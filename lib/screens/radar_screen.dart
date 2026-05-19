import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import '../config/radar_config.dart';
import '../services/nearby_service.dart';
import '../services/supabase_service.dart';
import '../services/zone_id_service.dart';
import '../services/permissions_service.dart';
import '../services/notification_service.dart';
import '../services/premium_service.dart';
import 'donations_screen.dart';
import 'chats_list_screen.dart';
import 'profile_edit_screen.dart';
import 'public_profile_sheet.dart';
import 'settings_screen.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({Key? key}) : super(key: key);

  @override
  _RadarScreenState createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _animationController;
  final NearbyService _nearbyService = NearbyService();
  final SupabaseService _supabaseService = SupabaseService();
  final ZoneIdService _zoneIdService = ZoneIdService();
  
  bool _isScanning = false;
  bool _isPremium = false;
  List<NearbyUser> _nearbyUsers = [];
  StreamSubscription<List<NearbyUser>>? _usersSub;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _initRadar();
    WidgetsBinding.instance.addObserver(this);
  }

  AppLifecycleState _lastLifecycleState = AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycleState = state;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _usersSub?.cancel();
    super.dispose();
  }

  Future<void> _initNotifications() async {
    final ns = NotificationService();
    await ns.init();
    await ns.requestPermissions();
  }

  Future<void> _initRadar() async {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    // Asegurarse de que el ID esté cargado
    String? uid = _zoneIdService.uid;
    if (uid == null || uid.isEmpty) {
      // Intentar restaurar sesión si por algún motivo se perdió el UID en memoria
      await _zoneIdService.getOrCreate();
      uid = _zoneIdService.uid;
    }

    // Inicializar con el ID de Supabase
    if (uid != null && uid.isNotEmpty) {
      await _nearbyService.initialize(uid);
    } else {
      print('[RadarScreen] Error: No se pudo obtener el UID del usuario.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de perfil. Por favor, reinicia la app.')),
        );
      }
    }

    // Escuchar usuarios descubiertos
    _usersSub = _nearbyService.discoveredUsersStream.listen((users) {
      if (mounted) {
        // Notificar si la app está minimizada y hay nuevos usuarios
        if (_lastLifecycleState != AppLifecycleState.resumed && users.length > _nearbyUsers.length) {
          NotificationService().showDiscoveryNotification(users.last.userName);
        }
        setState(() {
          _nearbyUsers = users;
        });
      }
    });

    // Cargar estado Premium
    final premium = await PremiumService.instance.loadPremiumStatus();
    if (mounted) setState(() => _isPremium = premium);

    // Iniciar escuchas globales de notificaciones (mensajes/solicitudes)
    if (uid != null) {
      _supabaseService.startGlobalNotificationListener(uid);
    }
  }

  void _toggleRadar() async {
    if (!_isScanning) {
      // Feedback visual inmediato al tocar el botón central.
      setState(() => _isScanning = true);
      _animationController.repeat();

      final granted = await PermissionsService.requestAllPermissions();
      if (!granted) {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _nearbyUsers.clear();
          });
          _animationController.reset();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Por favor, activa el Bluetooth y la Ubicación para usar el radar.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final started = await _nearbyService.startRadar();
      if (!started) {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _nearbyUsers.clear();
          });
          _animationController.reset();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo activar el radar. Comprueba tu conexión e inténtalo de nuevo.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    } else {
      setState(() {
        _isScanning = false;
        _nearbyUsers.clear();
      });
      _animationController.reset();
      await _nearbyService.stopRadar();
    }
  }

  void _onUserTapped(NearbyUser user) {
    // Verificar si el usuario está bloqueado por premium
    final isLocked = !_isPremium && (user.distanceMeters ?? 0) > RadarConfig.maxFreeDiscoveryRadiusMeters;

    if (isLocked) {
      _showPremiumLockSheet();
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final profile = user.profile;
        final hasIg = profile?['ig_visible'] == true && profile?['instagram_handle'] != null;
        final hasFb = profile?['fb_visible'] == true && profile?['facebook_handle'] != null;
        final hasTiktok = profile?['tiktok_visible'] == true && profile?['tiktok_handle'] != null;

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xFF00D2FF),
                backgroundImage: profile?['avatar_url'] != null ? NetworkImage(profile!['avatar_url']) : null,
                child: profile?['avatar_url'] == null
                    ? Text(
                        user.userName.isNotEmpty ? user.userName[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                user.userName,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                user.zoneId,
                style: const TextStyle(color: Color(0xFF00D2FF), fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        PublicProfileSheet.show(
                          context,
                          userId: user.zoneId,
                          realUid: profile?['id'],
                          userName: user.userName,
                          instagramHandle: profile?['instagram_handle'],
                          facebookHandle: profile?['facebook_handle'],
                          tiktokHandle: profile?['tiktok_handle'],
                          avatarUrl: profile?['avatar_url'],
                        );
                      },
                      icon: const Icon(Icons.person, color: Colors.black),
                      label: const Text('Ver Perfil', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D2FF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);

                        final myId = _zoneIdService.uid;
                        final theirId = profile?['id'];
                        if (myId != null && theirId != null) {
                          await _supabaseService.requestMatch(myId, theirId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Solicitud de chat enviada a ${user.userName}'),
                              backgroundColor: const Color(0xFF00D2FF),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.message, color: Color(0xFF00D2FF)),
                      label: const Text('Conectar', style: TextStyle(color: Color(0xFF00D2FF), fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF00D2FF)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SizedBox.expand(
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isScanning)
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return CustomPaint(
                    size: Size(screenSize.width, screenSize.height),
                    painter: RadarPainter(_animationController.value),
                  );
                },
              ),
            Positioned(
              top: 80,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.message_outlined, color: Colors.white70, size: 32),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ChatsListScreen()),
                      );
                    },
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isScanning ? 'Buscando cercanos...' : 'Toca para iniciar',
                            style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          if (_isScanning)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _nearbyUsers.isEmpty
                                    ? 'Radio: ${_nearbyService.discoveryRadiusMeters.round()} m'
                                    : '${_nearbyUsers.length} persona${_nearbyUsers.length > 1 ? 's' : ''} · ${_nearbyService.discoveryRadiusMeters.round()} m',
                                style: const TextStyle(color: Color(0xFF00D2FF), fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 28),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.person_outline, color: Colors.white70, size: 32),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ..._nearbyUsers.asMap().entries.map((entry) {
              final index = entry.key;
              final user = entry.value;
              
              // Angulo para esparcirlos circularmente
              final angle = (2 * pi / max(_nearbyUsers.length, 1)) * index - (pi / 2);
              
              // Radio pseudo-aleatorio basado en su ID para que salgan a diferentes distancias (entre 15% y 40% del ancho)
              final random = Random(user.endpointId.hashCode);
              final radius = screenSize.width * (0.15 + random.nextDouble() * 0.25);
                   final offsetX = screenSize.width / 2 + radius * cos(angle) - 24;
              final offsetY = screenSize.height / 2 + radius * sin(angle) - 24;

              final isLocked = !_isPremium && (user.distanceMeters ?? 0) > RadarConfig.maxFreeDiscoveryRadiusMeters;

              return Positioned(
                left: offsetX,
                top: offsetY,
                child: GestureDetector(
                  onTap: () => _onUserTapped(user),
                  child: AnimatedOpacity(
                    opacity: _isScanning ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 500),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: isLocked 
                              ? const RadialGradient(colors: [Colors.grey, Colors.blueGrey])
                              : const RadialGradient(colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)]),
                            boxShadow: [
                              BoxShadow(
                                color: (isLocked ? Colors.white10 : const Color(0xFF00D2FF)).withOpacity(0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                            image: (user.profile?['avatar_url'] != null && !isLocked)
                              ? DecorationImage(
                                  image: NetworkImage(user.profile!['avatar_url']),
                                  fit: BoxFit.cover,
                                )
                              : null,
                          ),
                          child: (user.profile?['avatar_url'] == null || isLocked)
                            ? Center(
                                child: isLocked 
                                  ? const Icon(Icons.lock, color: Colors.white, size: 20)
                                  : Text(
                                      user.userName.isNotEmpty ? user.userName[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                    ),
                              )
                            : null,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isLocked ? 'Premium' : user.userName,
                                style: TextStyle(
                                  color: isLocked ? const Color(0xFF00D2FF) : Colors.white70, 
                                  fontSize: 10,
                                  fontWeight: isLocked ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              if (user.distanceMeters != null)
                                Text(
                                  RadarConfig.formatDistance(user.distanceMeters),
                                  style: const TextStyle(color: Color(0xFF00D2FF), fontSize: 9),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleRadar,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _isScanning ? 120 : 100,
                height: _isScanning ? 120 : 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)],
                  ),
                  boxShadow: [
                    if (_isScanning)
                      BoxShadow(
                        color: const Color(0xFF00D2FF).withOpacity(0.5),
                        blurRadius: 40,
                        spreadRadius: 10,
                      )
                  ],
                ),
                child: Icon(
                  _isScanning ? Icons.wifi_tethering : Icons.power_settings_new,
                  color: Colors.white,
                  size: _isScanning ? 50 : 40,
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              child: TextButton.icon(
                onPressed: _openDonations,
                icon: const Icon(Icons.favorite, color: Colors.pinkAccent),
                label: const Text('Donaciones', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white10,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPremiumLockSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_person_rounded, size: 64, color: Color(0xFF00D2FF)),
            const SizedBox(height: 16),
            const Text(
              'Usuario fuera de rango',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'La versión gratuita solo permite ver perfiles a menos de ${RadarConfig.maxFreeDiscoveryRadiusMeters.round()} metros. ¡Pásate a Premium para desbloquear todo el radar!',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _openDonations();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D2FF),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Ver Membresías', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _openDonations() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DonationsScreen()),
    );
    // Recargar estado premium al volver
    final premium = await PremiumService.instance.loadPremiumStatus();
    if (mounted) setState(() => _isPremium = premium);
  }
}

class RadarPainter extends CustomPainter {
  final double animationValue;
  RadarPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFF00D2FF).withOpacity((1.0 - animationValue).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double maxRadius = sqrt(size.width * size.width + size.height * size.height) / 1.5;
    for (int i = 0; i < 3; i++) {
      double currentProgress = (animationValue + (i * 0.33)) % 1.0;
      paint.color = const Color(0xFF00D2FF).withOpacity((1.0 - currentProgress).clamp(0.0, 1.0));
      canvas.drawCircle(center, maxRadius * currentProgress, paint);
    }
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) => oldDelegate.animationValue != animationValue;
}
