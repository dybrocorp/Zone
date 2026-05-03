import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import '../services/nearby_service.dart';
import '../services/supabase_service.dart';
import '../services/zone_id_service.dart';
import '../services/permissions_service.dart';
import '../services/mock_chat_service.dart';
import '../services/notification_service.dart';
import 'chats_list_screen.dart';
import 'profile_edit_screen.dart';
import 'public_profile_sheet.dart';
import 'settings_screen.dart';
import 'mock_chat_screen.dart';

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
  final MockChatService _mockChatService = MockChatService();
  
  bool _isScanning = false;
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

    // Inicializar con el ID de Supabase
    _nearbyService.initialize(_zoneIdService.uid ?? '');

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

    _addDebugBots();

    // Iniciar escuchas globales de notificaciones (mensajes/solicitudes)
    final uid = _zoneIdService.uid;
    if (uid != null) {
      _supabaseService.startGlobalNotificationListener(uid);
    }
  }

  void _addDebugBots() {
    // Solo añadimos bots si no están ya en la lista
    if (!_nearbyUsers.any((u) => u.zoneId == 'ZONE-DEBUG-1')) {
      _nearbyUsers.add(NearbyUser(
        endpointId: 'debug_bot_1',
        token: 'TOKEN1',
        userName: 'Ana (Bot)',
        zoneId: 'ZONE-DEBUG-1',
        profile: {
          'id': 'debug-uuid-1',
          'avatar_url': 'https://i.pravatar.cc/150?img=5',
        }
      ));
    }
    if (!_nearbyUsers.any((u) => u.zoneId == 'ZONE-DEBUG-2')) {
      _nearbyUsers.add(NearbyUser(
        endpointId: 'debug_bot_2',
        token: 'TOKEN2',
        userName: 'Carlos (Bot)',
        zoneId: 'ZONE-DEBUG-2',
        profile: {
          'id': 'debug-uuid-2',
          'avatar_url': 'https://i.pravatar.cc/150?img=11',
        }
      ));
    }
  }

  void _toggleRadar() async {
    if (!_isScanning) {
      bool granted = await PermissionsService.requestAllPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Por favor, activa el Bluetooth y la Ubicación para usar el radar.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      setState(() {
        _isScanning = true;
      });
      await _nearbyService.startRadar();
      _animationController.repeat();
    } else {
      setState(() {
        _isScanning = false;
        _nearbyUsers.clear();
      });
      await _nearbyService.stopRadar();
      _animationController.reset();
    }
  }

  void _onUserTapped(NearbyUser user) {
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
                        
                        if (user.zoneId.startsWith('ZONE-DEBUG-')) {
                          // Persistir localmente para que aparezca en la bandeja
                          await _mockChatService.activateMockChat(
                            user.zoneId, 
                            user.userName, 
                            profile?['avatar_url']
                          );

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('¡${user.userName} aceptó de inmediato!'),
                              backgroundColor: const Color(0xFF00D2FF),
                              duration: const Duration(milliseconds: 1500),
                            ),
                          );
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MockChatScreen(
                                botName: user.userName,
                                zoneId: user.zoneId,
                                avatarUrl: profile?['avatar_url'],
                              ),
                            ),
                          );
                          return;
                        }

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
                          if (_isScanning && _nearbyUsers.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${_nearbyUsers.length} persona${_nearbyUsers.length > 1 ? 's' : ''} cerca',
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
                            gradient: const RadialGradient(
                              colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00D2FF).withOpacity(0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                            image: user.profile?['avatar_url'] != null
                              ? DecorationImage(
                                  image: NetworkImage(user.profile!['avatar_url']),
                                  fit: BoxFit.cover,
                                )
                              : null,
                          ),
                          child: user.profile?['avatar_url'] == null 
                            ? Center(
                                child: Text(
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
                          child: Text(
                            user.userName,
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            GestureDetector(
              onTap: _toggleRadar,
              onLongPress: () {
                // MODO DEBUG: Al dejar pulsado, inyectamos burbujas falsas para testear diseño y chats
                setState(() {
                  _addDebugBots();
                  
                  // Notificar descubrimiento si es modo debug y bajamos la app
                  if (_lastLifecycleState != AppLifecycleState.resumed) {
                    NotificationService().showDiscoveryNotification('Ana (Bot)');
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bots de prueba añadidos al mapa'), duration: Duration(milliseconds: 1000)),
                );
              },
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
          ],
        ),
      ),
    );
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
