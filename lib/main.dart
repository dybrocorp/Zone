import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_screen.dart';
import 'services/permissions_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Inicializar Supabase
    await Supabase.initialize(
      url: 'https://leejpxwctnubihacudik.supabase.co',
      anonKey: 'sb_publishable_vl-aeN4Ior-GZ5YB45MFyA_KGxgfZjV',
    );
  } catch (e) {
    print('[Main] Error inicializando Supabase: $e');
  }

  // Lanzar la app inmediatamente. Los permisos se manejarán dentro o en paralelo.
  runApp(const ZoneApp());
  
  // Solicitar permisos en paralelo para no bloquear el arranque visual
  PermissionsService.requestAllPermissions().then((granted) {
    print('[Main] Permisos iniciales concedidos: $granted');
  }).catchError((e) {
    print('[Main] Error en permisos iniciales: $e');
  });
}

class ZoneApp extends StatelessWidget {
  const ZoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF00D2FF),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: const AuthScreen(),
    );
  }
}
