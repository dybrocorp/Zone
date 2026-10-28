/// FASE 2.1 — Abstracción de almacenamiento seguro local de material privado.
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Separación de responsabilidades (mandato §9):
/// - generación de claves → servicios Ed25519/X25519
/// - almacenamiento/lectura/borrado → [SecureKeyStore]
/// - metadatos públicos → persistencia Isar ([IdentityRepository])
/// - UI/repos/Supabase/chat/mesh → NO acceden a este módulo
///
/// Reglas:
/// - Nada de claves en SharedPreferences, JSON plano, Isar, logs, `.env`,
///   git o Supabase (mandato §9). Unicamente el almacén seguro con
///   `flutter_secure_storage` (Android: encrypted SharedPreferences/Keystore,
///   el mismo mecanismo ya usado por la aplicación legacy).
/// - Valores versionados con envelope canónico `zidk1:<base64(seed)>`:
///   permite detección de versiones no soportadas (mandato §18: sin metadatos
///   no versionados).
/// - Fail-closed: seed ausente/corrupta/versión errónea ⇒ errores tipados;
///   NUNCA se regenera una identidad silenciosamente.
/// - Claves del almacén bajo el namespace `zid1.` (sin colisión con las
///   claves legacy `private_key`/`public_key`/`zone_id`/`supabase_uid`/
///   `sk_*`/`pseudo_*`).
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'identity_errors.dart';
import 'keys.dart';

/// Referencia lógica a un secreto dentro del almacén seguro.
class SecretKeyRef {
  const SecretKeyRef({
    required this.scope,
    required this.purpose,
    this.deviceId,
  }) : assert(scope == 'account' || scope == 'device'),
       assert(
         scope == 'device' ? deviceId != null : true,
         'deviceId is required for device-scoped secrets',
       );

  /// Ámbito: `account` (identidad de cuenta) o `device` (por dispositivo).
  final String scope;

  /// Propósito criptográfico (separación de roles D1/D2).
  final KeyPurpose purpose;

  /// Identificador del dispositivo para secretos de ámbito `device`.
  final String? deviceId;

  /// Clave física en el almacén bajo el namespace `zid1.`.
  String get storageKey {
    final sb = StringBuffer()
      ..write(kSecureKeyNamespacePrefix)
      ..write('.$scope.')
      ..write(purpose.purposeId);
    if (deviceId != null) {
      sb.write('.$deviceId');
    }
    return sb.toString();
  }

  @override
  String toString() => 'SecretKeyRef($storageKey)';
}

/// Backend de almacenamiento clave-valor (permite inyectar un doble en tests;
/// la implementación de producción usa `flutter_secure_storage`).
abstract class KeyValueBackend {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  /// Devuelve todas las entradas (para limpieza por prefijo).
  Future<Map<String, String>> readAll();
}

/// Backend de producción basado en `flutter_secure_storage` (Android:
/// `encryptedSharedPreferences: true`, igual que el código legacy existente).
class FlutterSecureStorageBackend implements KeyValueBackend {
  FlutterSecureStorageBackend({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}

/// Contrato del almacén seguro de la fundación.
abstract class SecureKeyStore {
  /// Guarda un secreto (seed cruda) versionado bajo envelope `zidk1:`.
  Future<void> writeSecret(SecretKeyRef ref, List<int> secretBytes);

  /// Lee y valida la seed. Lanza errores tipados fail-closed:
  /// [SecureKeyMissingError], [SecureKeyVersionMismatchError],
  /// [SecureKeyCorruptError].
  Future<List<int>> readSecret(SecretKeyRef ref);

  /// True si la entrada existe (y su envelope tiene versión soportada).
  Future<bool> hasSecret(SecretKeyRef ref);

  /// Elimina una entrada.
  Future<void> deleteSecret(SecretKeyRef ref);

  /// Elimina todas las entradas cuyo storageKey empieza por [keyPrefix].
  Future<void> deleteByPrefix(String keyPrefix);
}

/// Implementación versionada sobre un [KeyValueBackend].
class VersionedSecureKeyStore implements SecureKeyStore {
  VersionedSecureKeyStore(this._backend);

  final KeyValueBackend _backend;

  static String _envelope(List<int> secretBytes) =>
      '$kSecureKeyEnvelopeV1:${base64Encode(secretBytes)}';

  static List<int> _unseal(SecretKeyRef ref, String value) {
    const expected = '$kSecureKeyEnvelopeV1:';
    if (!value.startsWith('$kSecureKeyEnvelopeV1:')) {
      final found = value.contains(':') ? value.split(':').first : '(none)';
      throw SecureKeyVersionMismatchError(
        ref.storageKey,
        found,
        kSecureKeyEnvelopeV1,
      );
    }
    final payload = value.substring(expected.length);
    List<int> bytes;
    try {
      bytes = base64Decode(payload);
    } on FormatException {
      throw SecureKeyCorruptError(ref.storageKey, 'invalid base64 payload');
    }
    if (bytes.length != kIdentitySeedLength) {
      throw SecureKeyCorruptError(
        ref.storageKey,
        'decoded payload has ${bytes.length} bytes, '
        'expected $kIdentitySeedLength',
      );
    }
    return bytes;
  }

  @override
  Future<void> writeSecret(SecretKeyRef ref, List<int> secretBytes) async {
    if (secretBytes.length != kIdentitySeedLength) {
      throw InvalidSeedLengthError(secretBytes.length);
    }
    await _backend.write(ref.storageKey, _envelope(secretBytes));
  }

  @override
  Future<List<int>> readSecret(SecretKeyRef ref) async {
    final value = await _backend.read(ref.storageKey);
    if (value == null) {
      throw SecureKeyMissingError(ref.storageKey);
    }
    return _unseal(ref, value);
  }

  @override
  Future<bool> hasSecret(SecretKeyRef ref) async {
    final value = await _backend.read(ref.storageKey);
    return value != null && value.startsWith('$kSecureKeyEnvelopeV1:');
  }

  @override
  Future<void> deleteSecret(SecretKeyRef ref) =>
      _backend.delete(ref.storageKey);

  @override
  Future<void> deleteByPrefix(String keyPrefix) async {
    final all = await _backend.readAll();
    for (final key in all.keys) {
      if (key.startsWith(keyPrefix)) {
        await _backend.delete(key);
      }
    }
  }
}
