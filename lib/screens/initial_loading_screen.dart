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
    debugPrint('[Startup] Iniciando a las ${start.toIso8601String()}');

    try {
      // 0. Variables de entorno
      await dotenv.load(fileName: '.env');

      // 1. Conectividad (rápida, no requiere I/O)
      setState(() { _loadingText = 'Verificando red...'; _progress = 0.15; });
      await ConnectivityService().initialize();

      // 2 + 3. Isar y Seguridad P2P en PARALELO para ahorrar tiempo
      setState(() { _loadingText = 'Preparando identidad segura...'; _progress = 0.45; });
      await Future.wait([
        IsarService().initialize(),
        P2PSecurityService().initialize(),
      ]);
      debugPrint('[Startup] Isar + P2P OK (${DateTime.now().difference(start).inMilliseconds}ms)');

      // 4. Supabase
      setState(() { _loadingText = 'Conectando con la nube...'; _progress = 0.8; });
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );
      debugPrint('[Startup] Supabase OK (${DateTime.now().difference(start).inMilliseconds}ms)');

      // 5. Sync en background (no bloquea la UI)
      SyncService().initialize();

      setState(() { _loadingText = 'Listo'; _progress = 1.0; });

      // Breve retraso para suavidad visual
      await Future.delayed(const Duration(milliseconds: 200));

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
    } catch (e) {
      debugPrint('[Startup] ERROR CRÍTICO: $e');
      if (mounted) {
        setState(() {
          _loadingText = 'Error al iniciar. Reintenta por favor.';
          _progress = 0.0;
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
              'assets/logo.png',
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
            if (_progress > 0 && _progress < 1.0)
              SizedBox(
                width: 200,
                height: 4,
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00D2FF)),
                ),
              )
            else if (_progress == 0.0 && _loadingText.contains('Error'))
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: ElevatedButton.icon(
                  onPressed: _startInitialization,
                  icon: const Icon(Icons.refresh, color: Colors.black),
                  label: const Text('Reintentar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D2FF),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
