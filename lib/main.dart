import 'package:flutter/material.dart';
import 'screens/initial_loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZoneApp());
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
      home: const InitialLoadingScreen(),
    );
  }
}
