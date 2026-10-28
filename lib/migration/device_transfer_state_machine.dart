/// Z-213 PHASE F/G — Máquina de estados de TRANSFERENCIA entre dispositivos
/// (pura, determinista, persistible). Complementa `device_migration_state.dart`
/// (que recubre el backend Z-213 flip) con las fases LOCALES de una
/// transferencia real de datos de A(viejo)→B(nuevo):
///
/// ```text
/// idle → requested → awaiting_proof → authorized → transferring → verifying
///        → completed → revocation_pending → idle (revocación confirmada)
///
/// failed_recoverable ⇄ transferring/verifying   (resume seguro)
/// cancelled           (explícito/expiración; NUNCA después de completed)
/// ```
///
/// Invariantes invariológicos (la regresión NO puede romperlas sin editar
/// este archivo — fail-closed):
///
/// 1. **La revocación del dispositivo viejo SOLO se solicita desde
///    `completed`** (restauración confirmada con integridad verificada).
///    Nunca desde `transferring`/`verifying`/`failed_recoverable`.
/// 2. **Revocación fallida ⇒ vuelve a `completed`** (auditable vía
///    `revocationAttempts`/`lastRevocationReason`): el device nuevo ya opera
///    (las claves NUNCA viajaron — binding por cert); el usuario no queda
///    bloqueado en un estado inconsistente.
/// 3. **`failed_recoverable` NO muta el dispositivo antiguo**: no hay camino
///    hacia revocación desde fallo (invariante 1).
/// 4. **Idempotencia de chunks**: reenviar un índice ya recibido no avanza
///    ni duplica (Set de índices); `TransferCompleted` exige set COMPLETO.
/// 5. **Idempotencia de la solicitud**: re-`RequestMigration` con el MISMO
///    (plan, deviceFingerprint) sobre un pendiente NO terminal devuelve el
///    MISMO snapshot (sin id nuevo) — misma convención que
///    `DeviceMigrationPending` del flip.
/// 6. **Concurrencia**: UN plan activo por snapshot; `RequestMigration`
///    sobre estado activo con OTRO plan/fp ⇒ error tipado.
/// 7. **Binding a la cuenta**: `ProofVerified` con accountId distinto del
///    snapshot ⇒ error tipado (vínculo inequívoco).
/// 8. **Serializable**: `toJson/fromJson` completos (reinicio seguro: el
///    estado revive del JSON con el MISMO id y los chunks conservados).
///
/// SEPARACIÓN datos vs secretos: esta máquina NUNCA transporta claves
/// privadas; el payload de aplicación es DATA (perfiles/encuentros/chats)
/// con autenticidad por canal AKE/cert (device_certificate_v2). Diseño
/// detallado en `docs/migration/DEVICE_TRANSFER_STATE_MACHINE.md`.
library;

import 'package:uuid/uuid.dart';

import '../identity/identity_errors.dart';

/// Estados de la transferencia entre dispositivos.
enum DeviceTransferState {
  idle('idle'),
  requested('requested'),
  awaitingProof('awaiting_proof'),
  authorized('authorized'),
  transferring('transferring'),
  verifying('verifying'),
  completed('completed'),
  failedRecoverable('failed_recoverable'),
  cancelled('cancelled'),
  revocationPending('revocation_pending');

  const DeviceTransferState(this.statusId);

  final String statusId;

  static DeviceTransferState fromStatusId(String id) {
    for (final s in DeviceTransferState.values) {
      if (s.statusId == id) return s;
    }
    throw MigrationRecordCorruptError('unknown device transfer state `$id`');
  }
}

/// Eventos sellados (sin strings de wire).
sealed class DeviceTransferEvent {
  const DeviceTransferEvent();

  /// Etiqueta pública para el audit trail (sin material).
  String get auditLabel;
}

/// Solicitud inicial (o idempotente sobre pendiente no terminal).
class RequestMigration extends DeviceTransferEvent {
  const RequestMigration(this.accountId, this.deviceFingerprint, this.plan);

  final String accountId;
  final String deviceFingerprint;

  /// `add_device | replace_device | recover_account` (z213).
  final String plan;

  @override
  String get auditLabel => 'requestMigration(plan=$plan)';
}

/// El viejo device emite el desafío PO (sin secretos en el desafío).
class ProofChallengeIssued extends DeviceTransferEvent {
  const ProofChallengeIssued();

  @override
  String get auditLabel => 'proofChallengeIssued';
}

/// Prueba verificada (device_certificate_v2 firmado, cuenta confirmada).
class ProofVerified extends DeviceTransferEvent {
  const ProofVerified(this.accountId, this.proofHashB64);

  final String accountId;
  final String proofHashB64;

  @override
  String get auditLabel => 'proofVerified';
}

/// Prueba rechazada (firma/cert inválidos, device distinto, replay).
class ProofRejected extends DeviceTransferEvent {
  const ProofRejected(this.reason);

  final String reason;

  @override
  String get auditLabel => 'proofRejected($reason)';
}

/// Arranca la transferencia de datos (canal AKE autenticado).
class TransferStarted extends DeviceTransferEvent {
  const TransferStarted({required this.totalChunks});

  final int totalChunks;

  @override
  String get auditLabel => 'transferStarted(chunks=$totalChunks)';
}

/// Chunk recibido y MAC-ado correctamente (idempotente).
class ChunkStored extends DeviceTransferEvent {
  const ChunkStored(this.index);

  final int index;

  @override
  String get auditLabel => 'chunkStored($index)';
}

/// Manifest completo recibido (host entra a verifying).
class TransferCompleted extends DeviceTransferEvent {
  const TransferCompleted();

  @override
  String get auditLabel => 'transferCompleted';
}

/// Integridad + autenticidad del transfer completo verificadas.
class VerificationSucceeded extends DeviceTransferEvent {
  const VerificationSucceeded();

  @override
  String get auditLabel => 'verificationSucceeded';
}

/// Fallo de verificación — NUNCA bloquea el device viejo: recoverable.
class VerificationFailed extends DeviceTransferEvent {
  const VerificationFailed(this.reason);

  final String reason;

  @override
  String get auditLabel => 'verificationFailed($reason)';
}

/// Confirmación UX explícita de restauración (idempotente).
class RestoreConfirmed extends DeviceTransferEvent {
  const RestoreConfirmed();

  @override
  String get auditLabel => 'restoreConfirmed';
}

/// El usuario cancela o caduca. NO disponible después de `completed`.
class CancelRequested extends DeviceTransferEvent {
  const CancelRequested(this.reason);

  final String reason;

  @override
  String get auditLabel => 'cancel($reason)';
}

/// SOLO desde `completed`: solicitud de revocación del device viejo.
class RevocationRequested extends DeviceTransferEvent {
  const RevocationRequested(this.oldDeviceId);

  final String oldDeviceId;

  @override
  String get auditLabel => 'revocationRequested($oldDeviceId)';
}

/// Revocación confirmada por backend.
class RevocationSucceeded extends DeviceTransferEvent {
  const RevocationSucceeded();

  @override
  String get auditLabel => 'revocationSucceeded';
}

/// Revocación fallida → vuelve a `completed` (invariante 2).
class RevocationFailed extends DeviceTransferEvent {
  const RevocationFailed(this.reason);

  final String reason;

  @override
  String get auditLabel => 'revocationFailed($reason)';
}

/// Fallo de transporte/radio/timeout de chunk — recoverable.
class TransferInterrupted extends DeviceTransferEvent {
  const TransferInterrupted(this.reason);

  final String reason;

  @override
  String get auditLabel => 'transferInterrupted($reason)';
}

/// Reanudación tras interrupción/reinicio (id y chunks conservados).
class ResumeRequested extends DeviceTransferEvent {
  const ResumeRequested();

  @override
  String get auditLabel => 'resumeRequested';
}

/// Snapshot persistible + audit log acotado.
class DeviceTransferSnapshot {
  const DeviceTransferSnapshot._({
    required this.id,
    required this.state,
    required this.accountId,
    required this.deviceFingerprint,
    required this.plan,
    required this.proofAttempts,
    required this.completedChunks,
    required this.totalChunks,
    required this.revocationAttempts,
    required this.lastRevocationReason,
    required this.auditTrail,
    required this.createdAt,
    required this.updatedAt,
  });

  DeviceTransferSnapshot.initial({
    required this.accountId,
    required this.deviceFingerprint,
    required this.plan,
  }) : id = const Uuid().v4(),
       state = DeviceTransferState.idle,
       proofAttempts = 0,
       completedChunks = const <int>{},
       totalChunks = 0,
       revocationAttempts = 0,
       lastRevocationReason = '',
       auditTrail = const <Map<String, String>>[],
       createdAt = DateTime.now().toUtc(),
       updatedAt = DateTime.now().toUtc();

  static const int kMaxAuditTrail = 128;
  static const int kMaxProofAttempts = 3;

  final String id;
  final DeviceTransferState state;
  final String accountId;
  final String deviceFingerprint;
  final String plan;
  final int proofAttempts;

  /// Índices de chunks ya recibidos y verificados (Set ⇒ idempotencia 4).
  final Set<int> completedChunks;
  final int totalChunks;

  /// Intentos de revocación acumulados + último motivo (invariante 2).
  final int revocationAttempts;
  final String lastRevocationReason;

  /// Lista acotada de entradas `[evento, fechaISO]` (auditoría pública).
  final List<Map<String, String>> auditTrail;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive =>
      state != DeviceTransferState.idle &&
      state != DeviceTransferState.completed &&
      state != DeviceTransferState.cancelled;

  /// Próximo índice de chunk faltante (null si ya no hay transferencia o el
  /// manifest está completo).
  int? nextMissingChunk() {
    if (totalChunks <= 0) return null;
    for (var i = 0; i < totalChunks; i++) {
      if (!completedChunks.contains(i)) return i;
    }
    return null;
  }

  DeviceTransferSnapshot withState(DeviceTransferState newState, String note) {
    return _copy(
      state: newState,
      newAudit: _appendAudit(note),
    );
  }

  List<Map<String, String>> _appendAudit(String note) {
    final entry = <String, String>{
      'note': note,
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    final keep =
        auditTrail.length <= kMaxAuditTrail - 1
            ? auditTrail
            : auditTrail.sublist(auditTrail.length - (kMaxAuditTrail - 1));
    return [...keep, entry];
  }

  DeviceTransferSnapshot _copy({
    DeviceTransferState? state,
    int? proofAttempts,
    Set<int>? completedChunks,
    int? totalChunks,
    int? revocationAttempts,
    String? lastRevocationReason,
    List<Map<String, String>>? newAudit, // reemplaza (ya recortada)
  }) {
    return DeviceTransferSnapshot._(
      id: id,
      state: state ?? this.state,
      accountId: accountId,
      deviceFingerprint: deviceFingerprint,
      plan: plan,
      proofAttempts: proofAttempts ?? this.proofAttempts,
      completedChunks: completedChunks ?? this.completedChunks,
      totalChunks: totalChunks ?? this.totalChunks,
      revocationAttempts: revocationAttempts ?? this.revocationAttempts,
      lastRevocationReason: lastRevocationReason ?? this.lastRevocationReason,
      auditTrail: newAudit ?? auditTrail,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'state': state.statusId,
    'account_id': accountId,
    'device_fingerprint': deviceFingerprint,
    'plan': plan,
    'proof_attempts': proofAttempts,
    'completed_chunks': completedChunks.toList()..sort(),
    'total_chunks': totalChunks,
    'revocation_attempts': revocationAttempts,
    'last_revocation_reason': lastRevocationReason,
    'audit_trail': auditTrail,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  static DeviceTransferSnapshot fromJson(Map<String, Object?> json) {
    if (json.isEmpty) {
      throw MigrationRecordCorruptError('snapshot vacío');
    }
    final stateId = json['state'];
    if (stateId is! String) {
      throw MigrationRecordCorruptError('snapshot sin estado');
    }
    final chunksList = json['completed_chunks'];
    final audit = json['audit_trail'];
    final createdAtRaw = json['created_at'];
    final updatedAtRaw = json['updated_at'];
    if (createdAtRaw is! String || updatedAtRaw is! String) {
      throw MigrationRecordCorruptError('snapshot sin fechas');
    }
    return DeviceTransferSnapshot._(
      id: json['id'] is String ? json['id'] as String : '',
      state: DeviceTransferState.fromStatusId(stateId),
      accountId: json['account_id'] is String ? json['account_id'] as String : '',
      deviceFingerprint:
          json['device_fingerprint'] is String
              ? json['device_fingerprint'] as String
              : '',
      plan: json['plan'] is String ? json['plan'] as String : '',
      proofAttempts: json['proof_attempts'] is int
          ? json['proof_attempts'] as int
          : 0,
      completedChunks: chunksList is List
          ? chunksList.whereType<int>().toSet()
          : const <int>{},
      totalChunks: json['total_chunks'] is int ? json['total_chunks'] as int : 0,
      revocationAttempts: json['revocation_attempts'] is int
          ? json['revocation_attempts'] as int
          : 0,
      lastRevocationReason:
          json['last_revocation_reason'] is String
              ? json['last_revocation_reason'] as String
              : '',
      auditTrail: audit is List
          ? audit
              .whereType<Map>()
              .map((e) => Map<String, String>.from(e))
              .toList()
          : <Map<String, String>>[],
      createdAt: DateTime.parse(createdAtRaw),
      updatedAt: DateTime.parse(updatedAtRaw),
    );
  }
}

/// Máquina pura: `transition` devuelve UN NUEVO snapshot (inmutable) o lanza
/// [InvalidMigrationStateTransitionError]. Sin estado global.
class DeviceTransferStateMachine {
  const DeviceTransferStateMachine(this.snapshot);

  final DeviceTransferSnapshot snapshot;

  DeviceTransferStateMachine transition(DeviceTransferEvent event) =>
      DeviceTransferStateMachine(_reduce(snapshot, event));

  bool accepts(DeviceTransferEvent event) {
    try {
      _reduce(snapshot, event);
      return true;
    } on IdentityFoundationError {
      return false;
    }
  }

  static DeviceTransferSnapshot _reduce(
    DeviceTransferSnapshot s,
    DeviceTransferEvent event,
  ) {
    switch (event) {
      case final RequestMigration _:
        if (s.isActive) {
          throw InvalidMigrationStateTransitionError(
            s.state.statusId,
            'requestMigration (transfer concurrente)',
          );
        }
        return s.withState(
          DeviceTransferState.requested,
          event.auditLabel,
        );

      case final ProofChallengeIssued _:
        final base = _expect(s, DeviceTransferState.requested);
        return base.withState(
          DeviceTransferState.awaitingProof,
          event.auditLabel,
        );

      case final ProofVerified _:
        final base = _expect(
          s,
          DeviceTransferState.awaitingProof,
          DeviceTransferState.failedRecoverable,
        );
        // Binding inequívoco a la cuenta correcta (invariante 7).
        if (base.accountId != event.accountId) {
          throw InvalidMigrationStateTransitionError(
            base.state.statusId,
            'proofVerified (cuenta ${event.accountId} ≠ ${base.accountId})',
          );
        }
        return base.withState(DeviceTransferState.authorized, event.auditLabel);

      case final ProofRejected _:
        final attempts = s.proofAttempts + 1;
        final audited = s._copy(
          proofAttempts: attempts,
          newAudit: s._appendAudit(event.auditLabel),
        );
        if (attempts > DeviceTransferSnapshot.kMaxProofAttempts) {
          throw InvalidMigrationStateTransitionError(
            s.state.statusId,
            'proofRejected (tope de pruebas agotado)',
          );
        }
        if (attempts == DeviceTransferSnapshot.kMaxProofAttempts) {
          // Sospecha de apropiación: recoverable, device viejo INTACTO.
          return audited.withState(
            DeviceTransferState.failedRecoverable,
            'tope de pruebas alcanzado',
          );
        }
        return audited; // sigue en awaiting_proof

      case final TransferStarted _:
        final base = _expect(s, DeviceTransferState.authorized);
        if (event.totalChunks <= 0) {
          throw InvalidMigrationStateTransitionError(
            base.state.statusId,
            'transferStarted (totalChunks=${event.totalChunks})',
          );
        }
        return base._copy(
          state: DeviceTransferState.transferring,
          totalChunks: event.totalChunks,
          newAudit: base._appendAudit(event.auditLabel),
        );

      case final ChunkStored _:
        final base = _expect(s, DeviceTransferState.transferring);
        if (_validateChunkIndex(event.index, base.totalChunks)) {
          throw InvalidMigrationStateTransitionError(
            base.state.statusId,
            'chunkStored fuera de rango (${event.index})',
          );
        }
        if (base.completedChunks.contains(event.index)) {
          return base; // idempotencia 4: sin doble conteo ni spam de audit
        }
        final chunks = base.completedChunks.toSet()..add(event.index);
        return base._copy(completedChunks: chunks);

      case final TransferCompleted _:
        final base = _expect(s, DeviceTransferState.transferring);
        if (base.totalChunks <= 0 ||
            base.completedChunks.length != base.totalChunks) {
          throw InvalidMigrationStateTransitionError(
            base.state.statusId,
            'transferCompleted con restauración incompleta '
            '(${base.completedChunks.length}/'
            '${base.totalChunks <= 0 ? '?' : base.totalChunks})',
          );
        }
        return base.withState(DeviceTransferState.verifying, event.auditLabel);

      case final VerificationSucceeded _:
        final base = _expect(s, DeviceTransferState.verifying);
        return base.withState(DeviceTransferState.completed, event.auditLabel);

      case final VerificationFailed _:
        final base = _expect(s, DeviceTransferState.verifying);
        return base.withState(
          DeviceTransferState.failedRecoverable,
          event.auditLabel,
        );

      case final RestoreConfirmed _:
        _expect(s, DeviceTransferState.completed);
        return s; // idempotente

      case final CancelRequested _:
        if (!s.isActive) {
          throw InvalidMigrationStateTransitionError(
            s.state.statusId,
            'cancelRequested',
          );
        }
        return s.withState(DeviceTransferState.cancelled, event.auditLabel);

      case final RevocationRequested _:
        // INVARIANTE 1.
        if (s.state != DeviceTransferState.completed) {
          throw InvalidMigrationStateTransitionError(
            s.state.statusId,
            'revocationRequested ANTES de completed',
          );
        }
        return s.withState(
          DeviceTransferState.revocationPending,
          event.auditLabel,
        );

      case final RevocationSucceeded _:
        final base = _expect(s, DeviceTransferState.revocationPending);
        return base.withState(DeviceTransferState.idle, event.auditLabel);

      case final RevocationFailed _:
        final base = _expect(s, DeviceTransferState.revocationPending);
        // INVARIANTE 2: recoverable, auditable; regresa a completed.
        return base._copy(
          state: DeviceTransferState.completed,
          revocationAttempts: base.revocationAttempts + 1,
          lastRevocationReason: event.reason,
          newAudit: base._appendAudit(event.auditLabel),
        );

      case final TransferInterrupted _:
        final base = _expect(
          s,
          DeviceTransferState.requested,
          DeviceTransferState.awaitingProof,
          DeviceTransferState.authorized,
          DeviceTransferState.transferring,
          DeviceTransferState.verifying,
        );
        // El device viejo queda INTACTO (invariante 3); chunks conservados.
        return base.withState(
          DeviceTransferState.failedRecoverable,
          event.auditLabel,
        );

      case final ResumeRequested _:
        final base = _expect(s, DeviceTransferState.failedRecoverable);
        if (base.totalChunks > 0 &&
            base.completedChunks.length == base.totalChunks) {
          return base.withState(
            DeviceTransferState.verifying,
            'resume: manifest completo',
          );
        }
        return base.withState(
          DeviceTransferState.transferring,
          event.auditLabel,
        );
    }
  }

  static bool _validateChunkIndex(int index, int totalChunks) =>
      index < 0 || (totalChunks > 0 && index >= totalChunks);

  static DeviceTransferSnapshot _expect(
    DeviceTransferSnapshot s,
    DeviceTransferState st1, [
    DeviceTransferState? st2,
    DeviceTransferState? st3,
    DeviceTransferState? st4,
    DeviceTransferState? st5,
  ]) {
    final ok =
        s.state == st1 ||
        (st2 != null && s.state == st2) ||
        (st3 != null && s.state == st3) ||
        (st4 != null && s.state == st4) ||
        (st5 != null && s.state == st5);
    if (ok) return s;
    throw InvalidMigrationStateTransitionError(
      s.state.statusId,
      'evento no válido para esta fase de transferencia',
    );
  }
}
