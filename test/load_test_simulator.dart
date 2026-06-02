import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';
import 'dart:async';

// Sustituir por las credenciales reales
const String supabaseUrl = 'https://leejpxwctnubihacudik.supabase.co';
const String supabaseAnonKey = 'sb_publishable_vl-aeN4Ior-GZ5YB45MFyA_KGxgfZjV';

Future<void> main() async {
  // Inicializar cliente
  final client = SupabaseClient(supabaseUrl, supabaseAnonKey);
  
  // 1. Obtener nuestro usuario actual para inyectar los encuentros
  // En este script usaremos un usuario test si no hay credenciales, 
  // pero la simulación radica en golpear la tabla reports / encounters
  final uid = const Uuid().v4();

  final stopwatch = Stopwatch()..start();
  final random = Random();

  List<Future<void>> tasks = [];

  for (int i = 0; i < 50; i++) {
    tasks.add(Future.microtask(() async {
      final fakeZoneId = 'ZONE-MOCK${random.nextInt(9999).toString().padLeft(4, '0')}';
      try {
        // Simulando un Insert masivo y simultáneo de encuentros
        await client.from('encounters').insert({
          'user_id': uid,
          'other_zone_id': fakeZoneId,
          'seen_at': DateTime.now().toIso8601String()
        });
      } catch (e) {
        // Error handling
      }
    }));
  }

  await Future.wait(tasks);

  stopwatch.stop();
}
