import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';
import 'dart:async';

// Sustituir por las credenciales reales
const String supabaseUrl = 'https://leejpxwctnubihacudik.supabase.co';
const String supabaseAnonKey = 'sb_publishable_vl-aeN4Ior-GZ5YB45MFyA_KGxgfZjV';

Future<void> main() async {
  print('=============================================');
  print('ZONE - MASSS-DEVICE LOAD TESTING AUDIT SCRIPT');
  print('=============================================');

  // Inicializar cliente
  final client = SupabaseClient(supabaseUrl, supabaseAnonKey);
  
  // 1. Obtener nuestro usuario actual para inyectar los encuentros
  // En este script usaremos un usuario test si no hay credenciales, 
  // pero la simulación radica en golpear la tabla reports / encounters
  final uid = const Uuid().v4();
  final myZoneId = 'ZONE-TEST01';
  
  print('Generando ráfaga de 50 dispositivos simultáneos...');

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
        print('[SUCCESS] Insertado $fakeZoneId');
      } catch (e) {
        print('[ERROR] Error insertando $fakeZoneId: $e');
      }
    }));
  }

  await Future.wait(tasks);

  stopwatch.stop();
  print('=============================================');
  print('Auditoría completada. Tiempo total para 50 escrituras: ${stopwatch.elapsedMilliseconds} ms');
  print('=============================================');
}
