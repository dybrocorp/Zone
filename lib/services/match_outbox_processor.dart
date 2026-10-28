/// PHASE 2.2.5 — Procesador convergente del outbox de matches.
///
/// Arquitectura:
/// - [MatchOperationStore]: persistencia durable (Isar en producción,
///   memoria en tests). La `writeTxn` de Isar + el flag `inflight` serializan
///   el replay: la misma operación nunca se ejecuta dos veces en paralelo.
/// - [MatchOutboxBackend]: backend (Supabase en producción, falso en tests).
/// - [MatchOutboxProcessor.processAll]: orquesta validate → claim → ejecutar
///   → done/retry/terminal. Sin colas en memoria: todo sobrevive a reinicio.
///
/// Convergencia (la autoridad SIEMPRE es el servidor):
/// - request → `requestMatch` canónico (2.2.4): crea o reutiliza; el id
///   devuelto (nuevo o existente) completa la operación. Sin duplicados.
/// - accept → relee la fila: accepted ya ⇒ done; pending + soy receiver ⇒
///   aceptar; en otro caso terminal (sin reintentos infinitos, sin downgrade).
/// - reject → relee: rejected ya ⇒ done; pending + soy receiver ⇒ rechazar;
///   accepted ⇒ terminal sin escribir (gana la autoridad del servidor).
library;

import 'package:isar/isar.dart';

import '../models/isar_models.dart';
import 'isar_service.dart';
import 'match_outbox.dart';
import 'match_pair.dart';
import 'supabase_service.dart';

/// Persistencia durable de operaciones (implementada por Isar o memoria).
abstract class MatchOperationStore {
  /// Encola o reemplaza por `operationId` (deduplicación por construcción).
  Future<void> enqueue(LocalMatchOperation op);

  /// Operaciones `pending` cuya `nextAttemptAt` venció (o es nula).
  Future<List<LocalMatchOperation>> pendingDue(
    DateTime now, {
    bool ignoreBackoff = false,
  });

  /// Marca `pending` → `inflight`. False si ya no estaba pendiente
  /// (guarda contra replay concurrente).
  Future<bool> claim(String operationId);

  /// Devuelve `inflight` → `pending` sin quemar reintentos (p.ej. sin red).
  Future<void> release(String operationId);

  /// Registra un fallo retryable (retryCount++ y backoff) o terminal si se
  /// agotó [MatchOutboxPolicy.maxRetries].
  Future<void> recordRetry(String operationId, String errorCode, DateTime now);

  /// Marca terminal con código (conserva la fila para diagnóstico/reintento).
  Future<void> markFailed(String operationId, String errorCode);

  /// Completa la operación (borra la fila, como el outbox Z-007).
  Future<void> remove(String operationId);

  /// ¿Hay operación pendiente para el par canónico?
  Future<bool> hasPendingForPair(String low, String high);

  /// Fila `failed` del par (para surfacing en UI), o null.
  Future<LocalMatchOperation?> failedForPair(String low, String high);

  /// Todas las filas `failed` (banner de ChatsList).
  Future<List<LocalMatchOperation>> failedAll();

  /// Contadores para `SyncStatus`.
  Future<int> pendingCount();

  /// Contadores para `SyncStatus`.
  Future<int> failedCount();

  /// Reabre una fila `failed` como `pending` (reintento manual).
  Future<void> resetForRetry(String operationId);

  /// Reabre todas las `failed` (botón Reintentar).
  Future<void> resetAllFailed();

  /// Borra una fila (descarte explícito).
  Future<void> delete(String operationId);
}

/// Backend de matches para el replay (Supabase en producción).
abstract class MatchOutboxBackend {
  Future<String?> requestMatch(String requesterId, String receiverId);
  Future<Map<String, dynamic>?> getMatchById(String matchId);
  Future<bool> acceptMatch(String matchId);
  Future<bool> rejectMatch(String matchId);
}

/// Resumen de un ciclo de procesamiento (logging/estado, sin secretos).
class MatchOutboxSummary {
  const MatchOutboxSummary({
    this.processed = 0,
    this.completed = 0,
    this.retried = 0,
    this.failedTerminal = 0,
    this.skippedOffline = 0,
  });

  final int processed;
  final int completed;
  final int retried;
  final int failedTerminal;
  final int skippedOffline;
}

/// Implementación Isar de [MatchOperationStore] (producción).
class IsarMatchOperationStore implements MatchOperationStore {
  IsarMatchOperationStore([IsarService? isar]) : _isar = isar ?? IsarService();

  final IsarService _isar;

  @override
  Future<void> enqueue(LocalMatchOperation op) async {
    await _isar.isar.writeTxn(() async {
      await _isar.isar.localMatchOperations.putByOperationId(op);
    });
  }

  @override
  Future<List<LocalMatchOperation>> pendingDue(
    DateTime now, {
    bool ignoreBackoff = false,
  }) async {
    final all = await _isar.isar.localMatchOperations
        .filter()
        .stateEqualTo(MatchOpState.pending)
        .sortByCreatedAt()
        .findAll();
    if (ignoreBackoff) return all;
    return all
        .where((op) =>
            op.nextAttemptAt == null || !op.nextAttemptAt!.isAfter(now))
        .toList();
  }

  @override
  Future<bool> claim(String operationId) async {
    var claimed = false;
    await _isar.isar.writeTxn(() async {
      final op = await _isar.isar.localMatchOperations
          .filter()
          .operationIdEqualTo(operationId)
          .findFirst();
      if (op != null && op.state == MatchOpState.pending) {
        op.state = MatchOpState.inflight;
        await _isar.isar.localMatchOperations.put(op);
        claimed = true;
      }
    });
    return claimed;
  }

  @override
  Future<void> release(String operationId) async {
    await _isar.isar.writeTxn(() async {
      final op = await _isar.isar.localMatchOperations
          .filter()
          .operationIdEqualTo(operationId)
          .findFirst();
      if (op != null && op.state == MatchOpState.inflight) {
        op.state = MatchOpState.pending;
        await _isar.isar.localMatchOperations.put(op);
      }
    });
  }

  @override
  Future<void> recordRetry(
    String operationId,
    String errorCode,
    DateTime now,
  ) async {
    await _isar.isar.writeTxn(() async {
      final op = await _isar.isar.localMatchOperations
          .filter()
          .operationIdEqualTo(operationId)
          .findFirst();
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
      await _isar.isar.localMatchOperations.put(op);
    });
  }

  @override
  Future<void> markFailed(String operationId, String errorCode) async {
    await _isar.isar.writeTxn(() async {
      final op = await _isar.isar.localMatchOperations
          .filter()
          .operationIdEqualTo(operationId)
          .findFirst();
      if (op == null) return;
      op.state = MatchOpState.failed;
      op.lastErrorCode = errorCode;
      await _isar.isar.localMatchOperations.put(op);
    });
  }

  @override
  Future<void> remove(String operationId) async {
    await _isar.isar.writeTxn(() async {
      final op = await _isar.isar.localMatchOperations
          .filter()
          .operationIdEqualTo(operationId)
          .findFirst();
      if (op != null) {
        await _isar.isar.localMatchOperations.delete(op.id);
      }
    });
  }

  @override
  Future<bool> hasPendingForPair(String low, String high) async {
    final found = await _isar.isar.localMatchOperations
        .filter()
        .canonicalLowEqualTo(low)
        .canonicalHighEqualTo(high)
        .stateEqualTo(MatchOpState.pending)
        .findFirst();
    return found != null;
  }

  @override
  Future<LocalMatchOperation?> failedForPair(String low, String high) async {
    return _isar.isar.localMatchOperations
        .filter()
        .canonicalLowEqualTo(low)
        .canonicalHighEqualTo(high)
        .stateEqualTo(MatchOpState.failed)
        .findFirst();
  }

  @override
  Future<List<LocalMatchOperation>> failedAll() async {
    return _isar.isar.localMatchOperations
        .filter()
        .stateEqualTo(MatchOpState.failed)
        .sortByCreatedAt()
        .findAll();
  }

  @override
  Future<int> pendingCount() async {
    return _isar.isar.localMatchOperations
        .filter()
        .stateEqualTo(MatchOpState.pending)
        .count();
  }

  @override
  Future<int> failedCount() async {
    return _isar.isar.localMatchOperations
        .filter()
        .stateEqualTo(MatchOpState.failed)
        .count();
  }

  @override
  Future<void> resetForRetry(String operationId) async {
    await _isar.isar.writeTxn(() async {
      final op = await _isar.isar.localMatchOperations
          .filter()
          .operationIdEqualTo(operationId)
          .findFirst();
      if (op != null && op.state == MatchOpState.failed) {
        op.state = MatchOpState.pending;
        op.retryCount = 0;
        op.nextAttemptAt = null;
        op.lastErrorCode = null;
        await _isar.isar.localMatchOperations.put(op);
      }
    });
  }

  @override
  Future<void> resetAllFailed() async {
    final failed = await failedAll();
    for (final op in failed) {
      await resetForRetry(op.operationId);
    }
  }

  @override
  Future<void> delete(String operationId) async {
    await remove(operationId);
  }
}

/// Backend vivo sobre [SupabaseService] (producción).
class LiveMatchOutboxBackend implements MatchOutboxBackend {
  LiveMatchOutboxBackend([SupabaseService? supabase])
      : _supabase = supabase ?? SupabaseService();

  final SupabaseService _supabase;

  @override
  Future<String?> requestMatch(String requesterId, String receiverId) =>
      _supabase.requestMatch(requesterId, receiverId);

  @override
  Future<Map<String, dynamic>?> getMatchById(String matchId) =>
      _supabase.getMatchById(matchId);

  @override
  Future<bool> acceptMatch(String matchId) => _supabase.acceptMatch(matchId);

  @override
  Future<bool> rejectMatch(String matchId) => _supabase.rejectMatch(matchId);
}

/// Factorías de operaciones (validan fail-closed vía MatchPair/MatchOutboxPolicy).
LocalMatchOperation buildRequestOp({
  required String requester,
  required String receiver,
  required DateTime now,
}) {
  return LocalMatchOperation()
    ..operationId = MatchOutboxPolicy.requestId(
      requester: requester,
      receiver: receiver,
    )
    ..operationType = MatchOpType.request
    ..canonicalLow = MatchPair.canonicalLow(requester, receiver)
    ..canonicalHigh = MatchPair.canonicalHigh(requester, receiver)
    ..actorUserId = requester.trim()
    ..targetUserId = receiver.trim()
    ..state = MatchOpState.pending
    ..createdAt = now;
}

/// Factorías de operaciones (validan fail-closed vía MatchPair/MatchOutboxPolicy).
LocalMatchOperation buildAcceptOp({
  required String serverMatchId,
  required String actor,
  required String low,
  required String high,
  required DateTime now,
}) {
  if (low.trim().isEmpty || high.trim().isEmpty) {
    throw const InvalidMatchIdentityError('accept needs canonical pair');
  }
  return LocalMatchOperation()
    ..operationId = MatchOutboxPolicy.acceptId(
      serverMatchId: serverMatchId,
      actor: actor,
    )
    ..operationType = MatchOpType.accept
    ..canonicalLow = low.trim()
    ..canonicalHigh = high.trim()
    ..actorUserId = actor.trim()
    ..serverMatchId = serverMatchId.trim()
    ..state = MatchOpState.pending
    ..createdAt = now;
}

/// Factorías de operaciones (validan fail-closed vía MatchPair/MatchOutboxPolicy).
LocalMatchOperation buildRejectOp({
  required String serverMatchId,
  required String actor,
  required String low,
  required String high,
  required DateTime now,
}) {
  if (low.trim().isEmpty || high.trim().isEmpty) {
    throw const InvalidMatchIdentityError('reject needs canonical pair');
  }
  return LocalMatchOperation()
    ..operationId = MatchOutboxPolicy.rejectId(
      serverMatchId: serverMatchId,
      actor: actor,
    )
    ..operationType = MatchOpType.reject
    ..canonicalLow = low.trim()
    ..canonicalHigh = high.trim()
    ..actorUserId = actor.trim()
    ..serverMatchId = serverMatchId.trim()
    ..state = MatchOpState.pending
    ..createdAt = now;
}

/// Procesador convergente (inyectable; sin singletons propios).
class MatchOutboxProcessor {
  MatchOutboxProcessor._();

  /// Ejecuta todas las operaciones vencidas. Serializado por el llamador
  /// (`SyncService.syncNow` nunca corre en paralelo consigo mismo) + flag
  /// `inflight` por operación (doble guarda ante doble disparo).
  static Future<MatchOutboxSummary> processAll({
    required MatchOperationStore store,
    required MatchOutboxBackend backend,
    required Future<bool> Function() isOnline,
    required DateTime Function() clock,
    bool ignoreBackoff = false,
  }) async {
    var processed = 0;
    var completed = 0;
    var retried = 0;
    var failedTerminal = 0;

    if (!await isOnline()) {
      return const MatchOutboxSummary(skippedOffline: 1);
    }
    final ops = await store.pendingDue(clock(), ignoreBackoff: ignoreBackoff);
    for (final op in ops) {
      processed++;
      // 1. Validación fail-closed (corrupta ⇒ terminal, sin crash).
      final invalid = MatchOutboxPolicy.validateOp(
        operationType: op.operationType,
        canonicalLow: op.canonicalLow,
        canonicalHigh: op.canonicalHigh,
        actorUserId: op.actorUserId,
        targetUserId: op.targetUserId,
        serverMatchId: op.serverMatchId,
      );
      if (invalid != null) {
        await store.markFailed(op.operationId, invalid);
        failedTerminal++;
        continue;
      }
      // 2. Claim (seguridad concurrente).
      if (!await store.claim(op.operationId)) continue;
      try {
        switch (op.operationType) {
          case MatchOpType.request:
            if (await _replayRequest(store, backend, isOnline, op)) {
              completed++;
            } else {
              retried++;
            }
            break;
          case MatchOpType.accept:
            final done = await _replayAccept(store, backend, op);
            if (done == true) {
              completed++;
            } else if (done == false) {
              failedTerminal++;
            } else {
              retried++;
            }
            break;
          case MatchOpType.reject:
            final done = await _replayReject(store, backend, op);
            if (done == true) {
              completed++;
            } else if (done == false) {
              failedTerminal++;
            } else {
              retried++;
            }
            break;
        }
      } catch (e) {
        final code = MatchOutboxPolicy.classifyException(e);
        if (MatchOpError.isTerminal(code)) {
          await store.markFailed(op.operationId, code);
          failedTerminal++;
        } else {
          await store.recordRetry(op.operationId, code, clock());
          retried++;
        }
      }
    }
    return MatchOutboxSummary(
      processed: processed,
      completed: completed,
      retried: retried,
      failedTerminal: failedTerminal,
    );
  }

  /// true = done, false = transient (retry++) — nunca crea duplicados: el
  /// backend canónico crea o reutiliza y su id completa la operación.
  static Future<bool> _replayRequest(
    MatchOperationStore store,
    MatchOutboxBackend backend,
    Future<bool> Function() isOnline,
    LocalMatchOperation op,
  ) async {
    final id = await backend.requestMatch(op.actorUserId, op.targetUserId!);
    if (MatchPair.isValidMatchId(id)) {
      await store.remove(op.operationId);
      return true;
    }
    // Sin red a mitad de ciclo: liberar sin quemar reintentos.
    if (!await isOnline()) {
      await store.release(op.operationId);
      return false;
    }
    await store.recordRetry(op.operationId, MatchOpError.server, DateTime.now());
    return false;
  }

  /// true = done, false = terminal, null = transient.
  static Future<bool?> _replayAccept(
    MatchOperationStore store,
    MatchOutboxBackend backend,
    LocalMatchOperation op,
  ) async {
    final row = await backend.getMatchById(op.serverMatchId!);
    if (row == null) {
      await store.markFailed(op.operationId, MatchOpError.missing);
      return false;
    }
    if (!MatchPair.canAccept(row, op.actorUserId)) {
      await store.markFailed(op.operationId, MatchOpError.auth);
      return false;
    }
    switch (row['status'] as String?) {
      case 'accepted':
        await store.remove(op.operationId);
        return true;
      case 'pending':
        if (await backend.acceptMatch(op.serverMatchId!)) {
          await store.remove(op.operationId);
          return true;
        }
        await store.recordRetry(
          op.operationId,
          MatchOpError.server,
          DateTime.now(),
        );
        return null;
      default:
        // rejected u otro: gana la autoridad del servidor (sin downgrade ni
        // reescritura destructiva).
        await store.markFailed(op.operationId, MatchOpError.state);
        return false;
    }
  }

  /// true = done, false = terminal, null = transient.
  static Future<bool?> _replayReject(
    MatchOperationStore store,
    MatchOutboxBackend backend,
    LocalMatchOperation op,
  ) async {
    final row = await backend.getMatchById(op.serverMatchId!);
    if (row == null) {
      await store.markFailed(op.operationId, MatchOpError.missing);
      return false;
    }
    if (!MatchPair.canReject(row, op.actorUserId)) {
      await store.markFailed(op.operationId, MatchOpError.auth);
      return false;
    }
    switch (row['status'] as String?) {
      case 'rejected':
        await store.remove(op.operationId);
        return true;
      case 'pending':
        if (await backend.rejectMatch(op.serverMatchId!)) {
          await store.remove(op.operationId);
          return true;
        }
        await store.recordRetry(
          op.operationId,
          MatchOpError.server,
          DateTime.now(),
        );
        return null;
      default:
        // accepted: no degradar — terminal sin escribir.
        await store.markFailed(op.operationId, MatchOpError.state);
        return false;
    }
  }
}
