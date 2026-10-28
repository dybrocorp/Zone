/// PHASE 2.2/2.1 — Contexto de identidad público del runtime.
///
/// PRODUCT INTEGRATION SLICE (autorizado CTO 2026-09-25).
///
/// Inmutable y SIN material privado (I-004): expone únicamente identificadores
/// públicos y estados necesarios para el diálogo posterior de la fundación
/// (bridge 2.2.2/2.2.3, single-writer 2.2.4, consumidores 2.2.5).
///
/// Reglas:
/// - NUNCA incluye seeds, claves privadas, envelopes, tokens ni material
///   recuperable (toString/toLogMap seguros).
/// - Los campos `accountCreated`/`deviceCreated` distinguen primer arranque
///   (CREATE) de arranques siguientes (LOAD) — requisito de idempotencia.
library;

/// Contexto inmutable de identidad disponible tras el bootstrap productivo.
class IdentityContext {
  const IdentityContext({
    required this.accountId,
    required this.deviceId,
    required this.deviceStatus,
    required this.accountFingerprint,
    required this.deviceFingerprint,
    required this.migrationState,
    required this.accountCreated,
    required this.deviceCreated,
  });

  /// Identificador público de la cuenta (UUID v4 canónico).
  final String accountId;

  /// Identificador público del dispositivo (device_1, UUID v4 canónico).
  final String deviceId;

  /// Estado de ciclo de vida del dispositivo (`pending` tras el bootstrap, I-030).
  final String deviceStatus;

  /// ACCOUNT_FINGERPRINT (texto público normalizado, p.ej. 20 chars).
  final String accountFingerprint;

  /// DEVICE_FINGERPRINT (texto público normalizado).
  final String deviceFingerprint;

  /// Estado canónico de la migración leído SIN ejecutar eventos
  /// (ausencia de registro ⇒ `legacy`).
  final String migrationState;

  /// `true` si este arranque CREÓ la cuenta (primer arranque).
  final bool accountCreated;

  /// `true` si este arranque CREÓ el dispositivo device_1.
  final bool deviceCreated;

  /// Mapa plano para logging seguro — solo identificadores y estados públicos.
  Map<String, String> toLogMap() => {
    'account_id': accountId,
    'device_id': deviceId,
    'device_status': deviceStatus,
    'account_fingerprint': accountFingerprint,
    'device_fingerprint': deviceFingerprint,
    'migration_state': migrationState,
    'account_created': '$accountCreated',
    'device_created': '$deviceCreated',
  };

  @override
  String toString() =>
      'IdentityContext(account_id: $accountId, device_id: $deviceId, '
      'device_status: $deviceStatus, '
      'account_fingerprint: $accountFingerprint, '
      'device_fingerprint: $deviceFingerprint, '
      'migration_state: $migrationState, '
      'account_created: $accountCreated, device_created: $deviceCreated)';
}