/// PHASE 2.2.1 — Controlador de la migración de identidad.
///
/// NEW FOUNDATION EXTENSION — NOT YET INTEGRATED IN THE APP FLOW.
///
/// Orquesta la máquina pura (`MigrationStateMachine`) con persistencia
/// idempotente y auditoría. Sin singletons: estado inyectado (mandato §18),
/// mismo criterio que `IdentityRegistry`.
///
/// Contratos de seguridad:
/// - **Fail-closed**: transición prohibida ⇒ [InvalidMigrationStateTransitionError];
///   evento en estado `FINALIZED` ⇒ [MigrationAlreadyFinalizedError]; rollback
///   desde un estado distinto de `MIGRATION_FAILED` ⇒
///   [MigrationRollbackNotAllowedError]. Nunca se "salta" ni se inventa un estado.
/// - **Idempotencia**: la persistencia es upsert por índice único
///   (`putByMigrationId`) y la máquina es determinista. Los efectos secundarios
///   de fases posteriores (import, materialización) DEBEN ser idempotentes y
///   ejecutarse ANTES de persistir el nuevo estado: un crash entre efecto y
///   persistencia deja el estado anterior y la re-aplicación del mismo evento
///   re-ejecuta el efecto sin duplicar (semántica at-least-once).
/// - **Auditabilidad**: cada evento se registra como
///   `iso|estado_origen|evento|causa(tipada)`. NUNCA se registran seeds,
///   claves, envelopes, tokens ni payloads (PHASE 2.1.1 bridge §9).
/// - **Sin secretos**: el registro solo guarda metadatos públicos (I-004).
library;

import 'identity_errors.dart';
import 'migration_models.dart';
import 'migration_persistence.dart';
import 'migration_state_machine.dart';

/// Controlador de migración (inyectable, sin estado global).
class MigrationController {
  MigrationController({
    required this.repository,
    this.log,
  });

  final MigrationRepository repository;

  /// Callback de observabilidad (los logs SOLO llevan identificadores públicos
  /// y estados — nunca material privado, §19 encargo).
  final void Function(String message)? log;

  static const String _logTag = '[MIGRATION]';

  /// Carga el registro actual; ausencia de registro ⇒ estado `LEGACY`.
  Future<MigrationRecord> loadRecord() async {
    final record = await repository.load();
    if (record == null) {
      return MigrationRecord.initial();
    }
    return record;
  }

  /// Estado canónico actual de la migración (nunca null: ausencia ⇒ legacy).
  Future<MigrationState> currentState() async =>
      (await loadRecord()).state;

  Future<bool> isFinalized() async =>
      (await loadRecord()).state == MigrationState.finalized;

  /// Fail-closed: lanza [MigrationAlreadyFinalizedError] si la migración ya
  /// terminó (FINALIZED es terminal e irrevocable).
  Future<void> assertNotFinalized() async {
    if (await isFinalized()) {
      throw const MigrationAlreadyFinalizedError();
    }
  }

  /// Aplica un evento de la máquina de migración con validación estricta,
  /// persistencia idempotente y registro de auditoría.
  ///
  /// [cause] es una causa TIPADA para eventos de fallo (p.ej.
  /// `validation_failed`); nunca material secreto. Los binds de identidad
  /// (`legacyZoneId`, `boundAccountId`, `boundDeviceId`) y los fingerprints son
  /// metadatos públicos opcionales que las fases de bridge (2.2.2/2.2.3)
  /// rellenarán al materializar la identidad.
  Future<MigrationRecord> apply(
    MigrationEvent event, {
    String? cause,
    String? legacyZoneId,
    String? boundAccountId,
    String? boundDeviceId,
    String? fingerprintAcc,
    String? fingerprintDev,
  }) async {
    final current = await loadRecord();
    if (current.state == MigrationState.finalized) {
      throw const MigrationAlreadyFinalizedError();
    }

    final target = MigrationStateMachine.nextState(
      current.state,
      event,
    );

    final now = DateTime.now().toUtc();
    final isFailure = MigrationStateMachine.failureEvents.contains(event);
    final resolvedCause = isFailure ? (cause ?? event.name) : null;

    final updated = current.copyWith(
      state: target,
      lastEvent: event,
      updatedAt: now,
      attemptCount: isFailure
          ? current.attemptCount + 1
          : current.attemptCount,
      legacyZoneId: legacyZoneId ?? current.legacyZoneId,
      boundAccountId: boundAccountId ?? current.boundAccountId,
      boundDeviceId: boundDeviceId ?? current.boundDeviceId,
      fingerprintAcc: fingerprintAcc ?? current.fingerprintAcc,
      fingerprintDev: fingerprintDev ?? current.fingerprintDev,
      failedCause: isFailure
          ? resolvedCause
          : current.failedCause,
      audit: [...current.audit, _auditLine(now, current.state, event, resolvedCause)],
    );
    final saved = await repository.save(updated);
    _log('state=${saved.state.statusId} event=${event.name}');
    return saved;
  }

  /// Rollback seguro: ÚNICO camino de regreso a `LEGACY`, exclusivamente desde
  /// `MIGRATION_FAILED` (PHASE 2.1.1 §5: prohibido regresar de `AUTHORIZED` en
  /// adelante sin pasar por `MIGRATION_FAILED → rollback`).
  ///
  /// No destruye nada: los artefactos materializados permanecen hasta
  /// `FINALIZED`; el rollback solo restablece el estado de migración (los datos
  /// legacy nunca fueron borrados en la fase de import).
  Future<MigrationRecord> rollback({required String cause}) async {
    final current = await loadRecord();
    if (current.state != MigrationState.migrationFailed) {
      throw MigrationRollbackNotAllowedError(current.state.statusId);
    }
    final now = DateTime.now().toUtc();
    final updated = current.copyWith(
      state: MigrationState.legacy,
      lastEvent: MigrationEvent.rollbackConfirmed,
      updatedAt: now,
      rollbackCount: current.rollbackCount + 1,
      failedCause: cause,
      audit: [
        ...current.audit,
        _auditLine(now, current.state, MigrationEvent.rollbackConfirmed, cause),
      ],
    );
    final saved = await repository.save(updated);
    _log('state=legacy event=rollbackConfirmed cause=$cause');
    return saved;
  }

  /// Línea de auditoría: `iso|estado_origen|evento|causa`. Los ids de
  /// estado/evento y los ISO timestamps nunca contienen '\n' → separación
  /// segura.
  static String _auditLine(
    DateTime now,
    MigrationState from,
    MigrationEvent event,
    String? cause,
  ) =>
      '${now.toIso8601String()}|${from.statusId}|${event.name}|${cause ?? ''}';

  void _log(String message) {
    log?.call('$_logTag $message');
  }
}