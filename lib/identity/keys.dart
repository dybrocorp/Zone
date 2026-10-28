/// FASE 2.1 — Fundación de Identidad/Dispositivo.
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Constantes y enumeraciones canónicas de la fundación. La terminología y los
/// valores siguen EXACTAMENTE los documentos aprobados de FASE 2.0:
/// - `PHASE_2_IDENTITY_ARCHITECTURE.md` (account/device/encryption identity)
/// - `PHASE_2_DEVICE_MODEL.md` (device lifecycle, key versioning)
/// - `PHASE_2_CRYPTO_DECISIONS.md` (D1/D2: Ed25519 firma, X25519 cifra)
/// - `PHASE_2_BOOTSTRAP_POLICY.md` §4 (máquina de estados, I-030)
///
/// Ninguna clave privada vive en este fichero ni en los modelos de metadatos:
/// el material secreto reside únicamente en [SecureKeyStore].
library;

import 'dart:math';

/// Algoritmos de identidad aprobados en FASE 2.0.
enum IdentityKeyAlgorithm {
  /// Identidad/signature de cuenta (D1) y de dispositivo (device Ed25519).
  ed25519,

  /// Identidad de cifrado de dispositivo — ECDH (D2). Jamás firma.
  x25519;

  /// Identificador canónico (se persiste en metadatos, nunca se deriva de UI).
  String get algorithmId {
    switch (this) {
      case IdentityKeyAlgorithm.ed25519:
        return 'Ed25519';
      case IdentityKeyAlgorithm.x25519:
        return 'X25519';
    }
  }

  static IdentityKeyAlgorithm fromAlgorithmId(String id) {
    switch (id) {
      case 'Ed25519':
        return IdentityKeyAlgorithm.ed25519;
      case 'X25519':
        return IdentityKeyAlgorithm.x25519;
      default:
        throw ArgumentError.value(id, 'id', 'Algorithm unknown');
    }
  }
}

/// Versión del formato de clave de identidad (versionado de metadatos clave,
/// prohibido usar constantes mágicas sin versión — mandato FASE 2.1 §18).
enum IdentityKeyVersion {
  v1(1);

  const IdentityKeyVersion(this.value);

  final int value;

  static IdentityKeyVersion fromValue(int value) {
    for (final v in IdentityKeyVersion.values) {
      if (v.value == value) return v;
    }
    throw ArgumentError.value(value, 'value', 'Unsupported identity version');
  }
}

/// Propósito criptográfico estricto de cada material privado (D1/D2, §4.3).
///
/// Garantiza la separación de roles: el material de cifrado X25519 jamás se
/// expone a través de una API de firma y el material de firma Ed25519 jamás se
/// usa como identidad de cifrado. Los tests de separación (§16 #30-#33) anclan
/// este contrato.
enum KeyPurpose {
  /// Clave de firma de cuenta (account identity, Ed25519).
  accountIdentitySigning,

  /// Clave de firma de dispositivo (device identity, Ed25519).
  deviceIdentitySigning,

  /// Clave de cifrado de dispositivo (device encryption, X25519).
  deviceEncryption;

  String get purposeId => name;
}

/// Estado de la identidad de cuenta.
///
/// La arquitectura aprobada no define más estados de cuenta activables en esta
/// fase; el campo existe por mandato (§5: identity_status) y `active` es el
/// único estado alcanzable en FASE 2.1. Siguientes fases podrán extenderlo.
enum AccountIdentityStatus {
  active;

  String get statusId => name;

  static AccountIdentityStatus fromStatusId(String id) {
    for (final s in AccountIdentityStatus.values) {
      if (s.statusId == id) return s;
    }
    throw ArgumentError.value(id, 'id', 'Unknown account identity status');
  }
}

/// Estados de ciclo de vida de un dispositivo — autoridad: BOOTSTRAP_POLICY §4
/// (I-030) y DEVICE_MODEL §1.2.
enum DeviceStatus {
  /// Creado por bootstrap_account; sin derechos hasta confirmación firmada.
  pending,

  /// Confirmado (confirm_bootstrap); puede operar.
  active,

  /// Revocado por revoke_device (firma de cuenta).
  revoked,

  /// Marcado por detección de compromiso.
  compromised,

  /// Bloqueado por superar MAX_ATTEMPTS de confirmación (cool-down).
  locked,

  /// Cancelado (bootstrap_cancel / cold_block).
  killed;

  String get statusId => name;

  static DeviceStatus fromStatusId(String id) {
    for (final s in DeviceStatus.values) {
      if (s.statusId == id) return s;
    }
    throw ArgumentError.value(id, 'id', 'Unknown device status');
  }
}

/// Longitud canónica de una seed (clave privada simétrica/secreta en bruto)
/// para Ed25519 y X25519 en la implementación `cryptography` (RFC 8032 seed
/// = 32 bytes; RFC 7748 private scalar = 32 bytes).
const int kIdentitySeedLength = 32;

/// Longitud en bytes de una clave pública Ed25519/X25519 en bruto.
const int kIdentityPublicKeyLength = 32;

/// Longitud en bytes de una firma Ed25519 (R ‖ S).
const int kEd25519SignatureLength = 64;

/// Prefijo de versión del envelope de almacenamiento seguro.
/// Formato de valor almacenado: `zidk1:<base64-utf8(seed)>`.
const String kSecureKeyEnvelopeV1 = 'zidk1';

/// Prefijo de namespace para TODAS las claves de la fundación en el almacén
/// seguro. Evita colisiones con las claves legacy ya en uso:
/// `private_key`, `public_key`, `zone_id`, `supabase_uid`, `sk_*`, `pseudo_*`.
const String kSecureKeyNamespacePrefix = 'zid1';

/// Nombre de la instancia Isar dedicada a los metadatos de identidad.
/// Aislamiento de la base de mensajes legacy (misma arquitectura Isar,
/// instancia de datos independiente — documentado en el reporte).
const String kIdentityIsarInstanceName = 'zone_identity';

/// Retorna 32 bytes de entropía CSPRNG para seeds de Ed25519/X25519.
List<int> secureSeed() {
  final rng = Random.secure();
  return List<int>.generate(kIdentitySeedLength, (_) => rng.nextInt(256));
}
