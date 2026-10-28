import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/connectivity_service.dart';
import '../services/match_outbox_processor.dart';
import '../services/match_pair.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../services/zone_id_service.dart';
import '../utils/friendly_errors.dart';

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_screen.dart';
import '../widgets/user_avatar.dart';

class PublicProfileSheet extends StatefulWidget {
  final String userId; // El zone_id público
  final String? realUid; // El UID interno de Supabase
  final String userName;
  final String? instagramHandle;
  final String? facebookHandle;
  final String? tiktokHandle;
  final String? avatarUrl;

  const PublicProfileSheet({
    super.key,
    required this.userId,
    this.realUid,
    required this.userName,
    this.instagramHandle,
    this.facebookHandle,
    this.tiktokHandle,
    this.avatarUrl,
  });

  static void show(
    BuildContext context, {
    required String userId,
    String? realUid,
    required String userName,
    String? instagramHandle,
    String? facebookHandle,
    String? tiktokHandle,
    String? avatarUrl,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PublicProfileSheet(
        userId: userId,
        realUid: realUid,
        userName: userName,
        instagramHandle: instagramHandle,
        facebookHandle: facebookHandle,
        tiktokHandle: tiktokHandle,
        avatarUrl: avatarUrl,
      ),
    );
  }

  @override
  State<PublicProfileSheet> createState() => _PublicProfileSheetState();
}

class _PublicProfileSheetState extends State<PublicProfileSheet> {
  final _supabaseService = SupabaseService();
  final _zoneIdService = ZoneIdService();

  // 0: Initial, 1: Requesting, 2: Sent/Pending (server), 3: Accepted,
  // 4: Queued local (durable outbox, SIN matchId del servidor todavía).
  int _connectionState = 0;
  String? _currentMatchId;
  StreamSubscription<List<Map<String, dynamic>>>? _matchSubscription;
  StreamSubscription<SyncStatus>? _syncSubscription;

  bool _avatarIsPublic = true;
  List<dynamic> _galleryPhotos = [];

  @override
  void initState() {
    super.initState();
    _checkInitialMatchStatus();
    _fetchPrivacySettings();
    // PHASE 2.2.5: al completarse un ciclo de sync, re-leer el estado
    // canónico (la operación en cola puede haberse confirmado en servidor).
    _syncSubscription = SyncService().statusStream.listen((status) {
      if (status.state == SyncState.idle && mounted && _connectionState == 4) {
        _refreshAfterSync();
      }
    });
  }

  @override
  void dispose() {
    _matchSubscription?.cancel();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchPrivacySettings() async {
    if (widget.realUid == null) return;
    try {
      final res = await Supabase.instance.client
          .from('v_profile')
          .select('avatar_is_public, gallery_photos')
          .eq('id', widget.realUid!)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _avatarIsPublic = res['avatar_is_public'] ?? true;
          _galleryPhotos = List<dynamic>.from(res['gallery_photos'] ?? []);
        });
        _precacheVisibleImages();
      }
    } catch (e) {
      debugPrint('Error fetching privacy settings: $e');
    }
  }

  void _precacheVisibleImages() {
    // Z-002 · Decisión A (estricto server-side): sin bypass por conexión mesh.
    // El servidor (v_profile) ya NULIFICA avatar/galería no públicos; aquí solo
    // precacheamos lo que el servidor declaró visible.
    final urls = <String>[
      if (widget.avatarUrl != null &&
          widget.avatarUrl!.trim().isNotEmpty &&
          _avatarIsPublic)
        widget.avatarUrl!,
      ..._galleryPhotos
          .where((p) => p is Map && p['is_public'] == true)
          .map((photo) => (photo as Map)['url']?.toString() ?? '')
          .where((url) => url.trim().isNotEmpty),
    ];
    for (final url in urls) {
      precacheImage(NetworkImage(url), context).catchError((Object _) {});
    }
  }

  Future<void> _checkInitialMatchStatus() async {
    final myId = _zoneIdService.uid;
    final theirId = widget.realUid;
    if (myId == null || theirId == null) return;

    final match = await _supabaseService.getMatchStatus(myId, theirId);
    if (match != null) {
      _currentMatchId = match['id'];
      final status = match['status'];
      if (mounted) {
        setState(() {
          if (status == 'pending') {
            _connectionState = 2; // Sent/Pending
          } else if (status == 'accepted') {
            _connectionState = 3; // Accepted
          } else {
            _connectionState = 0; // Rejected or other
          }
        });
        _precacheVisibleImages();
      }
    }

    _listenToMatchChanges(myId, theirId);
  }

  void _listenToMatchChanges(String myId, String theirId) {
    // Cancelar suscripción previa (evita acumular listeners en re-checks).
    _matchSubscription?.cancel();
    _matchSubscription = Supabase.instance.client
        .from('matches')
        .stream(primaryKey: ['id'])
        .listen((data) {
          final relevantMatches = data
              .where(
                (m) =>
                    (m['requester_id'] == myId &&
                        m['receiver_id'] == theirId) ||
                    (m['requester_id'] == theirId && m['receiver_id'] == myId),
              )
              .toList();

          if (relevantMatches.isNotEmpty) {
            final match = relevantMatches.first;
            final status = match['status'];
            if (mounted) {
              setState(() {
                _currentMatchId = match['id'];
                if (status == 'pending') {
                  _connectionState = 2;
                } else if (status == 'accepted') {
                  _connectionState = 3;
                } else {
                  _connectionState = 0;
                }
              });
              _precacheVisibleImages();
            }
          }
        });
  }

  Future<void> _launchUrl(String platform, String? handle) async {
    if (handle == null || handle.isEmpty) return;

    // Sanitizar: solo alfanuméricos, guiones bajos y puntos (max 30 chars)
    final sanitized = handle
        .replaceAll(RegExp(r'[^a-zA-Z0-9_.]'), '')
        .substring(0, handle.length > 30 ? 30 : handle.length);

    if (sanitized.isEmpty) return;

    String url = '';
    if (platform == 'Instagram') {
      url = 'https://instagram.com/$sanitized';
    } else if (platform == 'Facebook') {
      url = 'https://facebook.com/$sanitized';
    } else if (platform == 'TikTok') {
      url = 'https://tiktok.com/@$sanitized';
    }

    if (url.isEmpty) return;

    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo abrir $url')));
      }
    }
  }

  void _handleConnectPressed() async {
    if (_connectionState == 3) {
      // Si ya está aceptado, entrar al chat inmediatamente
      if (_currentMatchId != null && widget.realUid != null) {
        Navigator.pop(context); // Cerrar el modal
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              matchId: _currentMatchId!,
              otherUserId: widget.realUid!,
              otherUserName: widget.userName,
              otherZoneId: widget.userId,
              otherAvatarUrl: widget.avatarUrl,
            ),
          ),
        );
      }
      return;
    }

    if (_connectionState == 0) {
      final myId =
          _zoneIdService.uid ?? await _zoneIdService.getStoredUid();
      if (!mounted) return;
      final theirId = widget.realUid;

      if (myId == null || theirId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: No se pudo identificar al usuario.'),
          ),
        );
        return;
      }

      setState(() => _connectionState = 1);

      try {
        final matchId = await _supabaseService.requestMatch(myId, theirId);
        if (!mounted) return;
        // PHASE 2.2.4 — seguridad de estado UI (bug NULL matchId): el estado
        // "pending" (2) SOLO existe con un identificador válido. Un resultado
        // nulo/vacío vuelve a idle (0) con error explícito — nunca se finge
        // "Solicitud enviada" sin matchId (con el realtime canónico, un
        // conflicto ya retorna el id existente en lugar de null).
        if (MatchPair.isValidMatchId(matchId)) {
          _currentMatchId = matchId;
          setState(() => _connectionState = 2);
        } else {
          // PHASE 2.2.5 — intent duradero en lugar de error estéril: se
          // encola la solicitud (deduplicada por operationId) y se muestra
          // estado local pendiente (4), NUNCA "enviada" sin confirmación.
          await _enqueueRequest(myId, theirId);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _connectionState = 0);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                FriendlyErrors.message(
                  e,
                  fallback: 'No se pudo enviar la solicitud.',
                ),
              ),
            ),
          );
        }
      }
    }
  }

  /// PHASE 2.2.5 — encola la solicitud como intent duradero (deduplicado por
  /// operationId determinista) y muestra estado local pendiente (4). Fail-closed:
  /// sin actor válido o identidad inválida, vuelve a idle con error.
  Future<void> _enqueueRequest(String myId, String theirId) async {
    try {
      final op = buildRequestOp(
        requester: myId,
        receiver: theirId,
        now: DateTime.now(),
      );
      await IsarMatchOperationStore().enqueue(op);
      // Intento inmediato (no-op sin red; urgente en reconexión).
      unawaited(SyncService().syncNow());
      if (!mounted) return;
      final offline = !ConnectivityService().hasRealInternet;
      setState(() => _connectionState = 4);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            offline
                ? 'Sin conexión: la solicitud se enviará automáticamente al reconectar.'
                : 'No se pudo contactar el servidor. Quedó en cola y se reintentará.',
          ),
        ),
      );
    } on InvalidMatchIdentityError {
      if (!mounted) return;
      setState(() => _connectionState = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo enviar la solicitud.')),
      );
    }
  }

  /// PHASE 2.2.5 — tras un ciclo de sync, reconcilia el estado en cola (4)
  /// con el servidor: confirmado ⇒ 2/3 con matchId real; operación fallida
  /// terminal y sin match ⇒ error + idle (reintentable tocando Conectar).
  Future<void> _refreshAfterSync() async {
    final myId = _zoneIdService.uid;
    final theirId = widget.realUid;
    if (myId == null || theirId == null) return;
    await _checkInitialMatchStatus();
    if (!mounted) return;
    if (_connectionState == 4 || _currentMatchId == null) {
      String low, high;
      try {
        low = MatchPair.canonicalLow(myId, theirId);
        high = MatchPair.canonicalHigh(myId, theirId);
      } on InvalidMatchIdentityError {
        return;
      }
      final store = IsarMatchOperationStore();
      final stillPending = await store.hasPendingForPair(low, high);
      final failed = await store.failedForPair(low, high);
      if (!stillPending && _currentMatchId == null) {
        if (mounted) {
          setState(() => _connectionState = 0);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                failed != null
                    ? 'No se pudo sincronizar la solicitud (${failed.lastErrorCode ?? 'error'}). Inténtalo de nuevo.'
                    : 'No se pudo enviar la solicitud. Inténtalo de nuevo.',
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasIg =
        widget.instagramHandle != null && widget.instagramHandle!.isNotEmpty;
    final hasFb =
        widget.facebookHandle != null && widget.facebookHandle!.isNotEmpty;
    final hasTiktok =
        widget.tiktokHandle != null && widget.tiktokHandle!.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 30),

          Row(
            children: [
              UserAvatar(
                // Z-002 (A estricto): sin bypass mesh. El servidor ya decidió.
                avatarUrl: _avatarIsPublic ? widget.avatarUrl : null,
                displayName: widget.userName,
                radius: 40,
                fallbackColor: Colors.grey.shade800,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${widget.userId.length >= 8 ? widget.userId.substring(0, 8) : widget.userId}...',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),

          if (hasIg || hasFb || hasTiktok) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Redes Públicas',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSocialIcon(
                  Icons.camera_alt,
                  'Instagram',
                  hasIg,
                  () => _launchUrl('Instagram', widget.instagramHandle),
                ),
                _buildSocialIcon(
                  Icons.facebook,
                  'Facebook',
                  hasFb,
                  () => _launchUrl('Facebook', widget.facebookHandle),
                ),
                _buildSocialIcon(
                  Icons.music_note,
                  'TikTok',
                  hasTiktok,
                  () => _launchUrl('TikTok', widget.tiktokHandle),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ] else ...[
            const Text(
              'Este usuario no ha compartido redes públicas.',
              style: TextStyle(
                color: Colors.white54,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 30),
          ],

          if (_galleryPhotos
              .where(
                (p) => p is Map && p['is_public'] == true,
              )
              .isNotEmpty) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Galería',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _galleryPhotos
                    .where(
                      (p) => p is Map && p['is_public'] == true,
                    )
                    .map((photo) {
                      return Container(
                        width: 100,
                        height: 120,
                        margin: const EdgeInsets.only(right: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            photo['url'].toString(),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => Container(
                              color: Colors.white10,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.white38,
                              ),
                            ),
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                color: Colors.white10,
                                alignment: Alignment.center,
                                child: const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    })
                    .toList(),
              ),
            ),
            const SizedBox(height: 30),
          ],

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _connectionState == 3
                  ? Colors.greenAccent
                  // PHASE 2.2.5 (4): en cola local — ámbar, distinto del
                  // pending confirmado (2, gris) y del idle (0, cian).
                  : (_connectionState == 4
                        ? Colors.orangeAccent
                        : (_connectionState == 0
                              ? const Color(0xFF00D2FF)
                              : Colors.grey.shade600)),
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _connectionState == 1
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    _connectionState == 3 ? Icons.chat : Icons.lock,
                    color: _connectionState == 1 ? Colors.white : Colors.black,
                    size: 20,
                  ),
            label: Text(
              _connectionState == 0
                  ? 'Conectar'
                  : _connectionState == 1
                  ? 'Enviando...'
                  : _connectionState == 2
                  ? 'Solicitud enviada, a la espera'
                  : _connectionState == 4
                  ? 'En cola · se enviará al conectar'
                  : 'Entrar al Chat',
              style: TextStyle(
                color: _connectionState == 1 ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            onPressed:
                (_connectionState == 1 ||
                        _connectionState == 2 ||
                        _connectionState == 4)
                    ? null
                    : _handleConnectPressed,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSocialIcon(
    IconData icon,
    String name,
    bool isVisible,
    VoidCallback onTap,
  ) {
    if (!isVisible) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: const Color(0xFF0F172A),
            child: Icon(icon, color: const Color(0xFF00D2FF)),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
