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
    await Future.delayed(const Duration(seconds: 2));

    // 1. Verificar si ya existe un ID guardado localmente
    final hasLocal = await _zoneIdService.hasLocalID();
    
    if (hasLocal) {
      // 2. Intentar restaurar sesión y verificar perfil
      final profile = await _zoneIdService.getMyProfile();
      if (!mounted) return;

      if (profile != null) {
        // ID válido y cuenta cargada -> Radar directo
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RadarScreen()),
        );
        return;
      }
    }

    // Si no hay ID o el perfil no carga -> Mostrar menú de inicio
    setState(() { _showSplash = false; });
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
          _buildLogo(size: 250),
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
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Color(0xFF0F172A), BlendMode.lighten),
      child: Image.asset(
        'assets/logo.jpg',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(Icons.wifi_tethering, size: size, color: const Color(0xFF00D2FF));
        },
      ),
    );
  }

  Widget _buildAuthContent() {
    return Column(
      key: const ValueKey('auth_menu'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLogo(size: 150),
        const SizedBox(height: 30),
        const Text(
          'ZONE',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
            color: Colors.white,
          ),
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
            child: const Text('Ya tengo un ZONE-ID', style: TextStyle(color: Color(0xFF00D2FF), fontSize: 16)),
          )
        ]
      ],
    );
  }
}
