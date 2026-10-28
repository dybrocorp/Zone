/// FASE 2.1 — Servicio de identidad de cifrado X25519 del dispositivo.
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Rol aprobado (D2, §4.2): X25519 es la **device encryption identity** —
/// ECDH para futuras sesiones E2EE. Regla inviolable: **X25519 jamás firma**
/// (I-002). Este servicio NO expone ninguna operación de firma; su única
/// operación sobre material privado es `sharedSecret` (ECDH).
///
/// Separación de roles (§4.3): el material privado Ed25519 nunca entra aquí y
/// el material X25519 nunca entra en `Ed25519IdentityService`. La clave
/// pública se serializa en Standard Base64 con padding (44 chars).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'identity_errors.dart';
import 'keys.dart';

/// Servicio X25519 de cifrado de dispositivo, sin estado global.
class X25519DeviceEncryptionService {
  const X25519DeviceEncryptionService();

  static final X25519 _x25519 = X25519();

  /// Reconstruye un keypair X25519 desde una seed de 32 bytes (fail-closed
  /// ante longitudes inválidas).
  static Future<SimpleKeyPair> keyPairFromSeed(List<int> seed) async {
    if (seed.length != kIdentitySeedLength) {
      throw InvalidSeedLengthError(seed.length);
    }
    return _x25519.newKeyPairFromSeed(seed);
  }

  /// Bytes crudos (32) de la clave pública X25519.
  static Future<List<int>> publicKeyBytes(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return Uint8List.fromList(publicKey.bytes);
  }

  /// Clave pública X25519 en Standard Base64 con padding (44 chars).
  static Future<String> publicKeyBase64(SimpleKeyPair keyPair) async {
    final bytes = await publicKeyBytes(keyPair);
    return base64Encode(bytes);
  }

  /// ECDH: secreto compartido entre la clave privada local X25519 y una clave
  /// pública X25519 remota. Única operación que toca material privado.
  ///
  /// Lanza error tipado si la clave pública remota no es X25519 (evita el uso
  /// accidental de una identidad Ed25519 como clave de cifrado — §4.3).
  static Future<SecretKey> sharedSecret({
    required SimpleKeyPair localKeyPair,
    required SimplePublicKey remotePublicKey,
  }) async {
    if (remotePublicKey.type != KeyPairType.x25519 ||
        remotePublicKey.bytes.length != kIdentityPublicKeyLength) {
      throw KeyPurposeMismatchError(
        KeyPurpose.deviceEncryption.purposeId,
        'remote public key type ${remotePublicKey.type.name} '
        '(${remotePublicKey.bytes.length} bytes)',
      );
    }
    try {
      return await _x25519.sharedSecretKey(
        keyPair: localKeyPair,
        remotePublicKey: remotePublicKey,
      );
    } on ArgumentError {
      throw KeyPurposeMismatchError(
        KeyPurpose.deviceEncryption.purposeId,
        'invalid X25519 ECDH input',
      );
    }
  }

  /// Construye una [SimplePublicKey] X25519 desde bytes crudos (44 b64/32 raw).
  static SimplePublicKey publicKeyFromBytes(List<int> rawBytes) {
    if (rawBytes.length != kIdentityPublicKeyLength) {
      throw InvalidIdentityMetadataError(
        'X25519 public key must be $kIdentityPublicKeyLength raw bytes',
      );
    }
    return SimplePublicKey(rawBytes, type: KeyPairType.x25519);
  }

  /// Idem desde Standard Base64 con padding.
  static SimplePublicKey publicKeyFromBase64(String base64) {
    List<int> bytes;
    try {
      bytes = base64Decode(base64.trim());
    } on FormatException {
      throw InvalidIdentityMetadataError('invalid base64 public key');
    }
    return publicKeyFromBytes(bytes);
  }
}
