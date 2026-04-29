import 'package:flutter/material.dart';
import 'profile_setup_screen.dart';
import 'dart:math';
import 'login_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String? _generatedId;
  
  // Controladores del "Splash Screen" (Bienvenida animada)
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _showSplash = true;

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
    // 1. Aparece suavemente el logo
    await _fadeController.forward();
    // 2. Se mantiene brillante un par de segundos
    await Future.delayed(const Duration(seconds: 2));
    // 3. Pasa al menú de login/registro
    if (mounted) {
      setState(() {
        _showSplash = false;
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  String _generateZoneId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    String code = String.fromCharCodes(Iterable.generate(
        8, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    return 'ZONE-$code';
  }

  Future<void> _startRegistration() async {
    setState(() {
      _isLoading = true;
      _generatedId = _generateZoneId();
    });

    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(generatedId: _generatedId!),
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
          // Indicador de carga sutil para la bienvenida
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
      // Este BlendMode toma tu imagen de fondo negro y hace que el negro se
      // vuelva transparente dejando que se amolde al color azul oscuro (Scaffold)
      colorFilter: const ColorFilter.mode(Color(0xFF0F172A), BlendMode.lighten),
      child: Image.asset(
        'assets/logo.jpg',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Si no encuentra la imagen (porque no la hemos guardado en disco), usa el icono
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
        _buildLogo(size: 150), // Logo más pequeño en la pantalla de opciones
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
          'Conecta localmente. Habla seguro.',
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 60),
        if (_isLoading) ...[
          const CircularProgressIndicator(color: Color(0xFF00D2FF)),
          const SizedBox(height: 20),
          const Text('Asignando ID de Perfil...', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Text(
            _generatedId ?? '',
            style: const TextStyle(
              color: Color(0xFF00D2FF), 
              fontSize: 24, 
              fontWeight: FontWeight.bold, 
              letterSpacing: 2
            ),
          ),
        ] else ...[
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D2FF),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _startRegistration,
            child: const Text('Comenzar Registro', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              side: const BorderSide(color: Color(0xFF00D2FF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _login,
            child: const Text('Ya tengo una cuenta', style: TextStyle(color: Color(0xFF00D2FF), fontSize: 16)),
          )
        ]
      ],
    );
  }
}
