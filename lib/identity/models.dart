/// FASE 2.1 — Modelos de datos de identidad/dispositivo.
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Definiciones PÚBLICAS (sin material privado). Los campos siguen la
/// terminología aprobada en FASE 2.0:
/// - `account_id`, `identity_public_key`, `identity_key_algorithm`,
///   `identity_version`, `identity_status` (mandato FASE 2.1 §5;
///   `PHASE_2_IDENTITY_ARCHITECTURE.md` §3, `PHASE_2_DEVICE_MODEL.md` §1.1)
/// - `device_id`, `device_public_key`, `encryption_public_key`, `status`,
///   `key_version`, timestamps y placeholders de revocación
///   (`PHASE_2_DEVICE_MODEL.md` §1.2/§1.3)
///
/// Regla de seguridad (invariante I-004): NINGÚN modelo de esta fundación
/// contiene material privado. Las seeds viven exclusivamente en `SecureKeyStore`.
library;

import 'keys.dart';

/// Identidad de cuenta (metadatos públicos + clave pública de firma Ed25519).
class AccountIdentity {
  const AccountIdentity({
    required this.accountId,
    required this.identityPublicKeyBase64,
    required this.identityAlgorithm,
    required this.identityVersion,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.zoneId,
  });

  /// Identificador inmutable de la cuenta (UUID v4 canónico, lowercase).
  final String accountId;

  /// ZONE-XXXXXXXX conservado como handle público (compatibilidad legacy).
  /// Puede ser null durante la creación local antes del registro remoto.
  final String? zoneId;

  /// Clave pública Ed25519 (32 bytes raw) en Standard Base64 con padding.
  final String identityPublicKeyBase64;

  /// Algoritmo de la clave de identidad: siempre `ed25519` (D1).
  final IdentityKeyAlgorithm identityAlgorithm;

  /// Versión de la clave de identidad (v1 en esta fase).
  final int identityVersion;

  /// Estado de la identidad de cuenta (`active` en FASE 2.1).
  final AccountIdentityStatus status;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Serialización pública — NUNCA incluye claves privadas (I-004).
  Map<String, Object?> toJson() => {
    'account_id': accountId,
    'zone_id': zoneId,
    'identity_public_key': identityPublicKeyBase64,
    'identity_key_algorithm': identityAlgorithm.algorithmId,
    'identity_version': identityVersion,
    'identity_status': status.statusId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// Salida de depuración sin material secreto (mandato §16 test #33).
  @override
  String toString() =>
      'AccountIdentity(accountId: $accountId, zoneId: $zoneId, '
      'algorithm: ${identityAlgorithm.algorithmId}, '
      'version: $identityVersion, status: ${status.statusId})';
}

/// Dispositivo registrado (metadatos públicos).
///
/// Modela la distinción aprobada account != device: un dispositivo pertenece a
/// una cuenta (`accountId`), tiene su propia identidad de firma Ed25519
/// (`devicePublicKeyBase64`) y su propia identidad de cifrado X25519
/// (`deviceEncryptionPublicKeyBase64`, versionada) — D4. El primer dispositivo
/// nace `pending` (I-013/I-030) y NUNCA se marca `active` implícitamente.
class DeviceProfile {
  const DeviceProfile({
    required this.deviceId,
    required this.accountId,
    required this.devicePublicKeyBase64,
    required this.deviceEncryptionPublicKeyBase64,
    required this.encryptionKeyVersion,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.revokedAt,
    this.revocationReason,
  });

  /// Identificador del dispositivo (UUID v4 canónico, lowercase).
  final String deviceId;

  /// Cuenta propietaria.
  final String accountId;

  /// Clave pública Ed25519 del dispositivo (identity de firma) — 44 chars b64.
  final String devicePublicKeyBase64;

  /// Clave pública X25519 de cifrado del dispositivo — 44 chars b64.
  final String deviceEncryptionPublicKeyBase64;

  /// Versión de la clave de cifrado (monótona por dispositivo — D7).
  final int encryptionKeyVersion;

  final DeviceStatus status;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Placeholder de revocación (I-030 / DEVICE_MODEL §1.2).
  final DateTime? revokedAt;

  /// Placeholder de motivo de revocación (DEVICE_MODEL §1.5: stolen/lost/...).
  final String? revocationReason;

  DeviceProfile copyWith({
    DeviceStatus? status,
    DateTime? updatedAt,
    int? encryptionKeyVersion,
    DateTime? revokedAt,
    String? revocationReason,
  }) {
    return DeviceProfile(
      deviceId: deviceId,
      accountId: accountId,
      devicePublicKeyBase64: devicePublicKeyBase64,
      deviceEncryptionPublicKeyBase64: deviceEncryptionPublicKeyBase64,
      encryptionKeyVersion: encryptionKeyVersion ?? this.encryptionKeyVersion,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      revokedAt: revokedAt ?? this.revokedAt,
      revocationReason: revocationReason ?? this.revocationReason,
    );
  }

  /// Serialización pública — NUNCA incluye claves privadas (I-004).
  Map<String, Object?> toJson() => {
    'device_id': deviceId,
    'account_id': accountId,
    'device_public_key': devicePublicKeyBase64,
    'device_encryption_public_key': deviceEncryptionPublicKeyBase64,
    'encryption_key_version': encryptionKeyVersion,
    'status': status.statusId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'revoked_at': revokedAt?.toIso8601String(),
    'revocation_reason': revocationReason,
  };

  /// Salida de depuración sin material secreto (mandato §16 test #33).
  @override
  String toString() =>
      'DeviceProfile(deviceId: $deviceId, accountId: $accountId, '
      'status: ${status.statusId}, encryptionKeyVersion: $encryptionKeyVersion)';
}
