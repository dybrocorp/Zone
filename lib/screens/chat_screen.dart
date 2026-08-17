import 'dart:async';
import 'package:flutter/material.dart';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/zone_id_service.dart';
import '../services/chat_e2ee_service.dart';
import '../services/notification_service.dart';
import '../services/nearby_service.dart';
import '../services/connectivity_service.dart';
import '../services/isar_service.dart';
import '../widgets/user_avatar.dart';
import 'public_profile_sheet.dart';

class ChatScreen extends StatefulWidget {
  final String matchId;
  final String otherUserName;
  final String otherZoneId;
  final String? otherUserId;
  final String? otherAvatarUrl;

  const ChatScreen({
    super.key,
    required this.matchId,
    required this.otherUserName,
    required this.otherZoneId,
    this.otherUserId,
    this.otherAvatarUrl,
  });

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final _supabaseService = SupabaseService();
  final _zoneIdService = ZoneIdService();
  final _e2eeService = ChatE2EEService();
  final _nearbyService = NearbyService();
  final _connectivity = ConnectivityService();
  final _isar = IsarService();

  StreamSubscription? _meshSubscription;

  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isBlocked = false;
  String? _otherAvatarUrl;
  Map<String, dynamic>? _otherProfile;
  SecretKey? _sharedSecret;
  RealtimeChannel? _subscription;
  final Map<String, String> _decryptedByMessageId = {};

  bool _isOtherOnline = false;
  bool _isOtherTyping = false;
  Timer? _typingTimer;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    NotificationService.currentActiveMatchId = widget.matchId;
    _setupChat();
    _setupMeshListener();
  }

  void _setupMeshListener() {
    _meshSubscription = _nearbyService.incomingMessagesStream.listen((msg) {
      if (msg.sourceZoneId == widget.otherZoneId) {
        debugPrint('[ChatScreen] Mensaje Mesh recibido de ${msg.sourceZoneId}');

        final newMsg = {
          'id': 'mesh-${DateTime.now().millisecondsSinceEpoch}',
          'sender_id': widget.otherUserId ?? widget.otherZoneId,
          'match_id': widget.matchId,
          'text':
              msg.text, // Ya viene descifrado si NearbyService hizo su trabajo
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'transport': 'mesh',
        };

        if (mounted) {
          setState(() {
            _messages.add(newMsg);
            _decryptedByMessageId[newMsg['id']!] = msg.text;
          });
          _scrollToBottom();
        }
      }
    });
  }

  Future<void> _setupChat() async {
    _otherAvatarUrl = widget.otherAvatarUrl;

    try {
      // Siempre llamar a getOrCreate para asegurar que la sesión y las llaves estén restauradas
      await _zoneIdService.getOrCreate();
      final uid = _zoneIdService.uid;

      // VERIFICACIÓN DE SEGURIDAD: Si por algún motivo el par de llaves no está listo, forzarlo ahora.
      if (!_e2eeService.isInitialized) {
        debugPrint(
          '[ChatScreen] Par de llaves no inicializado. Intentando recuperación forzada...',
        );
        await _zoneIdService.ensureAuth();
      }

      if (uid == null || !_e2eeService.isInitialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Error de seguridad: Llaves no listas. Por favor, reinicia la app.',
              ),
            ),
          );
        }
        return;
      }

      // Ejecutar consultas en paralelo para mejorar velocidad
      final results = await Future.wait([
        _supabaseService.getBlockedUsers(uid),
        _supabaseService.getProfileByZoneId(widget.otherZoneId),
        _supabaseService.getMessages(widget.matchId),
      ]);

      final blockedList = results[0] as List<Map<String, dynamic>>;
      final otherProfile = results[1] != null
          ? Map<String, dynamic>.from(results[1] as Map)
          : null;
      final history = results[2] as List<Map<String, dynamic>>;

      final isBlockedByMe = blockedList.any((b) {
        final blockedId = b['blocked_id'] as String?;
        final users = b['users'] != null
            ? Map<String, dynamic>.from(b['users'] as Map)
            : null;
        return blockedId == widget.otherUserId ||
            blockedId == widget.otherZoneId ||
            users?['zone_id'] == widget.otherZoneId;
      });

      final localOtherProfile = await _isar.getProfile(widget.otherZoneId);

      if (otherProfile != null || localOtherProfile != null) {
        _otherProfile = otherProfile;
        _otherAvatarUrl ??=
            otherProfile?['avatar_url'] as String? ??
            localOtherProfile?.avatarUrl;
        final otherPubKeyBase64 =
            otherProfile?['public_key'] ??
            otherProfile?['publicKey'] ??
            localOtherProfile?.publicKey;
        if (otherPubKeyBase64 != null &&
            otherPubKeyBase64.toString().isNotEmpty) {
          try {
            final otherPubKey = _e2eeService.importPublicKeyFromBase64(
              otherPubKeyBase64.toString(),
            );
            if (otherPubKey != null) {
              _sharedSecret = await _e2eeService.computeSharedSecret(
                otherPubKey,
              );
            }
          } catch (e) {
            debugPrint('[ChatScreen] Error derivando secreto compartido: $e');
          }
        }
      }

      await _prefetchDecrypted(history);

      _subscription = _supabaseService.subscribeToMessages(
        widget.matchId,
        uid,
        (newMsg) async {
          final msgId = newMsg['id']?.toString();
          final senderId = newMsg['sender_id'];
          final myId = _zoneIdService.uid;

          debugPrint('[ChatScreen] Nuevo mensaje recibido: $msgId');

          if (_messages.any((m) => m['id'] == msgId)) return;

          if (senderId == myId) {
            final tempIndex = _messages.indexWhere(
              (m) =>
                  m['id'].toString().startsWith('temp-') &&
                  m['sender_id'] == myId,
            );
            if (tempIndex != -1) {
              await _prefetchDecrypted([newMsg]);
              if (mounted) {
                setState(() {
                  _messages[tempIndex] = newMsg;
                });
              }
              return;
            }
          }

          try {
            await _prefetchDecrypted([newMsg]);
          } catch (_) {}
          if (mounted) {
            setState(() => _messages.add(newMsg));
            _scrollToBottom();
          }
        },
        (isOnline) {
          if (mounted) setState(() => _isOtherOnline = isOnline);
        },
        (isTyping) {
          if (mounted) setState(() => _isOtherTyping = isTyping);
        },
      );

      if (mounted) {
        setState(() {
          _isBlocked = isBlockedByMe;
          _messages
            ..clear()
            ..addAll(history);
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al abrir el chat: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _prefetchDecrypted(List<Map<String, dynamic>> messages) async {
    if (_sharedSecret == null) return;
    for (final msg in messages) {
      final id = msg['id']?.toString();
      if (id == null || _decryptedByMessageId.containsKey(id)) continue;
      try {
        _decryptedByMessageId[id] = await _e2eeService.decryptMessage(
          msg['encrypted_content'] ?? '',
          msg['nonce'] ?? '',
          msg['mac'] ?? '',
          _sharedSecret!,
        );
        debugPrint('[ChatScreen] Mensaje $id descifrado con éxito');
      } catch (e) {
        debugPrint('[ChatScreen] Error descifrando mensaje $id: $e');
        _decryptedByMessageId[id] = 'Error de cifrado ($e)';
      }
    }
  }

  String _messagePreview(Map<String, dynamic> msg) {
    final id = msg['id']?.toString();
    if (id != null && _decryptedByMessageId.containsKey(id)) {
      return _decryptedByMessageId[id]!;
    }
    if (_sharedSecret == null) return 'Configurando cifrado seguro...';
    if (id == null) return 'Sincronizando id de mensaje...';
    return 'Descifrando mensaje...';
  }

  Future<void> _handleBlock() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          '¿Bloquear usuario?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'No podrá enviarte más mensajes y desaparecerá de tu radar.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'BLOQUEAR',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final myId = _zoneIdService.uid;
      final theirId = widget.otherUserId ?? widget.otherZoneId;
      if (myId != null) {
        await _supabaseService.blockUser(myId, theirId);
        if (mounted) {
          Navigator.pop(context); // Salir del chat
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Usuario bloqueado')));
        }
      }
    }
  }

  Future<void> _handleReport() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Reportar a ${widget.otherUserName}',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Describe el motivo...',
            hintStyle: TextStyle(color: Colors.white24),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text(
              'ENVIAR REPORTE',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (reason != null && reason.isNotEmpty) {
      final myId = _zoneIdService.uid;
      final theirId = widget.otherUserId ?? widget.otherZoneId;
      if (myId != null) {
        await _supabaseService.reportUser(myId, theirId, reason);
        await _supabaseService.blockUser(myId, theirId);
        if (mounted) {
          Navigator.pop(context); // Salir del chat
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Gracias por tu reporte. Hemos bloqueado al usuario.',
              ),
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    if (NotificationService.currentActiveMatchId == widget.matchId) {
      NotificationService.currentActiveMatchId = null;
    }
    _meshSubscription?.cancel();
    _subscription?.unsubscribe();
    _messageController.dispose();
    _typingTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sharedSecret == null) return;

    final uid = _zoneIdService.uid;
    if (uid == null) return;

    final controllerText = text;
    _messageController.clear();

    // ID temporal para la UI optimista
    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = {
      'id': tempId,
      'sender_id': uid,
      'match_id': widget.matchId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    // Guardar texto descifrado localmente para el mensaje optimista
    _decryptedByMessageId[tempId] = controllerText;

    if (mounted) {
      setState(() => _messages.add(tempMsg));
      _scrollToBottom();
    }

    try {
      // 1. Enviar vía MESH si estamos cerca (Máxima velocidad, Offline)
      bool sentViaMesh = false;
      if (_nearbyService.isPeerReachable(widget.otherZoneId)) {
        await _nearbyService.sendMeshMessage(
          widget.otherZoneId,
          controllerText,
        );
        sentViaMesh = true;
        debugPrint('[ChatScreen] Mensaje enviado vía Mesh');
      }

      // 2. Enviar vía SUPABASE si hay conexión (Persistencia y Nube)
      if (_connectivity.isOnline) {
        final encrypted = await _e2eeService.encryptMessage(
          controllerText,
          _sharedSecret!,
        );
        await _supabaseService.sendMessage(
          matchId: widget.matchId,
          senderId: uid,
          encryptedContent: encrypted['encrypted_content'],
          nonce: encrypted['nonce'],
          mac: encrypted['mac'],
        );
        debugPrint('[ChatScreen] Mensaje enviado a Supabase');
      } else if (!sentViaMesh) {
        // Si no hay mesh ni internet, el mensaje falló
        throw Exception('Sin conexión Mesh ni Internet');
      }

      // Marcar transporte en el mensaje optimista si fue solo mesh
      if (sentViaMesh && !_connectivity.isOnline) {
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m['id'] == tempId);
            if (idx != -1) _messages[idx]['transport'] = 'mesh';
          });
        }
      }
    } catch (e) {
      debugPrint('[ChatScreen] Error enviando mensaje: $e');
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m['id'] == tempId));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al enviar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            UserAvatar(
              avatarUrl: _otherAvatarUrl,
              displayName: widget.otherUserName,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.otherUserName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: _isOtherOnline
                            ? Colors.greenAccent
                            : Colors.white24,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isOtherOnline ? 'En línea' : 'Desconectado',
                        style: TextStyle(
                          color: _isOtherOnline
                              ? Colors.greenAccent
                              : Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.lock, size: 11, color: Colors.white24),
                      const SizedBox(width: 2),
                      const Text(
                        'E2EE',
                        style: TextStyle(color: Colors.white24, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onSelected: (value) {
              if (value == 'refresh') {
                setState(() => _isLoading = true);
                _setupChat();
              } else if (value == 'block') {
                _handleBlock();
              } else if (value == 'report') {
                _handleReport();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Text('Refrescar Chat'),
              ),
              const PopupMenuItem(
                value: 'block',
                child: Text('Bloquear Usuario'),
              ),
              const PopupMenuItem(
                value: 'report',
                child: Text('Reportar Usuario'),
              ),
            ],
          ),
        ],
      ),

      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            width: double.infinity,
            color: Colors.greenAccent.withValues(alpha: 0.1),
            child: const Text(
              '🔒 Los mensajes están cifrados de extremo a extremo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.greenAccent, fontSize: 12),
            ),
          ),
          if (_isBlocked)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              width: double.infinity,
              color: Colors.redAccent.withValues(alpha: 0.1),
              child: const Text(
                '🚫 HAS BLOQUEADO A ESTE USUARIO',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00D2FF)),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['sender_id'] == _zoneIdService.uid;

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (!isMe) ...[
                                  GestureDetector(
                                    onTap: () {
                                      PublicProfileSheet.show(
                                        context,
                                        userId: widget.otherZoneId,
                                        realUid:
                                            widget.otherUserId ??
                                            _otherProfile?['id'] as String?,
                                        userName: widget.otherUserName,
                                        avatarUrl: _otherAvatarUrl,
                                        instagramHandle:
                                            _otherProfile?['instagram_handle'],
                                        facebookHandle:
                                            _otherProfile?['facebook_handle'],
                                        tiktokHandle:
                                            _otherProfile?['tiktok_handle'],
                                      );
                                    },
                                    child: UserAvatar(
                                      avatarUrl: _otherAvatarUrl,
                                      displayName: widget.otherUserName,
                                      radius: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? const Color(0xFF00D2FF)
                                          : const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(16)
                                          .copyWith(
                                            bottomRight: isMe
                                                ? Radius.zero
                                                : null,
                                            bottomLeft: !isMe
                                                ? Radius.zero
                                                : null,
                                          ),
                                      gradient: isMe
                                          ? const LinearGradient(
                                              colors: [
                                                Color(0xFF00D2FF),
                                                Color(0xFF3A7BD5),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            )
                                          : null,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.1,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                        if (msg['transport'] == 'mesh')
                                          BoxShadow(
                                            color: const Color(
                                              0xFF00D2FF,
                                            ).withValues(alpha: 0.1),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          ),
                                      ],
                                      border: isMe
                                          ? null
                                          : Border.all(color: Colors.white10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: isMe
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _messagePreview(msg),
                                          style: TextStyle(
                                            color: isMe
                                                ? Colors.black
                                                : Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        if (msg['transport'] == 'mesh')
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black12,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.bolt,
                                                    size: 10,
                                                    color: Color(0xFF00D2FF),
                                                  ),
                                                  SizedBox(width: 2),
                                                  Text(
                                                    'MALLA SEGURA',
                                                    style: TextStyle(
                                                      fontSize: 8,
                                                      color: Color(0xFF00D2FF),
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (isMe) const SizedBox(width: 24),
                              ],
                            ),
                          );
                        },
                      ),
                      if (_isOtherTyping)
                        Positioned(
                          bottom: 4,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1E293B,
                              ).withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${widget.otherUserName} está escribiendo...',
                              style: const TextStyle(
                                color: Color(0xFF00D2FF),
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1E293B),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: !_isBlocked,
                      onChanged: (val) {
                        if (_subscription != null) {
                          final uid = _zoneIdService.uid;
                          if (uid != null) {
                            _supabaseService.sendTypingStatus(
                              _subscription!,
                              uid,
                              val.isNotEmpty,
                            );

                            _typingTimer?.cancel();
                            if (val.isNotEmpty) {
                              _typingTimer = Timer(
                                const Duration(seconds: 3),
                                () {
                                  _supabaseService.sendTypingStatus(
                                    _subscription!,
                                    uid,
                                    false,
                                  );
                                },
                              );
                            }
                          }
                        }
                      },
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _isBlocked
                            ? 'Usuario bloqueado'
                            : 'Mensaje seguro...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.black26,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: _isBlocked
                        ? Colors.grey
                        : const Color(0xFF00D2FF),
                    child: IconButton(
                      icon: const Icon(
                        Icons.send,
                        color: Colors.black,
                        size: 20,
                      ),
                      onPressed: _isBlocked ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
