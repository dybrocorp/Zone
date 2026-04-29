import 'package:flutter/material.dart';
import 'dart:math';
import '../services/ble_service.dart';
import 'chats_list_screen.dart';
import 'profile_edit_screen.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  _RadarScreenState createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final BleDiscoveryService _bleService = BleDiscoveryService();
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _bleService.initialize();
  }

  void _toggleRadar() {
    setState(() {
      _isScanning = !_isScanning;
      if (_isScanning) {
        _bleService.startScanning();
        _bleService.startAdvertising();
      } else {
        _bleService.stopScanning();
        _bleService.stopAdvertising();
        _animationController.reset();
      }
    });
    
    if (_isScanning) {
      _animationController.repeat();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _bleService.stopScanning();
    _bleService.stopAdvertising();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Modern dark tone
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
                  size: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
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
                      child: Text(
                        _isScanning ? 'Buscando cercanos...' : 'Toca para iniciar',
                        key: ValueKey<bool>(_isScanning),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
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

          // Renderizar los Avatares descubiertos aquí (Se integrará luego)
          ..._bleService.discoveredUsers.map((user) {
             // Por ahora, lógica ficticia de posicionado aleatorio temporal si hubiera usuarios.
             // Aquí irían los iconos de las personas.
             return SizedBox.shrink();
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
