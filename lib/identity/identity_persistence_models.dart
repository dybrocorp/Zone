/// FASE 2.1 — Modelos Isar de metadatos públicos de identidad/dispositivo.
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Misma arquitectura de persistencia que el resto de la app (Isar 3), en una
/// instancia de datos independiente (`zone_identity`) para NO interferir con
/// la base de mensajes/perfiles legacy (mandato §12: no destruir datos
/// existentes; la base de mensajes queda intacta).
///
/// REGLA I-004: estos modelos contienen SOLO metadatos y claves PÚBLICAS.
/// Las seeds viven únicamente en el almacén seguro (`SecureKeyStore`).
library;

import 'package:isar/isar.dart';

part 'identity_persistence_models.g.dart';

/// Registro persistente de la identidad de cuenta (metadatos públicos).
@collection
class AccountIdentityDbo {
  Id isarId = Isar.autoIncrement;

  /// account_id inmutable (UUID v4 canónico, lowercase) — I-015.
  @Index(unique: true, replace: true)
  late String accountId;

  /// ZONE-XXXXXXXX conservado como handle público (compatibilidad legacy).
  /// Indexado NO único (varias cuentas locales pueden carecer de zone_id).
  @Index()
  String? zoneId;

  /// identity_public_key Ed25519 (44 chars b64) — D1.
  late String identityPublicKeyBase64;

  /// identity_key_algorithm ('Ed25519').
  late String identityAlgorithm;

  /// identity_version (1).
  late int identityVersion;

  /// identity_status ('active').
  late String identityStatus;

  late DateTime createdAt;
  late DateTime updatedAt;
}

/// Registro persistente de un dispositivo (metadatos públicos).
@collection
class DeviceDbo {
  Id isarId = Isar.autoIncrement;

  /// device_id (UUID v4 canónico, lowercase).
  @Index(unique: true, replace: true)
  late String deviceId;

  /// Cuenta propietaria.
  @Index()
  late String accountId;

  /// device_public_key Ed25519 (44 chars b64) — identidad de firma.
  late String devicePublicKeyBase64;

  /// device_encryption_public_key X25519 (44 chars b64) — identidad de
  /// cifrado, versionada (D7).
  late String deviceEncryptionPublicKeyBase64;

  /// encryption_key_version (monótono por dispositivo).
  late int encryptionKeyVersion;

  /// status ('pending' | 'active' | 'revoked' | 'compromised' | 'locked' |
  /// 'killed') — I-030.
  late String status;

  late DateTime createdAt;
  late DateTime updatedAt;

  /// Placeholder de revocación (I-030 / DEVICE_MODEL §1.2).
  DateTime? revokedAt;

  /// Placeholder de motivo de revocación.
  String? revocationReason;
}
