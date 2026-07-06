import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/connectivity_service.dart';
import '../services/isar_service.dart';
import '../services/p2p_security_service.dart';
import '../services/sync_service.dart';
import 'auth_screen.dart';

class InitialLoadingScreen extends StatefulWidget {
  const InitialLoadingScreen({super.key});

  @override
  State<InitialLoadingScreen> createState() => _InitialLoadingScreenState();
}

class _InitialLoadingScreenState extends State<InitialLoadingScreen> {
  String _loadingText = 'Iniciando sistemas...';
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  Future<void> _startInitialization() async {
    final start = DateTime.now();
    print('[Startup] Iniciando carga de servicios a las ${start.toIso8601String()}');

    try {
      // 0. Cargar variables de entorno
      await dotenv.load(fileName: '.env');

      // 1. Conectividad
      setState(() {
        _loadingText = 'Verificando red...';
        _progress = 0.2;
      });
      await ConnectivityService().initialize();
      print('[Startup] Connectivity OK (${DateTime.now().difference(start).inMilliseconds}ms)');

      // 2. Isar Database
      setState(() {
        _loadingText = 'Cargando base de datos local...';
        _progress = 0.4;
      });
      await IsarService().initialize();
      print('[Startup] Isar OK (${DateTime.now().difference(start).inMilliseconds}ms)');

      // 3. Seguridad P2P
      setState(() {
        _loadingText = 'Asegurando identidad P2P...';
        _progress = 0.6;
      });
      await P2PSecurityService().initialize();
      print('[Startup] Security OK (${DateTime.now().difference(start).inMilliseconds}ms)');

      // 4. Supabase
      setState(() {
        _loadingText = 'Conectando con la nube...';
        _progress = 0.8;
      });
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );
       print('[Startup] Supabase OK (${DateTime.now().difference(start).inMilliseconds}ms)');

      // 5. Sync
      SyncService().initialize();
      
      setState(() {
        _loadingText = 'Listo';
        _progress = 1.0;
      });

      // Breve retraso para suavidad visual
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
    } catch (e) {
      print('[Startup] ERROR CRÍTICO durante la carga: $e');
      if (mounted) {
        setState(() {
          _loadingText = 'Error al iniciar. Reintenta por favor.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png', // Asegúrate de que existe o usa un Icon como fallback
              width: 120,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.radar,
                size: 80,
                color: Color(0xFF00D2FF),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              _loadingText,
              style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              height: 4,
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00D2FF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
