import 'package:flutter/material.dart';
import 'profile_setup_screen.dart';
import 'radar_screen.dart';
import 'dart:math';
import 'login_screen.dart';
import '../services/zone_id_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String? _generatedId;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _showSplash = true;

  final _zoneIdService = ZoneIdService();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_fadeController);
    _startSplash();
  }

  void _startSplash() async {
    await _fadeController.forward();
    
    // 1. Verificar si ya existe un ID guardado localmente
    final hasLocal = await _zoneIdService.hasLocalID();
    
    if (hasLocal) {
      try {
        // Restaurar sesión de fondo
        await _zoneIdService.getOrCreate();
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const RadarScreen()),
          );
        }
        return;
      } catch (e) {
        print('[AuthScreen] Error restaurando sesión automática: $e');
      }
    }

    // 2. Si no hay ID o falló la restauración -> Esperar un momento y mostrar menú
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() { _showSplash = false; });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _startRegistration() async {
    setState(() { _isLoading = true; });

    // Generar/obtener ZONE-ID y registrar en Supabase
    final zoneId = await _zoneIdService.getOrCreate();
    setState(() { _generatedId = zoneId; });

    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(generatedId: zoneId),
      ),
    );
  }

  void _login() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            child: _showSplash ? _buildSplash() : _buildAuthContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildSplash() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        key: const ValueKey('splash'),
        children: [
          _buildLogo(size: 300),
          const SizedBox(height: 20),
          const CircularProgressIndicator(
            color: Color(0xFF00D2FF),
            strokeWidth: 2,
          )
        ],
      ),
    );
  }

  Widget _buildLogo({double size = 150}) {
    return Image.asset(
      'assets/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Icon(Icons.wifi_tethering, size: size, color: const Color(0xFF00D2FF));
      },
    );
  }

  Widget _buildAuthContent() {
    return Column(
      key: const ValueKey('auth_menu'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLogo(size: 200),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'ZON',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            // La "E" estilizada con 3 líneas
            Column(
              children: [
                Container(width: 25, height: 4, decoration: BoxDecoration(color: const Color(0xFF00D2FF), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 5),
                Container(width: 25, height: 4, decoration: BoxDecoration(color: const Color(0xFF00D2FF), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 5),
                Container(width: 25, height: 4, decoration: BoxDecoration(color: const Color(0xFF00D2FF), borderRadius: BorderRadius.circular(2))),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Conoce Personas Que Están Cerca De Ti, Sin La Presión De Hablar En Persona',
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 60),
        if (_isLoading) ...[
          const CircularProgressIndicator(color: Color(0xFF00D2FF)),
          const SizedBox(height: 20),
          const Text('Generando tu ID seguro...', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Text(
            _generatedId ?? '',
            style: const TextStyle(
              color: Color(0xFF00D2FF),
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ] else ...[
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D2FF),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _startRegistration,
            child: const Text('Comenzar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              side: const BorderSide(color: Color(0xFF00D2FF)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _login,
            child: const Text('Ya tengo un ID', style: TextStyle(color: Color(0xFF00D2FF), fontSize: 16)),
          )
        ]
      ],
    );
  }
}
