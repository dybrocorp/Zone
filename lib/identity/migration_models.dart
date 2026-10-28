/// PHASE 2.2.1 — Modelos de la migración de identidad (persistencia + dominio).
///
/// NEW FOUNDATION EXTENSION — NOT YET INTEGRATED IN THE APP FLOW.
///
/// REGLA I-004: estos modelos contienen SOLO metadatos públicos de la
/// migración (estado, bind de identificadores, fingerprints, checksums,
/// causas tipadas y auditoría). NINGÚN material privado (seeds, claves,
/// envelopes `zid1.`/`zidk1:`, tokens) vive aquí ni en el registro persistido.
///
/// La colección vive en la instancia `zone_identity` (misma que la fundación),
/// separada de la base de mensajes legacy. El registro es SINGLETON por
/// instalación (`kMigrationSingletonId`) con índice único + `putBy*` idempotente.
library;

import 'package:isar/isar.dart';

import 'migration_state_machine.dart';

part 'migration_models.g.dart';

/// Registro persistente de la migración (metadatos públicos).
@collection
class MigrationDbo {
  Id isarId = Isar.autoIncrement;

  /// Identificador singleton de la migración por instalación
  /// (`kMigrationSingletonId`). Índice único → un solo registro; `putBy*`
  /// idempotente (reintentos no duplican).
  @Index(unique: true, replace: true)
  late String migrationId;

  /// Estado actual de la máquina (statusId canónico, SYNTAX: `MigrationState.statusId`).
  late String state;

  late DateTime createdAt;
  late DateTime updatedAt;

  /// Último evento aplicado (nombre del enum; auditoría, nunca secreto).
  String? lastEvent;

  /// Contador de intentos fallidos (events de la rama de fallo).
  int? attemptCount;

  /// Contador de rollbacks confirmados.
  int? rollbackCount;

  /// `zone_id` legacy detectado (handle público de compatibilidad).
  String? legacyZoneId;

  /// `account_id` ligado en `BRIDGED` (identificador, no secreto).
  String? boundAccountId;

  /// `device_id` de device_1 ligado en `BRIDGED` (identificador, no secreto).
  String? boundDeviceId;

  /// Fingerprint ACC (texto público de 20 chars) tras materializar la cuenta.
  String? fingerprintAcc;

  /// Fingerprint DEV (texto público de 20 chars) tras materializar device_1.
  String? fingerprintDev;

  /// Checksum de verificación (huella de los metadatos públicos verificados en
  /// `VERIFIED`). Nunca cubre material privado.
  String? verificationChecksum;

  /// Última causa tipada de fallo (p.ej. `validation_failed`). Nunca expone
  /// material secreto.
  String? failedCause;

  /// Auditoría cronológica, una línea por evento:
  /// `isoTimestamp|estado_origen|evento|causa(opcional)`, separadas por '\n'.
  /// Los ids de estado/evento y los ISO timestamps no contienen '\n'.
  String? auditTrail;
}

/// Modelo de dominio de la migración (inmutable, sin material privado).
class MigrationRecord {
  const MigrationRecord({
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.lastEvent,
    this.attemptCount = 0,
    this.rollbackCount = 0,
    this.legacyZoneId,
    this.boundAccountId,
    this.boundDeviceId,
    this.fingerprintAcc,
    this.fingerprintDev,
    this.verificationChecksum,
    this.failedCause,
    this.audit = const [],
  });

  /// Registro inicial: `LEGACY`, sin historial. Usado cuando no existe registro
  /// persistido (ausencia ⇒ nada migrado todavía).
  factory MigrationRecord.initial() {
    final now = DateTime.now().toUtc();
    return MigrationRecord(
      state: MigrationState.legacy,
      createdAt: now,
      updatedAt: now,
    );
  }

  final MigrationState state;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MigrationEvent? lastEvent;
  final int attemptCount;
  final int rollbackCount;

  /// `zone_id` legacy detectado (handle público).
  final String? legacyZoneId;

  /// `account_id` ligado en `BRIDGED`.
  final String? boundAccountId;

  /// `device_id` de device_1 ligado en `BRIDGED`.
  final String? boundDeviceId;

  final String? fingerprintAcc;
  final String? fingerprintDev;
  final String? verificationChecksum;

  /// Última causa tipada de fallo.
  final String? failedCause;

  /// Auditoría cronológica (más antigua primero).
  final List<String> audit;

  bool get isTerminal =>
      MigrationStateMachine.terminalStates.contains(state);

  MigrationRecord copyWith({
    MigrationState? state,
    DateTime? updatedAt,
    MigrationEvent? lastEvent,
    int? attemptCount,
    int? rollbackCount,
    String? legacyZoneId,
    String? boundAccountId,
    String? boundDeviceId,
    String? fingerprintAcc,
    String? fingerprintDev,
    String? verificationChecksum,
    String? failedCause,
    List<String>? audit,
  }) {
    return MigrationRecord(
      state: state ?? this.state,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastEvent: lastEvent ?? this.lastEvent,
      attemptCount: attemptCount ?? this.attemptCount,
      rollbackCount: rollbackCount ?? this.rollbackCount,
      legacyZoneId: legacyZoneId ?? this.legacyZoneId,
      boundAccountId: boundAccountId ?? this.boundAccountId,
      boundDeviceId: boundDeviceId ?? this.boundDeviceId,
      fingerprintAcc: fingerprintAcc ?? this.fingerprintAcc,
      fingerprintDev: fingerprintDev ?? this.fingerprintDev,
      verificationChecksum:
          verificationChecksum ?? this.verificationChecksum,
      failedCause: failedCause ?? this.failedCause,
      audit: audit ?? this.audit,
    );
  }

  /// Serialización pública segura — NUNCA incluye material privado (I-004).
  Map<String, Object?> toJson() => {
    'migration_state': state.statusId,
    'last_event': lastEvent?.name,
    'attempt_count': attemptCount,
    'rollback_count': rollbackCount,
    'legacy_zone_id': legacyZoneId,
    'bound_account_id': boundAccountId,
    'bound_device_id': boundDeviceId,
    'fingerprint_acc': fingerprintAcc,
    'fingerprint_dev': fingerprintDev,
    'verification_checksum': verificationChecksum,
    'failed_cause': failedCause,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// Salida de depuración sin material secreto (D same criterio mandato §16).
  @override
  String toString() =>
      'MigrationRecord(state: ${state.statusId}, attemptCount: $attemptCount, '
      'rollbackCount: $rollbackCount, boundAccountId: $boundAccountId, '
      'boundDeviceId: $boundDeviceId)';
}