/// FASE 2.1 — Servicio de identidad de firma Ed25519 (cuenta y dispositivo).
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Rol aprobado (D1/D2, §4.1/§4.2): Ed25519 es la **identidad de firma**
/// (account identity y device identity). Este servicio NUNCA produce material
/// de cifrado; su única API sobre la clave privada es `sign`.
///
/// Prohibiciones reforzadas por diseño:
/// - No existe "firma X25519" (I-002): este servicio SOLO acepta seeds
///   Ed25519 (32 bytes).
/// - Ningún método devuelve la seed ni la expone en logs/errores (I-004).
/// - La seed se reconstruye con `newKeyPairFromSeed` (formato canónico
///   32 bytes de `cryptography`): mismo seed ⇒ misma clave pública
///   (test determinismo #4).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'identity_errors.dart';
import 'keys.dart';

/// Servicio de firma Ed25519, sin estado global (las seeds se pasan por
/// parámetro; el material nunca se mantiene en singletons).
class Ed25519IdentityService {
  const Ed25519IdentityService();

  static final Ed25519 _ed25519 = Ed25519();

  /// Reconstruye un keypair Ed25519 desde una seed de 32 bytes (fail-closed
  /// ante longitudes inválidas).
  static Future<SimpleKeyPair> keyPairFromSeed(List<int> seed) async {
    if (seed.length != kIdentitySeedLength) {
      throw InvalidSeedLengthError(seed.length);
    }
    return _ed25519.newKeyPairFromSeed(seed);
  }

  /// Bytes crudos (32) de la clave pública.
  static Future<List<int>> publicKeyBytes(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return Uint8List.fromList(publicKey.bytes);
  }

  /// Clave pública en Standard Base64 con padding (44 chars).
  static Future<String> publicKeyBase64(SimpleKeyPair keyPair) async {
    final bytes = await publicKeyBytes(keyPair);
    return base64Encode(bytes);
  }

  /// Firma un mensaje arbitrario (bytes) con Ed25519 → firma de 64 bytes
  /// (R ‖ S). Única operación permitida sobre la clave privada.
  static Future<List<int>> sign(
    SimpleKeyPair keyPair,
    List<int> message,
  ) async {
    final signature = await _ed25519.sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// Verifica una firma Ed25519 de 64 bytes contra una clave pública de
  /// 32 bytes. No lanza: devuelve false ante cualquier input inválido.
  static Future<bool> verify({
    required List<int> publicKeyBytes,
    required List<int> message,
    required List<int> signatureBytes,
  }) async {
    if (publicKeyBytes.length != kIdentityPublicKeyLength ||
        signatureBytes.length != kEd25519SignatureLength) {
      return false;
    }
    try {
      return await _ed25519.verify(
        message,
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        ),
      );
    } on ArgumentError {
      return false;
    }
  }
}
