// Z-203 (FASE 1.6): las credenciales ya NO están hardcodeadas (eran de un
// proyecto ajeno/apagado). Se leen del entorno en tiempo de ejecución:
//   $env:SUPABASE_URL / $env:SUPABASE_ANON_KEY
// Si faltan, el script aborta sin golpear ninguna instancia.
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';
import 'dart:async';

Future<void> main() async {
  final supabaseUrl = Platform.environment['SUPABASE_URL'];
  final supabaseAnonKey = Platform.environment['SUPABASE_ANON_KEY'];
  if (supabaseUrl == null || supabaseUrl.isEmpty ||
      supabaseAnonKey == null || supabaseAnonKey.isEmpty) {
    stdout.writeln(
      '[load_test_simulator] Faltan SUPABASE_URL / SUPABASE_ANON_KEY en el entorno.',
    );
    exit(1);
  }

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
