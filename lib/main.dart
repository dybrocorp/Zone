import 'dart:async';
import 'package:flutter/material.dart';
import 'screens/initial_loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[FLUTTER_ERROR] ${details.exception}');
    debugPrint('[FLUTTER_ERROR] Stack: ${details.stack}');
  };

  runZonedGuarded(() {
    runApp(const ZoneApp());
  }, (error, stackTrace) {
    debugPrint('[ZONE_ERROR] $error');
    debugPrint('[ZONE_ERROR] Stack: $stackTrace');
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
      home: const InitialLoadingScreen(),
    );
  }
}
