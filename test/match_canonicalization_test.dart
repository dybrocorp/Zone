/// PHASE 2.2.4 — Match canonicalization + retry safety: tests UNIT.
///
/// Matriz sobre `lib/services/match_pair.dart` (lógica pura, sin Supabase):
/// 1. A→B crea un match. 2. A→B repetido reutiliza. 3. B→A reutiliza.
/// 4. A→B y B→A no duplican. 5. getMatchStatus(A,B)==(B,A) (lookup
/// bidireccional + pick determinista). 6. pending existente se reutiliza.
/// 7. accepted existente se reutiliza (nunca se degrada). 8. el conflicto de
/// backend retorna el existente. 9. el fallo no produce estado pending.
/// 10. matchId nunca nulo tras éxito. 11./12. accept/reject solo
/// participante (receiver). 13. un tercero no muta. 14. matches direccionales
/// históricos se manejan. 15. par canónico determinista. 16. sin secretos.
/// 17. reintento tras fallo transitorio es seguro.
///
/// El "backend" es un almacén en memoria con la MISMA regla de unicidad que
/// la migración `z211_match_canonical.sql` (una fila por par canónico), de
/// modo que los flujos 1–8/17 ejercitan la semántica real de decisión +
/// recuperación sin red.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/services/match_pair.dart';

const String _a = '11111111-1111-4111-8111-111111111111';
const String _b = '22222222-2222-4222-8222-222222222222';
const String _c = '33333333-3333-4333-8333-333333333333';

/// Almacén en memoria con unicidad canónica (espejo de `uq_matches_canonical_pair`).
class FakeMatchStore {
  final Map<String, Map<String, dynamic>> _rows = {};
  int _seq = 0;
  bool failNextInsert = false;

  String _slot(String x, String y) =>
      '${MatchPair.canonicalLow(x, y)}|${MatchPair.canonicalHigh(x, y)}';

  /// Imita `getMatchStatus`: bidireccional + earliest determinista.
  Map<String, dynamic>? lookup(String x, String y) => _rows[_slot(x, y)];

  /// Imita el INSERT con unicidad canónica (conflicto si el slot existe).
  Map<String, dynamic> insert(String requester, String receiver) {
    if (failNextInsert) {
      failNextInsert = false;
      throw StateError('transient failure');
    }
    final slot = _slot(requester, receiver);
    if (_rows.containsKey(slot)) {
      throw StateError('unique violation uq_matches_canonical_pair');
    }
    _seq++;
    final row = {
      'id': 'match-$_seq',
      'requester_id': requester,
      'receiver_id': receiver,
      'status': 'pending',
    };
    _rows[slot] = row;
    return row;
  }

  void delete(String id) {
    _rows.removeWhere((_, r) => r['id'] == id);
  }

  int get rowCount => _rows.length;
}

/// Orquestación `requestMatch` sobre el almacén falso (misma secuencia que
/// `SupabaseService.requestMatch`: leer → decidir → escribir → recuperar).
String? fakeRequest(FakeMatchStore store, String requester, String receiver) {
  if (requester.trim().isEmpty ||
      receiver.trim().isEmpty ||
      requester.trim() == receiver.trim()) {
    return null;
  }
  final decision = MatchPair.decide(
    existing: store.lookup(requester, receiver),
    requesterId: requester,
    receiverId: receiver,
  );
  switch (decision.action) {
    case MatchRequestAction.reuse:
      return decision.matchId;
    case MatchRequestAction.recreate:
      store.delete(decision.matchId!);
      break;
    case MatchRequestAction.create:
      break;
  }
  try {
    return store.insert(requester, receiver)['id'] as String;
  } catch (_) {
    final recovered = store.lookup(requester, receiver);
    final id = recovered?['id'] as String?;
    return MatchPair.isValidMatchId(id) ? id : null;
  }
}

void main() {
  group('15./16. par canónico', () {
    test('determinista y simétrico', () {
      expect(MatchPair.canonicalLow(_a, _b), MatchPair.canonicalLow(_b, _a));
      expect(
        MatchPair.canonicalHigh(_a, _b),
        MatchPair.canonicalHigh(_b, _a),
      );
      expect(MatchPair.canonicalLow(_a, _b), _a);
      expect(MatchPair.canonicalHigh(_a, _b), _b);
    });

    test('no contiene secretos: la salida es subconjunto de las entradas', () {
      final lo = MatchPair.canonicalLow(_a, _b);
      final hi = MatchPair.canonicalHigh(_a, _b);
      expect({lo, hi}, {_a, _b});
    });

    test('vacío/auto falla cerrado', () {
      expect(
        () => MatchPair.canonicalLow('', _b),
        throwsA(isA<InvalidMatchIdentityError>()),
      );
      expect(
        () => MatchPair.canonicalHigh(_a, _a),
        throwsA(isA<InvalidMatchIdentityError>()),
      );
      expect(
        () => MatchPair.decide(
          existing: null,
          requesterId: _a,
          receiverId: _a,
        ),
        throwsA(isA<InvalidMatchIdentityError>()),
      );
    });
  });

  group('decisión requestMatch (CASE 1–6)', () {
    test('CASE 1: sin existente → create', () {
      final d = MatchPair.decide(
        existing: null,
        requesterId: _a,
        receiverId: _b,
      );
      expect(d.action, MatchRequestAction.create);
      expect(d.matchId, isNull);
    });

    test('CASE 2/4: pending existente → reuse (misma y distinta dirección)',
        () {
      final row = {'id': 'm1', 'status': 'pending'};
      final sameDir = MatchPair.decide(
        existing: row,
        requesterId: _a,
        receiverId: _b,
      );
      final reverseDir = MatchPair.decide(
        existing: row,
        requesterId: _b,
        receiverId: _a,
      );
      expect(sameDir.action, MatchRequestAction.reuse);
      expect(sameDir.matchId, 'm1');
      expect(reverseDir.action, MatchRequestAction.reuse);
      expect(reverseDir.matchId, 'm1');
    });

    test('CASE 5: accepted existente → reuse (nunca degrada)', () {
      final d = MatchPair.decide(
        existing: {'id': 'm1', 'status': 'accepted'},
        requesterId: _b,
        receiverId: _a,
      );
      expect(d.action, MatchRequestAction.reuse);
      expect(d.matchId, 'm1');
    });

    test('CASE 6: rejected existente → recreate con id', () {
      final d = MatchPair.decide(
        existing: {'id': 'm9', 'status': 'rejected'},
        requesterId: _a,
        receiverId: _b,
      );
      expect(d.action, MatchRequestAction.recreate);
      expect(d.matchId, 'm9');
    });

    test('estado desconocido → reuse (nunca duplicar)', () {
      final d = MatchPair.decide(
        existing: {'id': 'm1', 'status': 'weird'},
        requesterId: _a,
        receiverId: _b,
      );
      expect(d.action, MatchRequestAction.reuse);
    });

    test('fila corrupta sin id → create', () {
      final d = MatchPair.decide(
        existing: {'status': 'pending'},
        requesterId: _a,
        receiverId: _b,
      );
      expect(d.action, MatchRequestAction.create);
    });
  });

  group('1.–4./8./17. flujos end-to-end sobre almacén canónico', () {
    test('1: A→B crea exactamente un match con id válido', () {
      final store = FakeMatchStore();
      final id = fakeRequest(store, _a, _b);
      expect(MatchPair.isValidMatchId(id), isTrue);
      expect(store.rowCount, 1);
    });

    test('2: A→B repetido retorna el mismo match, sin duplicar', () {
      final store = FakeMatchStore();
      final first = fakeRequest(store, _a, _b);
      final second = fakeRequest(store, _a, _b);
      expect(second, first);
      expect(store.rowCount, 1);
    });

    test('3./4: B→A tras A→B retorna el MISMO match (carrera incluida)', () {
      final store = FakeMatchStore();
      final fromA = fakeRequest(store, _a, _b);
      final fromB = fakeRequest(store, _b, _a);
      expect(fromB, fromA);
      expect(store.rowCount, 1);
    });

    test('8: conflicto de inserción concurrente recupera el existente', () {
      final store = FakeMatchStore();
      // A inserta; el intento de B colisiona en el índice canónico.
      final winner = store.insert(_a, _b)['id'];
      String? loserResult;
      try {
        loserResult = store.insert(_b, _a)['id'] as String;
      } catch (_) {
        final recovered = store.lookup(_b, _a);
        final id = recovered?['id'] as String?;
        loserResult = MatchPair.isValidMatchId(id) ? id : null;
      }
      expect(loserResult, winner);
      expect(store.rowCount, 1);
    });

    test('17: reintento tras fallo transitorio es seguro', () {
      final store = FakeMatchStore();
      store.failNextInsert = true;
      // Primer intento: falla el insert pero la recuperación no halla nada.
      expect(fakeRequest(store, _a, _b), isNull);
      expect(store.rowCount, 0);
      // Reintento: crea exactamente uno.
      final id = fakeRequest(store, _a, _b);
      expect(MatchPair.isValidMatchId(id), isTrue);
      expect(store.rowCount, 1);
      // Y otro reintento más: reutiliza.
      expect(fakeRequest(store, _a, _b), id);
      expect(store.rowCount, 1);
    });

    test('7: accepted existente se reutiliza desde ambas direcciones', () {
      final store = FakeMatchStore();
      final id = fakeRequest(store, _a, _b)!;
      store.lookup(_a, _b)!['status'] = 'accepted';
      expect(fakeRequest(store, _b, _a), id);
      expect(fakeRequest(store, _a, _b), id);
      expect(store.rowCount, 1);
    });

    test('CASE 6 e2e: rejected → re-request crea uno nuevo válido', () {
      final store = FakeMatchStore();
      fakeRequest(store, _a, _b);
      store.lookup(_a, _b)!['status'] = 'rejected';
      final id = fakeRequest(store, _a, _b);
      expect(MatchPair.isValidMatchId(id), isTrue);
      expect(store.lookup(_a, _b)!['status'], 'pending');
      expect(store.rowCount, 1);
    });
  });

  group('5. lookup bidireccional', () {
    test('lookup(A,B) == lookup(B,A)', () {
      final store = FakeMatchStore();
      fakeRequest(store, _a, _b);
      final ab = store.lookup(_a, _b);
      final ba = store.lookup(_b, _a);
      expect(ab, isNotNull);
      expect(ba?['id'], ab?['id']);
    });
  });

  group('9./10. seguridad de estado UI', () {
    test('isValidMatchId: solo ids reales habilitan pending', () {
      expect(MatchPair.isValidMatchId('match-1'), isTrue);
      expect(MatchPair.isValidMatchId(null), isFalse);
      expect(MatchPair.isValidMatchId(''), isFalse);
      expect(MatchPair.isValidMatchId('   '), isFalse);
    });

    test('fallo total → null (la UI debe quedarse en idle con error)', () {
      final store = FakeMatchStore()..failNextInsert = true;
      expect(fakeRequest(store, _a, _b), isNull);
      expect(store.rowCount, 0);
    });
  });

  group('11.–13. autorización por participante', () {
    test('A pide a B → B puede aceptar, A no, C tampoco', () {
      final row = {'requester_id': _a, 'receiver_id': _b};
      expect(MatchPair.canAccept(row, _b), isTrue);
      expect(MatchPair.canAccept(row, _a), isFalse);
      expect(MatchPair.canAccept(row, _c), isFalse);
      expect(MatchPair.canReject(row, _b), isTrue);
      expect(MatchPair.canReject(row, _a), isFalse);
      expect(MatchPair.canReject(row, _c), isFalse);
    });

    test('isParticipant cubre a ambos, excluye a terceros', () {
      final row = {'requester_id': _a, 'receiver_id': _b};
      expect(MatchPair.isParticipant(row, _a), isTrue);
      expect(MatchPair.isParticipant(row, _b), isTrue);
      expect(MatchPair.isParticipant(row, _c), isFalse);
    });
  });

  group('14. matches direccionales históricos', () {
    test('cada fila histórica resuelve a reuse (el orden earliest lo da el '
        'servidor con order+limit)', () {
      // Dos filas históricas A→B y B→A: cualquiera que devuelva el servidor
      // como earliest se reutiliza — nunca se crea una tercera.
      for (final row in [
        {'id': 'old-1', 'status': 'pending'},
        {'id': 'old-2', 'status': 'pending'},
      ]) {
        final d = MatchPair.decide(
          existing: row,
          requesterId: _b,
          receiverId: _a,
        );
        expect(d.action, MatchRequestAction.reuse);
        expect(MatchPair.isValidMatchId(d.matchId), isTrue);
      }
    });
  });
}
