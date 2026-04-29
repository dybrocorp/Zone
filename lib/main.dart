import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';
import 'services/permissions_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Solicitamos permisos al arranque temporalmente para asegurar el BLE
  await PermissionsService.requestBlePermissions();
  
  runApp(const ZoneApp());
}

class ZoneApp extends StatelessWidget {
  const ZoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zone Social',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF00D2FF),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: const AuthScreen(),
    );
  }
}
