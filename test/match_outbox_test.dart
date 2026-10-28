/// PHASE 2.2.5 — Match offline/outbox + convergence: tests UNIT.
///
/// Cobertura de la matriz (§14) sin Isar nativo ni red: almacén en memoria
/// (misma semántica `putByOperationId` que Isar) + backend falso con la MISMA
/// regla de unicidad canónica que `z211_match_canonical.sql` + reloj
/// controlable. El procesador bajo prueba es el de producción
/// (`MatchOutboxProcessor.processAll`).
///
/// 1. determinismo de identidad · 2. deduplicación de encolado · 3. persistencia
/// offline · 4. persistencia ante reinicio · 5. reintento conserva identidad ·
/// 6. fallo transitorio reintenta · 7. fallo de autorización terminal ·
/// 8. operación corrupta fail-closed · 9. replay tras éxito+respuesta perdida ·
/// 10. reutilización canónica · 11. convergencia reversa · 12. accepted nunca
/// se degrada · 13. accept offline converge · 14. reject offline converge ·
/// 15. procesamiento concurrente seguro · 16. sin secretos · 17. matchId
/// válido tras confirmación · 18. sin matchId falso offline · 19. completitud
/// tras sync · 20. el reintento no duplica.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zone/models/isar_models.dart';
import 'package:zone/services/match_outbox.dart';
import 'package:zone/services/match_outbox_processor.dart';
import 'package:zone/services/match_pair.dart';

const String _a = '11111111-1111-4111-8111-111111111111';
const String _b = '22222222-2222-4222-8222-222222222222';
const String _c = '33333333-3333-4333-8333-333333333333';

String _slot(String x, String y) =>
    '${MatchPair.canonicalLow(x, y)}|${MatchPair.canonicalHigh(x, y)}';

/// Almacén en memoria con semántica `putByOperationId` (reemplazo por clave).
class FakeMatchStore implements MatchOperationStore {
  final Map<String, LocalMatchOperation> rows = {};

  LocalMatchOperation _clone(LocalMatchOperation op) => LocalMatchOperation()
    ..operationId = op.operationId
    ..operationType = op.operationType
    ..canonicalLow = op.canonicalLow
    ..canonicalHigh = op.canonicalHigh
    ..actorUserId = op.actorUserId
    ..targetUserId = op.targetUserId
    ..serverMatchId = op.serverMatchId
    ..state = op.state
    ..retryCount = op.retryCount
    ..nextAttemptAt = op.nextAttemptAt
    ..createdAt = op.createdAt
    ..lastErrorCode = op.lastErrorCode;

  @override
  Future<void> enqueue(LocalMatchOperation op) async {
    rows[op.operationId] = _clone(op);
  }

  @override
  Future<List<LocalMatchOperation>> pendingDue(
    DateTime now, {
    bool ignoreBackoff = false,
  }) async {
    final list = rows.values
        .where((o) => o.state == MatchOpState.pending)
        .where(
          (o) =>
              ignoreBackoff ||
              o.nextAttemptAt == null ||
              !o.nextAttemptAt!.isAfter(now),
        )
        .toList()
      ..sort((x, y) => x.createdAt.compareTo(y.createdAt));
    return list;
  }

  @override
  Future<bool> claim(String operationId) async {
    final op = rows[operationId];
    if (op == null || op.state != MatchOpState.pending) return false;
    op.state = MatchOpState.inflight;
    return true;
  }

  @override
  Future<void> release(String operationId) async {
    final op = rows[operationId];
    if (op != null && op.state == MatchOpState.inflight) {
      op.state = MatchOpState.pending;
    }
  }

  @override
  Future<void> recordRetry(
    String operationId,
    String errorCode,
    DateTime now,
  ) async {
    final op = rows[operationId];
    if (op == null) return;
    final next = op.retryCount + 1;
    if (next >= MatchOutboxPolicy.maxRetries) {
      op.state = MatchOpState.failed;
      op.lastErrorCode = errorCode;
    } else {
      op.retryCount = next;
      op.state = MatchOpState.pending;
      op.nextAttemptAt = MatchOutboxPolicy.nextAttemptAt(
        retryCount: next,
        now: now,
      );
      op.lastErrorCode = errorCode;
    }
  }

  @override
  Future<void> markFailed(String operationId, String errorCode) async {
    final op = rows[operationId];
    if (op == null) return;
    op.state = MatchOpState.failed;
    op.lastErrorCode = errorCode;
  }

  @override
  Future<void> remove(String operationId) async {
    rows.remove(operationId);
  }

  @override
  Future<bool> hasPendingForPair(String low, String high) async =>
      rows.values.any(
        (o) =>
            o.canonicalLow == low &&
            o.canonicalHigh == high &&
            o.state == MatchOpState.pending,
      );

  @override
  Future<LocalMatchOperation?> failedForPair(String low, String high) async {
    for (final o in rows.values) {
      if (o.canonicalLow == low &&
          o.canonicalHigh == high &&
          o.state == MatchOpState.failed) {
        return o;
      }
    }
    return null;
  }

  @override
  Future<List<LocalMatchOperation>> failedAll() async =>
      rows.values.where((o) => o.state == MatchOpState.failed).toList();

  @override
  Future<int> pendingCount() async => rows.values
      .where((o) => o.state == MatchOpState.pending)
      .length;

  @override
  Future<int> failedCount() async => rows.values
      .where((o) => o.state == MatchOpState.failed)
      .length;

  @override
  Future<void> resetForRetry(String operationId) async {
    final op = rows[operationId];
    if (op != null && op.state == MatchOpState.failed) {
      op.state = MatchOpState.pending;
      op.retryCount = 0;
      op.nextAttemptAt = null;
      op.lastErrorCode = null;
    }
  }

  @override
  Future<void> resetAllFailed() async {
    for (final op in rows.values) {
      if (op.state == MatchOpState.failed) {
        await resetForRetry(op.operationId);
      }
    }
  }

  @override
  Future<void> delete(String operationId) async {
    rows.remove(operationId);
  }
}

/// Backend falso: unicidad canónica + inyección de fallos + registro.
class FakeMatchBackend implements MatchOutboxBackend {
  final Map<String, Map<String, dynamic>> rows = {};
  final List<String> calls = [];
  int _seq = 0;

  /// Falla el próximo INSERT con [error] DESPUÉS de insertar (pérdida de
  /// respuesta) o ANTES (fallo limpio), según [afterInsert].
  Object? failNextInsert;
  bool failAfterInsert = false;
  Object? failNextUpdate;

  String _slotOf(String requester, String receiver) =>
      _slot(requester, receiver);

  Map<String, dynamic>? lookup(String x, String y) => rows[_slotOf(x, y)];

  @override
  Future<String?> requestMatch(String requesterId, String receiverId) async {
    calls.add('request:$requesterId->$receiverId');
    final slot = _slotOf(requesterId, receiverId);
    final existing = rows[slot];
    if (existing != null) {
      if (existing['status'] == 'rejected') {
        rows.remove(slot);
      } else {
        return existing['id'] as String;
      }
    }
    _seq++;
    final row = {
      'id': 'match-$_seq',
      'requester_id': requesterId,
      'receiver_id': receiverId,
      'status': 'pending',
    };
    if (failNextInsert != null && !failAfterInsert) {
      final e = failNextInsert;
      failNextInsert = null;
      throw e!;
    }
    rows[slot] = row;
    if (failNextInsert != null && failAfterInsert) {
      final e = failNextInsert;
      failNextInsert = null;
      throw e!;
    }
    return row['id'] as String;
  }

  @override
  Future<Map<String, dynamic>?> getMatchById(String matchId) async {
    calls.add('get:$matchId');
    for (final r in rows.values) {
      if (r['id'] == matchId) return Map.of(r);
    }
    return null;
  }

  @override
  Future<bool> acceptMatch(String matchId) async {
    calls.add('accept:$matchId');
    if (failNextUpdate != null) {
      final e = failNextUpdate;
      failNextUpdate = null;
      throw e!;
    }
    for (final r in rows.values) {
      if (r['id'] == matchId) {
        r['status'] = 'accepted';
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> rejectMatch(String matchId) async {
    calls.add('reject:$matchId');
    if (failNextUpdate != null) {
      final e = failNextUpdate;
      failNextUpdate = null;
      throw e!;
    }
    for (final r in rows.values) {
      if (r['id'] == matchId) {
        r['status'] = 'rejected';
        return true;
      }
    }
    return false;
  }

  int get rowCount => rows.length;
}

void main() {
  group('identidad de operación (1)', () {
    test('determinista y simétrica en el par, sensible a la dirección', () {
      final ab = MatchOutboxPolicy.requestId(requester: _a, receiver: _b);
      final ab2 = MatchOutboxPolicy.requestId(requester: _a, receiver: _b);
      final ba = MatchOutboxPolicy.requestId(requester: _b, receiver: _a);
      expect(ab, ab2);
      expect(ab, startsWith('mr:'));
      // La dirección importa (RLS): A→B y B→A son operaciones distintas que
      // convergen en el MISMO par canónico del servidor.
      expect(ba, isNot(ab));
      expect(ab, contains(MatchPair.canonicalLow(_a, _b)));
      expect(ab, contains(MatchPair.canonicalHigh(_a, _b)));
      expect(
        MatchOutboxPolicy.acceptId(serverMatchId: 'm1', actor: _b),
        'ma:m1:$_b',
      );
      expect(
        MatchOutboxPolicy.rejectId(serverMatchId: 'm1', actor: _b),
        'mj:m1:$_b',
      );
    });

    test('backoff determinista con tope', () {
      expect(MatchOutboxPolicy.backoffForRetry(0), const Duration(minutes: 1));
      expect(MatchOutboxPolicy.backoffForRetry(1), const Duration(minutes: 2));
      expect(MatchOutboxPolicy.backoffForRetry(5), const Duration(minutes: 32));
      expect(MatchOutboxPolicy.backoffForRetry(6), const Duration(minutes: 60));
      expect(MatchOutboxPolicy.backoffForRetry(99), const Duration(minutes: 60));
    });
  });

  group('clasificación de errores (6/7)', () {
    test('red/timeout → retryable; auth/malformado → terminal', () {
      expect(
        MatchOutboxPolicy.classifyException(
          const SocketException('unreachable'),
        ),
        MatchOpError.network,
      );
      expect(
        MatchOutboxPolicy.classifyException(TimeoutException('t', const Duration(seconds: 1))),
        MatchOpError.timeout,
      );
      expect(
        MatchOutboxPolicy.classifyException(
          const PostgrestException(message: 'x', code: '42501'),
        ),
        MatchOpError.auth,
      );
      expect(
        MatchOutboxPolicy.classifyException(
          const PostgrestException(message: 'new row violates row-level security', code: '42501'),
        ),
        MatchOpError.auth,
      );
      expect(
        MatchOutboxPolicy.classifyException(
          const PostgrestException(message: 'x', code: '500'),
        ),
        MatchOpError.server,
      );
      expect(
        MatchOutboxPolicy.classifyException(const FormatException('bad')),
        MatchOpError.malformed,
      );
      expect(MatchOpError.isTerminal(MatchOpError.auth), isTrue);
      expect(MatchOpError.isTerminal(MatchOpError.malformed), isTrue);
      expect(MatchOpError.isTerminal(MatchOpError.missing), isTrue);
      expect(MatchOpError.isTerminal(MatchOpError.state), isTrue);
      expect(MatchOpError.isTerminal(MatchOpError.network), isFalse);
      expect(MatchOpError.isTerminal(MatchOpError.server), isFalse);
      expect(MatchOpError.isTerminal(MatchOpError.unknown), isFalse);
    });
  });

  group('validación fail-closed (8)', () {
    test('operaciones corruptas se detectan sin backend', () {
      String? v({
        required String t,
        String low = 'x',
        String high = 'y',
        String actor = _a,
        String? target,
        String? sid,
      }) =>
          MatchOutboxPolicy.validateOp(
            operationType: t,
            canonicalLow: low,
            canonicalHigh: high,
            actorUserId: actor,
            targetUserId: target,
            serverMatchId: sid,
          );
      expect(v(t: 'bogus', target: _b), MatchOpError.malformed);
      expect(v(t: 'request', actor: '', target: _b), MatchOpError.malformed);
      expect(v(t: 'request', target: null), MatchOpError.malformed);
      expect(
        v(t: 'request', low: 'WRONG', high: 'PAIR', target: _b),
        MatchOpError.malformed,
      );
      expect(v(t: 'accept', sid: null), MatchOpError.malformed);
      expect(v(t: 'reject', sid: '  '), MatchOpError.malformed);
      // Válidas:
      expect(
        v(
          t: 'request',
          low: MatchPair.canonicalLow(_a, _b),
          high: MatchPair.canonicalHigh(_a, _b),
          target: _b,
        ),
        isNull,
      );
      expect(
        v(t: 'accept', low: 'x', high: 'y', sid: 'm1'),
        isNull,
      );
    });
  });

  group('flujos del procesador', () {
    late DateTime now;
    late FakeMatchStore store;
    late FakeMatchBackend backend;

    setUp(() {
      now = DateTime.utc(2026, 10, 8, 18, 0);
      store = FakeMatchStore();
      backend = FakeMatchBackend();
    });

    Future<MatchOutboxSummary> run({bool online = true}) =>
        MatchOutboxProcessor.processAll(
          store: store,
          backend: backend,
          isOnline: () async => online,
          clock: () => now,
        );

    LocalMatchOperation reqOp() => buildRequestOp(
          requester: _a,
          receiver: _b,
          now: now,
        );

    test('2: encolar dos veces → una sola fila durable', () async {
      await store.enqueue(reqOp());
      await store.enqueue(reqOp());
      expect(store.rows, hasLength(1));
    });

    test('3/18: offline → persiste sin matchId falso y sin llamadas', () async {
      await store.enqueue(reqOp());
      final s = await run(online: false);
      expect(s.skippedOffline, 1);
      expect(backend.calls, isEmpty);
      final ops = await store.pendingDue(now);
      expect(ops, hasLength(1));
      expect(ops.first.serverMatchId, isNull);
      expect(MatchPair.isValidMatchId(ops.first.serverMatchId), isFalse);
    });

    test('4: reinicio → la operación sobrevive y converge', () async {
      await store.enqueue(reqOp());
      // "Reinicio": procesador nuevo sobre el MISMO almacén durable.
      final s = await run();
      expect(s.completed, 1);
      expect(backend.rowCount, 1);
      expect(await store.pendingCount(), 0);
    });

    test('5/6: transitorio conserva identidad y reintenta con backoff',
        () async {
      await store.enqueue(reqOp());
      backend.failNextInsert = const SocketException('down');
      var s = await run();
      expect(s.retried, 1);
      final op = store.rows.values.single;
      expect(op.retryCount, 1);
      expect(op.nextAttemptAt, isNotNull);
      final opId = op.operationId;
      // Aún en backoff: no se reprocesa.
      s = await run();
      expect(s.processed, 0);
      // Vencido el backoff: converge con LA MISMA identidad.
      now = op.nextAttemptAt!.add(const Duration(seconds: 1));
      s = await run();
      expect(s.completed, 1);
      expect(backend.rowCount, 1);
      expect(store.rows, isEmpty);
      expect(opId, startsWith('mr:'));
    });

    test('9: éxito en servidor + respuesta perdida → sin duplicado', () async {
      await store.enqueue(reqOp());
      backend.failNextInsert = const SocketException('lost');
      backend.failAfterInsert = true;
      var s = await run();
      expect(s.retried, 1);
      expect(backend.rowCount, 1);
      // Reintento: el backend canónico reutiliza, no duplica.
      final op = store.rows.values.single;
      now = op.nextAttemptAt!.add(const Duration(seconds: 1));
      s = await run();
      expect(s.completed, 1);
      expect(backend.rowCount, 1);
    });

    test('10/11: match preexistente y reverso convergen sin insertar',
        () async {
      // Otro camino creó B→A en el servidor.
      await backend.requestMatch(_b, _a);
      backend.calls.clear();
      await store.enqueue(reqOp());
      final s = await run();
      expect(s.completed, 1);
      expect(backend.rowCount, 1);
      expect(
        backend.calls.where((c) => c.startsWith('request:')),
        hasLength(1),
      );
    });

    test('20: reintentos repetidos nunca duplican el match', () async {
      await store.enqueue(reqOp());
      for (var i = 0; i < 3; i++) {
        backend.failNextInsert = const SocketException('flaky');
        await run();
        final op = store.rows.values.single;
        now = (op.nextAttemptAt ?? now).add(const Duration(seconds: 1));
      }
      final s = await run();
      expect(s.completed, 1);
      expect(backend.rowCount, 1);
    });

    test('agotados los reintentos → failed terminal con código', () async {
      await store.enqueue(reqOp());
      for (var i = 0; i < MatchOutboxPolicy.maxRetries; i++) {
        backend.failNextInsert = const SocketException('down');
        await run();
        final op = store.rows.values.singleOrNull;
        if (op != null && op.state == MatchOpState.pending) {
          now = (op.nextAttemptAt ?? now).add(const Duration(seconds: 1));
        }
      }
      final failed = await store.failedAll();
      expect(failed, hasLength(1));
      expect(failed.single.lastErrorCode, MatchOpError.network);
      // Terminal: ya no se reprocesa.
      final s = await run();
      expect(s.processed, 0);
      // Reintento manual la reabre.
      await store.resetForRetry(failed.single.operationId);
      now = now.add(const Duration(minutes: 1));
      final s2 = await run();
      expect(s2.completed, 1);
    });

    test('7: accept no autorizado → terminal sin reintentos', () async {
      final row = await backend.requestMatch(_a, _b);
      final op = buildAcceptOp(
        serverMatchId: row!,
        actor: _c, // tercero, no es receiver
        low: MatchPair.canonicalLow(_a, _b),
        high: MatchPair.canonicalHigh(_a, _b),
        now: now,
      );
      await store.enqueue(op);
      final s = await run();
      expect(s.failedTerminal, 1);
      final failed = await store.failedAll();
      expect(failed.single.lastErrorCode, MatchOpError.auth);
      expect(failed.single.retryCount, 0);
      expect(backend.lookup(_a, _b)!['status'], 'pending');
    });

    test('12/13: accept offline del receiver converge; repetido no reescribe',
        () async {
      final id = (await backend.requestMatch(_a, _b))!;
      backend.calls.clear();
      await store.enqueue(
        buildAcceptOp(
          serverMatchId: id,
          actor: _b,
          low: MatchPair.canonicalLow(_a, _b),
          high: MatchPair.canonicalHigh(_a, _b),
          now: now,
        ),
      );
      final s = await run();
      expect(s.completed, 1);
      expect(backend.lookup(_a, _b)!['status'], 'accepted');
      // Replay sobre accepted ya convergido: done sin reescribir.
      await store.enqueue(
        buildAcceptOp(
          serverMatchId: id,
          actor: _b,
          low: MatchPair.canonicalLow(_a, _b),
          high: MatchPair.canonicalHigh(_a, _b),
          now: now,
        ),
      );
      backend.calls.clear();
      final s2 = await run();
      expect(s2.completed, 1);
      expect(
        backend.calls.where((c) => c.startsWith('accept:')),
        isEmpty,
      );
    });

    test('14: reject offline converge; sobre accepted no degrada', () async {
      final id = (await backend.requestMatch(_a, _b))!;
      await store.enqueue(
        buildRejectOp(
          serverMatchId: id,
          actor: _b,
          low: MatchPair.canonicalLow(_a, _b),
          high: MatchPair.canonicalHigh(_a, _b),
          now: now,
        ),
      );
      expect((await run()).completed, 1);
      expect(backend.lookup(_a, _b)!['status'], 'rejected');

      // Fila accepted + reject encolado (intención vieja): terminal, el
      // servidor gana, sin escritura destructiva.
      final id2 = (await backend.requestMatch(_a, _c))!;
      backend.lookup(_a, _c)!['status'] = 'accepted';
      backend.calls.clear();
      await store.enqueue(
        buildRejectOp(
          serverMatchId: id2,
          actor: _c,
          low: MatchPair.canonicalLow(_a, _c),
          high: MatchPair.canonicalHigh(_a, _c),
          now: now,
        ),
      );
      final s = await run();
      expect(s.failedTerminal, 1);
      expect(backend.lookup(_a, _c)!['status'], 'accepted');
      expect(
        backend.calls.where((c) => c.startsWith('reject:')),
        isEmpty,
      );
    });

    test('accept sobre fila ausente → terminal missing', () async {
      await store.enqueue(
        buildAcceptOp(
          serverMatchId: 'match-gone',
          actor: _b,
          low: MatchPair.canonicalLow(_a, _b),
          high: MatchPair.canonicalHigh(_a, _b),
          now: now,
        ),
      );
      final s = await run();
      expect(s.failedTerminal, 1);
      expect((await store.failedAll()).single.lastErrorCode, MatchOpError.missing);
    });

    test('8 (store): operación corrupta → failed sin llamadas ni crash',
        () async {
      final bad = LocalMatchOperation()
        ..operationId = 'bogus'
        ..operationType = 'bogus'
        ..canonicalLow = ''
        ..canonicalHigh = ''
        ..actorUserId = ''
        ..state = MatchOpState.pending
        ..createdAt = now;
      await store.enqueue(bad);
      final s = await run();
      expect(s.failedTerminal, 1);
      expect(backend.calls, isEmpty);
      expect((await store.failedAll()).single.lastErrorCode, MatchOpError.malformed);
    });

    test('15: doble procesamiento concurrente ejecuta una sola vez', () async {
      await store.enqueue(reqOp());
      final results = await Future.wait([run(), run()]);
      final totalCompleted =
          results.fold<int>(0, (sum, s) => sum + s.completed);
      expect(totalCompleted, 1);
      expect(
        backend.calls.where((c) => c.startsWith('request:')),
        hasLength(1),
      );
      expect(backend.rowCount, 1);
    });

    test('17/19: confirmación ⇒ id válido + fila eliminada', () async {
      await store.enqueue(reqOp());
      final s = await run();
      expect(s.completed, 1);
      expect(store.rows, isEmpty);
      final row = backend.lookup(_a, _b)!;
      expect(MatchPair.isValidMatchId(row['id'] as String?), isTrue);
    });
  });

  group('sin secretos en el outbox (16)', () {
    test('las filas solo portan UUIDs, tipo/estado/contadores y códigos',
        () async {
      final ops = [
        buildRequestOp(requester: _a, receiver: _b, now: DateTime.utc(2026)),
        buildAcceptOp(
          serverMatchId: 'm1',
          actor: _b,
          low: MatchPair.canonicalLow(_a, _b),
          high: MatchPair.canonicalHigh(_a, _b),
          now: DateTime.utc(2026),
        ),
        buildRejectOp(
          serverMatchId: 'm1',
          actor: _b,
          low: MatchPair.canonicalLow(_a, _b),
          high: MatchPair.canonicalHigh(_a, _b),
          now: DateTime.utc(2026),
        ),
      ];
      const forbidden = [
        'private',
        'seed',
        'token',
        'secret',
        'password',
        'zidk1',
        'sk_',
        'bearer',
      ];
      for (final op in ops) {
        final dump = [
          op.operationId,
          op.operationType,
          op.canonicalLow,
          op.canonicalHigh,
          op.actorUserId,
          op.targetUserId ?? '',
          op.serverMatchId ?? '',
          op.state,
          op.lastErrorCode ?? '',
        ].join('|').toLowerCase();
        for (final f in forbidden) {
          expect(dump, isNot(contains(f)), reason: f);
        }
      }
    });
  });
}
