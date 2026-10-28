/// PHASE 2.2.3 — Encounter idempotency: tests UNIT.
///
/// Matriz sobre la identidad canónica (`lib/services/encounter_key.dart`):
/// 1. A ve B una vez → un encuentro (clave canónica presente).
/// 2. A ve B repetidamente (mismo bucket) → un encuentro lógico.
/// 3. B ve A → MISMA identidad canónica.
/// 4. Orden A/B invertido → misma clave.
/// 5. Creación duplicada concurrente → un solo registro lógico.
/// 6. Reinicio → la deduplicación se mantiene (derivación stateless).
/// 7. Creación offline → recuperable (derivación 100% local, sin I/O).
/// 8. A↔C no relacionado → clave distinta.
/// 9. Distinto bucket de tiempo/sesión → separado correctamente.
/// 10. Ningún material privado aparece en la clave.
/// 11. Identidad malformada/incompleta falla cerrado.
/// 12. Los datos de encuentros existentes siguen legibles (vía legacy).
///
/// Sin Isar nativo ni red: lógica pura + contrato de unicidad simulado con
/// un Set (en producción lo imponen el índice único Postgres y la writeTxn).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/services/encounter_key.dart';

const String _zoneA = 'ZONE-A1B2C3D4';
const String _zoneB = 'ZONE-E5F6A7B8';
const String _zoneC = 'ZONE-99999999';

void main() {
  group('1./2. avistamiento único y repetido', () {
    test('A ve B una vez → clave canónica con prefijo de versión', () async {
      final key = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: DateTime.utc(2026, 10, 8, 18, 12),
      );
      expect(key, startsWith('ZEN-1:'));
      expect(key, matches(RegExp(r'^ZEN-1:[0-9a-f]{64}$')));
    });

    test('A ve B repetidamente en el mismo bucket → MISMA clave', () async {
      final first = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: DateTime.utc(2026, 10, 8, 18, 5),
      );
      final second = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: DateTime.utc(2026, 10, 8, 18, 55),
      );
      expect(second, first);
    });
  });

  group('3./4. convergencia bilateral e independencia del orden', () {
    test('B ve A → misma identidad que A ve B', () async {
      final fromA = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: DateTime.utc(2026, 10, 8, 18, 12),
      );
      final fromB = await EncounterKey.canonicalKey(
        zoneA: _zoneB,
        zoneB: _zoneA,
        seenAt: DateTime.utc(2026, 10, 8, 18, 40),
      );
      expect(fromB, fromA);
    });

    test('orden de argumentos invertido → misma clave', () async {
      final t = DateTime.utc(2026, 10, 8, 9, 0);
      expect(
        await EncounterKey.canonicalKey(zoneA: _zoneB, zoneB: _zoneA, seenAt: t),
        await EncounterKey.canonicalKey(zoneA: _zoneA, zoneB: _zoneB, seenAt: t),
      );
    });
  });

  group('5. duplicados concurrentes → un registro lógico', () {
    test('N derivaciones concurrentes colapsan en una sola clave', () async {
      final t = DateTime.utc(2026, 10, 8, 18, 12);
      final keys = await Future.wait(
        List.generate(
          20,
          (i) => EncounterKey.canonicalKey(
            // Mitad de los callbacks con el orden invertido (dos endpoints).
            zoneA: i.isEven ? _zoneA : _zoneB,
            zoneB: i.isEven ? _zoneB : _zoneA,
            seenAt: t.add(Duration(seconds: i)),
          ),
        ),
      );
      // Contrato que en producción imponen la writeTxn + índice único:
      // el Set (add idempotente) deja UN solo registro lógico.
      final logical = <String>{};
      for (final k in keys) {
        logical.add(k);
      }
      expect(logical, hasLength(1));
    });
  });

  group('6. reinicio mantiene la deduplicación', () {
    test('re-derivar desde campos persistidos → misma clave (stateless)',
        () async {
      // Simula la fila persistida: (ownZone, otherZone, seenAt).
      const ownZone = _zoneA;
      const otherZone = _zoneB;
      final seenAt = DateTime.utc(2026, 10, 8, 18, 12, 33);
      final beforeRestart = await EncounterKey.canonicalKey(
        zoneA: ownZone,
        zoneB: otherZone,
        seenAt: seenAt,
      );
      // "Reinicio": proceso nuevo, mismos valores leídos del disco.
      final afterRestart = await EncounterKey.canonicalKey(
        zoneA: ownZone,
        zoneB: otherZone,
        seenAt: seenAt,
      );
      expect(afterRestart, beforeRestart);
    });
  });

  group('7. creación offline recuperable', () {
    test('la derivación no requiere red ni reloj remoto', () async {
      // Sin mocks de conectividad: la función no acepta ningún canal de I/O
      // en su firma (solo handles + timestamp local) — la llamada directa lo
      // demuestra: no lanza sin backend.
      final key = await EncounterKey.tryCanonicalKey(
        myZone: _zoneA,
        peerZone: _zoneB,
        seenAt: DateTime.now(),
      );
      expect(key, isNotNull);
      expect(key, startsWith('ZEN-1:'));
    });
  });

  group('8. pares no relacionados no colisionan', () {
    test('A↔C ≠ A↔B y B↔C ≠ A↔B', () async {
      final t = DateTime.utc(2026, 10, 8, 18, 12);
      final ab = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: t,
      );
      final ac = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneC,
        seenAt: t,
      );
      final bc = await EncounterKey.canonicalKey(
        zoneA: _zoneB,
        zoneB: _zoneC,
        seenAt: t,
      );
      expect(ac, isNot(ab));
      expect(bc, isNot(ab));
      expect(bc, isNot(ac));
    });
  });

  group('9. separación por bucket de tiempo', () {
    test('distinto bucket horario → encuentro lógico distinto', () async {
      final h18 = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: DateTime.utc(2026, 10, 8, 18, 59, 59),
      );
      final h19 = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: DateTime.utc(2026, 10, 8, 19, 0, 0),
      );
      expect(h19, isNot(h18));
    });

    test('distinto día, misma hora → distinto', () async {
      final d1 = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: DateTime.utc(2026, 10, 8, 18, 12),
      );
      final d2 = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: DateTime.utc(2026, 10, 9, 18, 12),
      );
      expect(d2, isNot(d1));
    });

    test('bucket usa UTC, no hora local (determinista entre dispositivos)',
        () async {
      // 20:30 +02:00 == 18:30 UTC → mismo bucket que 18:15 UTC.
      final fromOffset = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: DateTime.parse('2026-10-08T20:30:00+02:00'),
      );
      final fromUtc = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: DateTime.utc(2026, 10, 8, 18, 15),
      );
      expect(fromOffset, fromUtc);
    });
  });

  group('10. sin material privado en la clave', () {
    test('formato fijo ZEN-1:<64 hex>: estructuralmente incapaz de portar '
        'secretos y determinista (sin aleatoriedad)', () async {
      final t = DateTime.utc(2026, 10, 8, 18, 12);
      final k1 = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: t,
      );
      final k2 = await EncounterKey.canonicalKey(
        zoneA: _zoneA,
        zoneB: _zoneB,
        seenAt: t,
      );
      expect(k1, k2); // Sin nonce/secreto interno: mismos inputs ⇒ misma clave.
      expect(k1, isNot(contains(_zoneA)));
      expect(k1, isNot(contains(_zoneB)));
      expect(k1.length, 'ZEN-1:'.length + 64);
    });
  });

  group('11. identidad malformada falla cerrado', () {
    test('handles inválidos lanzan InvalidEncounterIdentityError', () async {
      final t = DateTime.utc(2026, 10, 8, 18, 12);
      for (final bad in ['', 'BAD', 'ZONE-SHORT', 'ZONE-abc\$1234', 'ZONE-']) {
        await expectLater(
          EncounterKey.canonicalKey(zoneA: _zoneA, zoneB: bad, seenAt: t),
          throwsA(isA<InvalidEncounterIdentityError>()),
          reason: 'peer=$bad',
        );
        await expectLater(
          EncounterKey.canonicalKey(zoneA: bad, zoneB: _zoneB, seenAt: t),
          throwsA(isA<InvalidEncounterIdentityError>()),
          reason: 'mine=$bad',
        );
      }
    });

    test('auto-encuentro (A==A) falla cerrado', () async {
      await expectLater(
        EncounterKey.canonicalKey(
          zoneA: _zoneA,
          zoneB: _zoneA.toLowerCase(),
          seenAt: DateTime.utc(2026, 10, 8, 18, 12),
        ),
        throwsA(isA<InvalidEncounterIdentityError>()),
      );
    });

    test('tryCanonicalKey mapea el fallo a null (omitir, no crashear)',
        () async {
      expect(
        await EncounterKey.tryCanonicalKey(
          myZone: '',
          peerZone: _zoneB,
          seenAt: DateTime.utc(2026, 10, 8, 18, 12),
        ),
        isNull,
      );
      expect(
        await EncounterKey.tryCanonicalKey(
          myZone: _zoneA,
          peerZone: _zoneA,
          seenAt: DateTime.utc(2026, 10, 8, 18, 12),
        ),
        isNull,
      );
    });
  });

  group('12. datos existentes siguen legibles (vía legacy)', () {
    test('isDuplicate decide por bucket sobre seenAt persistidos', () {
      // Fila histórica de las 18:05 (mismo bucket que el candidato 18:50).
      expect(
        EncounterKey.isDuplicate(
          existingSeenAt: [DateTime.utc(2026, 10, 8, 18, 5)],
          candidate: DateTime.utc(2026, 10, 8, 18, 50),
        ),
        isTrue,
      );
      // Fila de otro bucket → el candidato SÍ se registra.
      expect(
        EncounterKey.isDuplicate(
          existingSeenAt: [DateTime.utc(2026, 10, 8, 17, 59)],
          candidate: DateTime.utc(2026, 10, 8, 18, 1),
        ),
        isFalse,
      );
      // Sin historial → se registra.
      expect(
        EncounterKey.isDuplicate(
          existingSeenAt: const [],
          candidate: DateTime.utc(2026, 10, 8, 18, 1),
        ),
        isFalse,
      );
    });

    test('normalización tolera minúsculas y espacios (handles reales)',
        () async {
      final key = await EncounterKey.canonicalKey(
        zoneA: '  zone-a1b2c3d4 ',
        zoneB: _zoneB,
        seenAt: DateTime.utc(2026, 10, 8, 18, 12),
      );
      expect(
        key,
        await EncounterKey.canonicalKey(
          zoneA: _zoneA,
          zoneB: _zoneB,
          seenAt: DateTime.utc(2026, 10, 8, 18, 12),
        ),
      );
    });
  });
}
