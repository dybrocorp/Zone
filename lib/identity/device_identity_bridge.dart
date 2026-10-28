/// Z-213 PHASE F/G — Puente de identidad de dispositivo (runtime).
///
/// Estado: DISEÑADO + IMPLEMENTADO (unidades PROBADAS LOCALMENTE).
///
/// Único puente entre el RUNTIME de la app y la fundación de identidad
/// (FASE 2.1). Responsabilidades EXACTAS (una sola escritura por material):
///
/// 1. `deviceId` UUIDv4 estable: se genera UNA VEZ y se persiste en el
///    almacén seguro (`zid1.device.id`). Un deviceId corrupto es error
///    tipado (NUNCA regeneración silenciosa — fail-closed).
/// 2. Semillas separadas Ed25519 (firma de dispositivo, D1) y X25519
///    (cifrado de dispositivo, D2) para el MISMO deviceId — refs
///    `SecretKeyRef(scope:'device', purpose:..., deviceId:)` distintos y
///    escritos por UNE única instancia del puente (escritor único).
/// 3. **Single-flight**: N llamadas concurrentes a [ensureInitialized]
///    comparten el MISMO Future; tras completar, llamadas posteriores
///    RE-CARGAN de almacenamiento (deterministas) y jamás regeneran.
/// 4. [DeviceIdentitySnapshot] expone SOLO pares de claves en memoria y
///    públicas serializadas; el material privado no viaja por otros
///    métodos de esta clase.
///
/// Regla de frontera: SIN Supabase, SIN Isar, SIN UI. El puente solo habla
/// con [KeyValueBackend]/[SecureKeyStore] y los servicios de firma/cifrado
/// (separación §9 de la fundación).
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'canonical.dart';
import 'ed25519_identity_service.dart';
import 'fingerprint_service.dart';
import 'identity_errors.dart';
import 'keys.dart';
import 'secure_key_store.dart';
import 'x25519_device_service.dart';

/// Error tipado del puente (fail-closed; mensaje UI-safe sin material).
class DeviceIdentityBridgeError implements Exception {
  const DeviceIdentityBridgeError(this.reason, this.detail);

  final String reason;
  final String detail;

  @override
  String toString() => 'DeviceIdentityBridgeError($reason: $detail)';
}

/// Instantánea de identidad de dispositivo (solo en memoria).
class DeviceIdentitySnapshot {
  const DeviceIdentitySnapshot({
    required this.deviceId,
    required this.ed25519KeyPair,
    required this.x25519KeyPair,
    required this.ed25519PublicKeyBase64,
    required this.x25519PublicKeyBase64,
  });

  /// UUIDv4 estable (persistido; jamás se deriva de datos de UI).
  final String deviceId;

  /// Firma Ed25519 del dispositivo (D1). JAMÁS sirve de identidad ECDH.
  final SimpleKeyPair ed25519KeyPair;

  /// Cifrado X25519 del dispositivo (D2). JAMÁS firma.
  final SimpleKeyPair x25519KeyPair;

  /// Públicas en base64 estándar con padding (44 chars para 32 bytes).
  final String ed25519PublicKeyBase64;
  final String x25519PublicKeyBase64;
}

/// Puente runtime de identidad de dispositivo (escritor único, single-flight).
class DeviceIdentityBridge {
  DeviceIdentityBridge({KeyValueBackend? backend})
      : _backend = backend ?? FlutterSecureStorageBackend() {
    _store = VersionedSecureKeyStore(_backend);
  }

  final KeyValueBackend _backend;
  late final SecureKeyStore _store;

  /// Guard de escritura única (future compartido entre llamadas concurrentes).
  Future<DeviceIdentitySnapshot>? _inFlight;
  bool _loadedAtLeastOnce = false;

  /// Clave física del deviceId (fuera del namespace de semillas).
  static const String _kDeviceIdKey = '$kSecureKeyNamespacePrefix.device.id';

  /// Inicia o RE-CARGA la identidad del dispositivo. Idempotente y
  /// single-flight: los concurrentes comparten la misma inicialización.
  Future<DeviceIdentitySnapshot> ensureInitialized() {
    if (_loadedAtLeastOnce && _inFlight == null) {
      // Re-carga determinista desde almacenamiento (sin generación).
      _inFlight = _loadOrCreate();
    }
    return _inFlight ??= _loadOrCreate();
  }

  Future<DeviceIdentitySnapshot> _loadOrCreate() async {
    try {
      // 1. deviceId persistido (fail-closed ante corrupto).
      final deviceIdValue = await _backend.read(_kDeviceIdKey);
      String deviceId;
      if (deviceIdValue == null) {
        deviceId = _generateUuidV4();
        await _backend.write(_kDeviceIdKey, deviceId);
      } else {
        try {
          deviceId = CanonicalCodec.uuidCanonical(deviceIdValue);
        } on InvalidIdentityMetadataError {
          throw const DeviceIdentityBridgeError(
            'corrupt_device_id',
            'deviceId almacenado no es UUID canónico',
          );
        }
      }

      // 2. Semillas separadas por propósito (refs distintas, mismo deviceId).
      final edRef = SecretKeyRef(
        scope: 'device',
        purpose: KeyPurpose.deviceIdentitySigning,
        deviceId: deviceId,
      );
      final xRef = SecretKeyRef(
        scope: 'device',
        purpose: KeyPurpose.deviceEncryption,
        deviceId: deviceId,
      );

      final edSeed = await _loadOrCreateSeed(edRef);
      final xSeed = await _loadOrCreateSeed(xRef);

      final edKp = await Ed25519IdentityService.keyPairFromSeed(edSeed);
      final xKp = await X25519DeviceEncryptionService.keyPairFromSeed(xSeed);

      final edPk = await Ed25519IdentityService.publicKeyBase64(edKp);
      final xPk = await X25519DeviceEncryptionService.publicKeyBase64(xKp);

      return DeviceIdentitySnapshot(
        deviceId: deviceId,
        ed25519KeyPair: edKp,
        x25519KeyPair: xKp,
        ed25519PublicKeyBase64: edPk,
        x25519PublicKeyBase64: xPk,
      );
    } finally {
      _loadedAtLeastOnce = true;
      _inFlight = null;
    }
  }

  /// Lee la semilla del ref; si NO existe, la GENERA + persiste UNA vez.
  /// Semilla corrupta/versión errónea ⇒ error tipado del store (jamás
  /// regeneración silenciosa — la identidad se corrompe NOTIFICANDO).
  Future<List<int>> _loadOrCreateSeed(SecretKeyRef ref) async {
    final exists = await _store.hasSecret(ref);
    if (exists) {
      return _store.readSecret(ref);
    }
    final seed = Uint8List.fromList(_generateSeed());
    await _store.writeSecret(ref, seed);
    return seed;
  }

  /// Genera 32 bytes criptográficos (Random.secure — SOLO para creación
  /// inicial; nunca para re-crear una identidad existente).
  List<int> _generateSeed() {
    final rnd = Random.secure();
    return List<int>.generate(kIdentitySeedLength, (_) => rnd.nextInt(256));
  }

  /// DEVICE_FINGERPRINT texto canónico (20 chars Base32 unambiguous) para
  /// anclas OOB. Necesita `accountId` de la capa llamadora (UUID de cuenta).
  static Future<String> deviceFingerprintText({
    required String accountId,
    required DeviceIdentitySnapshot identity,
  }) async {
    return FingerprintService.deviceFingerprintText(
      accountId: accountId,
      deviceId: identity.deviceId,
      devicePublicKeyBytes: await _xPublicKeyBytesAsync(identity),
    );
  }

  static Future<Uint8List> _xPublicKeyBytesAsync(
    DeviceIdentitySnapshot identity,
  ) async {
    final publicKey = await identity.x25519KeyPair.extractPublicKey();
    return Uint8List.fromList(publicKey.bytes);
  }

  /// UUIDv4 canónico (bits de versión/variante RFC 4122 correctos).
  String _generateUuidV4() {
    final rnd = Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0F) | 0x40; // version 4
    b[8] = (b[8] & 0x3F) | 0x80; // variant 10
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  /// Borrado COMPLETO de la identidad del dispositivo (wipe explícito —
  /// SOLO por deleteAccount/pipeline de reinicialización aprobado; NO por
  /// recuperación de errores transitorios).
  Future<void> wipeIdentity() async {
    await _backend.delete(_kDeviceIdKey);
    await _store.deleteByPrefix('$kSecureKeyNamespacePrefix.device.');
    // (Las refs de semilla contienen deviceId — el prefijo las barre todas.)
  }
}
