import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import '../services/nearby_service.dart';
import '../services/connection_service.dart';
import '../services/permissions_service.dart';
import 'chats_list_screen.dart';
import 'profile_edit_screen.dart';
import 'public_profile_sheet.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  _RadarScreenState createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final NearbyService _nearbyService = NearbyService();
  final ConnectionService _connectionService = ConnectionService();
  bool _isScanning = false;
  List<NearbyUser> _nearbyUsers = [];
  StreamSubscription<List<NearbyUser>>? _usersSub;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _nearbyService.initialize('ZONE-User');

    // Escuchar usuarios descubiertos
    _usersSub = _nearbyService.discoveredUsersStream.listen((users) {
      setState(() {
        _nearbyUsers = users;
      });
    });
  }

  void _toggleRadar() async {
    setState(() {
      _isScanning = !_isScanning;
    });

    if (_isScanning) {
      // Solicitar permisos de Nearby Connections
      await PermissionsService.requestAllPermissions();
      await _nearbyService.startRadar();
      _animationController.repeat();
    } else {
      await _nearbyService.stopRadar();
      _animationController.reset();
      setState(() {
        _nearbyUsers.clear();
      });
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
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Avatar
              CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xFF00D2FF),
                child: Text(
                  user.userName.isNotEmpty ? user.userName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                user.userName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user.isConnected ? '🟢 Conectado' : '📡 Cerca de ti',
                style: TextStyle(
                  color: user.isConnected ? Colors.greenAccent : Colors.white54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Botón: Conectar / Mensaje
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (user.isConnected) {
                          Navigator.pop(context);
                          // Navegar al chat
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PublicProfileSheet(userName: user.userName),
                            ),
                          );
                        } else {
                          _connectionService.sendConnectionRequest(user.endpointId);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Solicitud enviada a ${user.userName}'),
                              backgroundColor: const Color(0xFF00D2FF),
                            ),
                          );
                        }
                      },
                      icon: Icon(
                        user.isConnected ? Icons.person : Icons.person_add,
                        color: Colors.black,
                      ),
                      label: Text(
                        user.isConnected ? 'Ver Perfil' : 'Conectar',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D2FF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
  void dispose() {
    _animationController.dispose();
    _nearbyService.stopRadar();
    _usersSub?.cancel();
    super.dispose();
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
          // Ondas del Radar Animadas
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
            
          // Cabecera superior con iconos y texto
          Positioned(
            top: 80,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Izquierda: Conversaciones
                IconButton(
                  icon: const Icon(Icons.message_outlined, color: Colors.white70, size: 32),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ChatsListScreen()),
                    );
                  },
                ),
                // Centro: Instrucción contextual
                Expanded(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Column(
                        key: ValueKey<bool>(_isScanning),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isScanning ? 'Buscando cercanos...' : 'Toca para iniciar',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (_isScanning && _nearbyUsers.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${_nearbyUsers.length} persona${_nearbyUsers.length > 1 ? 's' : ''} cerca',
                                style: const TextStyle(
                                  color: Color(0xFF00D2FF),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Derecha: Modificar Perfil
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
          ),

          // Renderizar los Avatares descubiertos en el radar
          ..._nearbyUsers.asMap().entries.map((entry) {
            final index = entry.key;
            final user = entry.value;
            // Distribuir los usuarios en un patrón circular
            final angle = (2 * pi / max(_nearbyUsers.length, 1)) * index - (pi / 2);
            final radius = screenSize.width * 0.28;
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
                          gradient: RadialGradient(
                            colors: user.isConnected
                                ? [Colors.greenAccent, Colors.green.shade700]
                                : [const Color(0xFF00D2FF), const Color(0xFF3A7BD5)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (user.isConnected
                                      ? Colors.greenAccent
                                      : const Color(0xFF00D2FF))
                                  .withOpacity(0.5),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            user.userName.isNotEmpty
                                ? user.userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          user.userName.length > 10
                              ? '${user.userName.substring(0, 10)}…'
                              : user.userName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // Botón central principal
          GestureDetector(
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
        ],
      )),
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
    
    // Dibujar tres anillos desfasados para dar efecto de ondas contínuas de radar
    for (int i = 0; i < 3; i++) {
      double currentProgress = (animationValue + (i * 0.33)) % 1.0;
      paint.color = const Color(0xFF00D2FF).withOpacity((1.0 - currentProgress).clamp(0.0, 1.0));
      canvas.drawCircle(center, maxRadius * currentProgress, paint);
    }
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
