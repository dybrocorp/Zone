/// PHASE 2.2.1 — Máquina de estados de la migración de identidad.
///
/// NEW FOUNDATION EXTENSION — NOT YET INTEGRATED IN THE APP FLOW.
///
/// Materializa el diseño aprobado en PHASE 2.1.1
/// (`docs/migration/IDENTITY_MIGRATION_STATE_MACHINE.md`) y su actualización
/// bajo la ADR de PHASE 2.1.2 (`ADR-0001-X25519-OWNERSHIP.md`, import de la
/// X25519 legacy como encryption key de device_1):
///
/// ```
/// LEGACY ─▶ DISCOVERED ─▶ VALIDATED ─▶ BRIDGED ─▶ AUTHORIZED ─▶ MIGRATED
///               │            │            │            │          │
///               │            │            │            │          ▼
///               │            │            │            │       VERIFIED ─▶ FINALIZED
///               └─▶ MIGRATION_FAILED ◀───┴────────────┴──────────┘
///                        │  (única salida: rollback confirmado)
///                        ▼
///                     LEGACY
/// ```
///
/// Máquina PURA, determinista, sin estado global (mandato §18 / PHASE 2.1.1
/// §9): las transiciones permitidas se modelan explícitamente y cualquier otra
/// combinación devuelve [MigrationTransitionResult.invalid] o lanza
/// [InvalidMigrationStateTransitionError] con la API estricta. Mismo patrón
/// fail-closed que `DeviceLifecycle` (I-030).
///
/// Invariantes (PHASE 2.1.1 §5):
/// - sin saltos hacia delante; `FINALIZED` y `MIGRATION_FAILED` son terminales;
/// - `MIGRATION_FAILED → LEGACY` es la ÚNICA transición hacia atrás;
/// - `legacy → verified/finalized` sin pasar por el bridge: prohibido.
library;

import 'identity_errors.dart';

/// Identificador del registro singleton de migración por instalación.
///
/// La migración es un proceso unitario por instalación/app. `putByMigrationId`
/// + índice único garantizan idempotencia de escritura (no duplicados).
const String kMigrationSingletonId = 'default';

/// Estados de la máquina de migración. `statusId` es el identificador canónico
/// que se persiste (nunca derivado de UI, mismo criterio que
/// `IdentityKeyAlgorithm.algorithmId`).
enum MigrationState {
  /// Identidad legacy activa; fundación ausente o no integrada.
  legacy('legacy'),

  /// Inventariados los stores legacy + estado de `zone_identity`.
  discovered('discovered'),

  /// Checks fail-closed aprobados (formato, unicidad, par X25519).
  validated('validated'),

  /// Account + device_1 materializados en `zone_identity`; X25519 legacy
  /// importada como device encryption de device_1 (ADR-0001).
  bridged('bridged'),

  /// device_1 activo por confirmación I-030; single-writer preparado.
  authorized('authorized'),

  /// Escritores migrados; operación normal sobre identidad nueva.
  migrated('migrated'),

  /// Post-checks aprobados (E2EE legacy, fingerprints, sin huérfanos).
  verified('verified'),

  /// Terminal feliz: legacy archivado/eliminado; migración irrevocable.
  finalized('finalized'),

  /// Terminal de fallo con retorno a LEGACY (rollback) como única salida.
  migrationFailed('migration_failed');

  const MigrationState(this.statusId);

  final String statusId;

  /// Fail-closed: estado desconocido ⇒ [MigrationRecordCorruptError], nunca se
  /// inventa un estado.
  static MigrationState fromStatusId(String id) {
    for (final s in MigrationState.values) {
      if (s.statusId == id) return s;
    }
    throw MigrationRecordCorruptError('unknown migration state `$id`');
  }
}

/// Eventos que provocan transiciones (nomenclatura PHASE 2.1.1 §4).
enum MigrationEvent {
  /// `LEGACY → DISCOVERED`: arranque del bridge; detectar stores legacy.
  migrationStarted,

  /// `DISCOVERED → VALIDATED`: validación fail-closed OK.
  validationSucceeded,

  /// `DISCOVERED → MIGRATION_FAILED`: validación falla.
  validationFailed,

  /// `VALIDATED → BRIDGED`: account + device_1 materializados (identidad +
  /// X25519 legacy importada, ADR-0001).
  bridgeCompleted,

  /// `VALIDATED → MIGRATION_FAILED`: materialización inconsistente.
  bridgeFailed,

  /// `BRIDGED → AUTHORIZED`: `confirm_bootstrap` firmado (I-030).
  bootstrapConfirmed,

  /// `BRIDGED → MIGRATION_FAILED`: confirmación falla / lock / kill.
  bootstrapFailed,

  /// `AUTHORIZED → MIGRATED`: single-writer activado; consumidores nuevos leen
  /// `zone_identity`.
  singleWriterActivated,

  /// `MIGRATED → VERIFIED`: post-checks OK (fingerprints, E2EE legacy, sin
  /// huérfanos).
  verificationSucceeded,

  /// `MIGRATED → MIGRATION_FAILED`: verificación falla.
  verificationFailed,

  /// `VERIFIED → FINALIZED`: archivado/limpieza legacy; marca terminal.
  finalized,

  /// `MIGRATION_FAILED → LEGACY`: rollback confirmado (única salida atrás).
  rollbackConfirmed,
}

/// Resultado de evaluar un evento contra un estado.
enum MigrationTransitionResult {
  /// Transición válida a otro estado materializado (ver [MigrationStateMachine.nextState]).
  transitioned,

  /// Transición prohibida (fail-closed).
  invalid,
}

/// Máquina de estados determinista de la migración.
///
/// Todas las combinaciones válidas se modelan explícitamente; el resto devuelve
/// [MigrationTransitionResult.invalid] o lanza [InvalidMigrationStateTransitionError]
/// con la API estricta. La máquina es pura: nunca persiste, nunca ejecuta efectos.
class MigrationStateMachine {
  const MigrationStateMachine._();

  /// Estados terminales (sin salida): `FINALIZED` y `MIGRATION_FAILED`.
  static const Set<MigrationState> terminalStates = {
    MigrationState.finalized,
    MigrationState.migrationFailed,
  };

  /// Eventos que conducen a `MIGRATION_FAILED` (usados por el controlador para
  /// contabilizar intentos y conservar la causa tipada).
  static const Set<MigrationEvent> failureEvents = {
    MigrationEvent.validationFailed,
    MigrationEvent.bridgeFailed,
    MigrationEvent.bootstrapFailed,
    MigrationEvent.verificationFailed,
  };

  /// Evaluación pura: ¿la transición `current --event-->` es válida?
  static MigrationTransitionResult evaluate(
    MigrationState current,
    MigrationEvent event,
  ) {
    switch (current) {
      case MigrationState.legacy:
        return event == MigrationEvent.migrationStarted
            ? MigrationTransitionResult.transitioned
            : MigrationTransitionResult.invalid;
      case MigrationState.discovered:
        switch (event) {
          case MigrationEvent.validationSucceeded:
          case MigrationEvent.validationFailed:
            return MigrationTransitionResult.transitioned;
          default:
            return MigrationTransitionResult.invalid;
        }
      case MigrationState.validated:
        switch (event) {
          case MigrationEvent.bridgeCompleted:
          case MigrationEvent.bridgeFailed:
            return MigrationTransitionResult.transitioned;
          default:
            return MigrationTransitionResult.invalid;
        }
      case MigrationState.bridged:
        switch (event) {
          case MigrationEvent.bootstrapConfirmed:
          case MigrationEvent.bootstrapFailed:
            return MigrationTransitionResult.transitioned;
          default:
            return MigrationTransitionResult.invalid;
        }
      case MigrationState.authorized:
        return event == MigrationEvent.singleWriterActivated
            ? MigrationTransitionResult.transitioned
            : MigrationTransitionResult.invalid;
      case MigrationState.migrated:
        switch (event) {
          case MigrationEvent.verificationSucceeded:
          case MigrationEvent.verificationFailed:
            return MigrationTransitionResult.transitioned;
          default:
            return MigrationTransitionResult.invalid;
        }
      case MigrationState.verified:
        return event == MigrationEvent.finalized
            ? MigrationTransitionResult.transitioned
            : MigrationTransitionResult.invalid;
      case MigrationState.finalized:
        // Terminal: sin salida (ni siquiera rollback).
        return MigrationTransitionResult.invalid;
      case MigrationState.migrationFailed:
        return event == MigrationEvent.rollbackConfirmed
            ? MigrationTransitionResult.transitioned
            : MigrationTransitionResult.invalid;
    }
  }

  /// Estado destino si [evaluate] devuelve [MigrationTransitionResult.transitioned].
  /// Si la transición es inválida lanza [InvalidMigrationStateTransitionError]
  /// (API estricta fail-closed, mismo criterio que `DeviceLifecycle.nextStatus`).
  static MigrationState nextState(
    MigrationState current,
    MigrationEvent event,
  ) {
    if (evaluate(current, event) == MigrationTransitionResult.invalid) {
      throw InvalidMigrationStateTransitionError(
        current.statusId,
        event.name,
      );
    }
    switch (event) {
      case MigrationEvent.migrationStarted:
        return MigrationState.discovered;
      case MigrationEvent.validationSucceeded:
        return MigrationState.validated;
      case MigrationEvent.validationFailed:
      case MigrationEvent.bridgeFailed:
      case MigrationEvent.bootstrapFailed:
      case MigrationEvent.verificationFailed:
        return MigrationState.migrationFailed;
      case MigrationEvent.bridgeCompleted:
        return MigrationState.bridged;
      case MigrationEvent.bootstrapConfirmed:
        return MigrationState.authorized;
      case MigrationEvent.singleWriterActivated:
        return MigrationState.migrated;
      case MigrationEvent.verificationSucceeded:
        return MigrationState.verified;
      case MigrationEvent.finalized:
        return MigrationState.finalized;
      case MigrationEvent.rollbackConfirmed:
        return MigrationState.legacy;
    }
  }
}