/// FASE 2.1 — Registro de identidad (facade de la fundación).
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Punto de entrada único de la fundación: orquesta generación, almacenamiento
/// seguro, persistencia de metadatos, ciclo de vida y fingerprints.
/// Sin singletons: estado inyectado (mandato §18: sin singletons ocultos para
/// estado de seguridad; sin estado criptográfico mutable global).
///
/// Reglas críticas:
/// - NUNCA regenera una identidad si los metadatos y el almacén seguro están
///   en desacuerdo: [InconsistentIdentityStateError] (mandato §15).
/// - Los materiales privados se devuelven SOLO como [AccountKeyMaterial] /
///   [DeviceKeyMaterial] con APIs de propósito estricto (firma vs cifrado).
/// - device_1 nace `pending` (I-013/I-030) — jamás activo implícitamente.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import 'device_lifecycle.dart';
import 'ed25519_identity_service.dart';
import 'fingerprint_service.dart';
import 'identity_errors.dart';
import 'identity_persistence.dart';
import 'keys.dart';
import 'models.dart';
import 'secure_key_store.dart';
import 'x25519_device_service.dart';

typedef IdGenerator = String Function();

/// Material de firma de la cuenta (Ed25519), obtenido del almacén seguro.
/// Solo expone operaciones de firma; nada de cifrado (D1).
class AccountKeyMaterial {
  AccountKeyMaterial._(this.metadata, this._keyPair);

  final AccountIdentity metadata;
  final SimpleKeyPair _keyPair;

  Future<List<int>> publicKeyBytes() =>
      Ed25519IdentityService.publicKeyBytes(_keyPair);

  Future<String> publicKeyBase64() =>
      Ed25519IdentityService.publicKeyBase64(_keyPair);

  /// Firma Ed25519 (64 bytes). Única operación sobre la clave privada.
  Future<List<int>> sign(List<int> message) =>
      Ed25519IdentityService.sign(_keyPair, message);
}

/// Material de un dispositivo: identidad de firma Ed25519 + identidad de
/// cifrado X25519, con APIs de propósito estricto separadas (D2).
class DeviceKeyMaterial {
  DeviceKeyMaterial._(
    this.metadata,
    this._signingKeyPair,
    this._encryptionKeyPair,
  );

  final DeviceProfile metadata;
  final SimpleKeyPair _signingKeyPair;
  final SimpleKeyPair _encryptionKeyPair;

  Future<List<int>> devicePublicKeyBytes() =>
      Ed25519IdentityService.publicKeyBytes(_signingKeyPair);

  Future<String> devicePublicKeyBase64() =>
      Ed25519IdentityService.publicKeyBase64(_signingKeyPair);

  Future<List<int>> encryptionPublicKeyBytes() =>
      X25519DeviceEncryptionService.publicKeyBytes(_encryptionKeyPair);

  Future<String> encryptionPublicKeyBase64() =>
      X25519DeviceEncryptionService.publicKeyBase64(_encryptionKeyPair);

  /// Firma del dispositivo (device Ed25519) — precisión, no protocolo.
  Future<List<int>> sign(List<int> message) =>
      Ed25519IdentityService.sign(_signingKeyPair, message);

  /// ECDH con una clave pública X25519 remota (futuras sesiones E2EE).
  Future<SecretKey> sharedSecretWith(SimplePublicKey remotePublicKey) =>
      X25519DeviceEncryptionService.sharedSecret(
        localKeyPair: _encryptionKeyPair,
        remotePublicKey: remotePublicKey,
      );
}

/// Registro de identidad de FASE 2.1.
class IdentityRegistry {
  IdentityRegistry({
    required this.keyStore,
    required this.repository,
    IdGenerator? generateId,
  }) : _generateId = generateId ?? (() => const Uuid().v4());

  final SecureKeyStore keyStore;
  final IdentityRepository repository;
  final IdGenerator _generateId;

  static SecretKeyRef _accountRef() => SecretKeyRef(
    scope: 'account',
    purpose: KeyPurpose.accountIdentitySigning,
  );

  static SecretKeyRef _deviceSigningRef(String deviceId) => SecretKeyRef(
    scope: 'device',
    purpose: KeyPurpose.deviceIdentitySigning,
    deviceId: deviceId,
  );

  static SecretKeyRef _deviceEncryptionRef(String deviceId) => SecretKeyRef(
    scope: 'device',
    purpose: KeyPurpose.deviceEncryption,
    deviceId: deviceId,
  );

  // ──────────────────────────────────────────────────────
  //  Identidad de cuenta
  // ──────────────────────────────────────────────────────

  /// Crea la identidad de cuenta si NO existe (metadatos + secreto ausentes);
  /// si ambos existen, la carga. Cualquier desajuste (metadatos sin secreto o
  /// secreto sin metadatos) ⇒ [InconsistentIdentityStateError] — nunca se
  /// regenera silenciosamente.
  Future<AccountIdentity> ensureAccountIdentity({String? zoneId}) async {
    final metadata = await repository.loadAccount();
    final hasSeed = await keyStore.hasSecret(_accountRef());

    if (metadata == null && !hasSeed) {
      final accountId = _generateId();
      final seed = secureSeed();
      final keyPair = await Ed25519IdentityService.keyPairFromSeed(seed);
      final publicBase64 = await Ed25519IdentityService.publicKeyBase64(
        keyPair,
      );
      final now = DateTime.now().toUtc();
      final account = AccountIdentity(
        accountId: accountId,
        zoneId: zoneId,
        identityPublicKeyBase64: publicBase64,
        identityAlgorithm: IdentityKeyAlgorithm.ed25519,
        identityVersion: IdentityKeyVersion.v1.value,
        status: AccountIdentityStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      await keyStore.writeSecret(_accountRef(), seed);
      await repository.saveAccount(account);
      return account;
    }

    if (metadata != null && hasSeed) {
      return metadata;
    }

    throw InconsistentIdentityStateError(
      metadata == null
          ? 'account seed present without account metadata'
          : 'account metadata present without account seed',
    );
  }

  /// Devuelve el metadata de la cuenta o null si no existe (solo lectura).
  Future<AccountIdentity?> loadAccountMetadata() => repository.loadAccount();

  /// Carga el material de firma de la cuenta. Fail-closed: si el registro
  /// público no existe, lanza [IdentityNotFoundError]; si la seed falta o está
  /// corrupta, [SecureKeyMissingError]/[SecureKeyCorruptError] (no regenera).
  Future<AccountKeyMaterial> loadAccountKeyMaterial(String accountId) async {
    final metadata = await repository.loadAccount();
    if (metadata == null || metadata.accountId != accountId) {
      throw IdentityNotFoundError('account', accountId);
    }
    final seed = await keyStore.readSecret(_accountRef());
    final keyPair = await Ed25519IdentityService.keyPairFromSeed(seed);
    return AccountKeyMaterial._(metadata, keyPair);
  }

  // ──────────────────────────────────────────────────────
  //  Dispositivos
  // ──────────────────────────────────────────────────────

  /// Registra un dispositivo de la cuenta (primer dispositivo o nuevo), con
  /// identidad de firma Ed25519 + identidad de cifrado X25519 locales. El
  /// dispositivo nace `pending` (I-013/I-030) — el bootstrap/confirmación
  /// formal es de fases posteriores.
  Future<DeviceProfile> registerDevice({required String accountId}) async {
    final account = await repository.loadAccount();
    if (account == null || account.accountId != accountId) {
      throw IdentityNotFoundError('account', accountId);
    }

    final deviceId = _generateId();
    final deviceSigningSeed = secureSeed();
    final deviceEncryptionSeed = secureSeed();

    final signingKeyPair = await Ed25519IdentityService.keyPairFromSeed(
      deviceSigningSeed,
    );
    final encryptionKeyPair =
        await X25519DeviceEncryptionService.keyPairFromSeed(
          deviceEncryptionSeed,
        );

    final devicePublicBase64 = await Ed25519IdentityService.publicKeyBase64(
      signingKeyPair,
    );
    final encryptionPublicBase64 =
        await X25519DeviceEncryptionService.publicKeyBase64(encryptionKeyPair);

    final now = DateTime.now().toUtc();
    final device = DeviceProfile(
      deviceId: deviceId,
      accountId: accountId,
      devicePublicKeyBase64: devicePublicBase64,
      deviceEncryptionPublicKeyBase64: encryptionPublicBase64,
      encryptionKeyVersion: IdentityKeyVersion.v1.value,
      status: DeviceStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    await keyStore.writeSecret(_deviceSigningRef(deviceId), deviceSigningSeed);
    await keyStore.writeSecret(
      _deviceEncryptionRef(deviceId),
      deviceEncryptionSeed,
    );
    await repository.saveDevice(device);
    return device;
  }

  /// Carga el material de un dispositivo (firma + cifrado) + metadata.
  Future<DeviceKeyMaterial> loadDeviceKeyMaterial(String deviceId) async {
    final metadata = await repository.loadDevice(deviceId);
    if (metadata == null) {
      throw IdentityNotFoundError('device', deviceId);
    }
    final signingSeed = await keyStore.readSecret(_deviceSigningRef(deviceId));
    final encryptionSeed = await keyStore.readSecret(
      _deviceEncryptionRef(deviceId),
    );
    final signingKeyPair = await Ed25519IdentityService.keyPairFromSeed(
      signingSeed,
    );
    final encryptionKeyPair =
        await X25519DeviceEncryptionService.keyPairFromSeed(encryptionSeed);
    return DeviceKeyMaterial._(metadata, signingKeyPair, encryptionKeyPair);
  }

  Future<DeviceProfile?> findDevice(String deviceId) =>
      repository.loadDevice(deviceId);

  Future<List<DeviceProfile>> listDevices(String accountId) =>
      repository.loadDevices(accountId);

  /// Aplica un evento de la máquina de estados (I-030). Devuelve null cuando
  /// el evento produce GONE (timeout TTL → GC de artefactos). Lanza
  /// [InvalidDeviceStateTransitionError] ante transiciones prohibidas.
  Future<DeviceProfile?> transitionDevice(
    String deviceId,
    DeviceLifecycleEvent event,
  ) async {
    final device = await repository.loadDevice(deviceId);
    if (device == null) {
      throw IdentityNotFoundError('device', deviceId);
    }
    final next = DeviceLifecycle.nextStatus(device.status, event);
    if (next == null) {
      // GONE: eliminar artefactos (seeds + registro). La cuenta queda intacta.
      await keyStore.deleteSecret(_deviceSigningRef(deviceId));
      await keyStore.deleteSecret(_deviceEncryptionRef(deviceId));
      await repository.deleteDevice(deviceId);
      return null;
    }
    final now = DateTime.now().toUtc();
    final updated = device.copyWith(
      status: next,
      updatedAt: now,
      revokedAt:
          (next == DeviceStatus.revoked || next == DeviceStatus.compromised)
          ? now
          : null,
      revocationReason: next == DeviceStatus.revoked ? 'user_initiated' : null,
    );
    await repository.saveDevice(updated);
    return updated;
  }

  /// Elimina por completo un dispositivo (borrado local explícito).
  Future<void> removeDevice(String deviceId) async {
    await keyStore.deleteSecret(_deviceSigningRef(deviceId));
    await keyStore.deleteSecret(_deviceEncryptionRef(deviceId));
    await repository.deleteDevice(deviceId);
  }

  // ──────────────────────────────────────────────────────
  //  Fingerprints
  // ──────────────────────────────────────────────────────

  /// ACCOUNT_FINGERPRINT (texto de 20 chars) a partir del metadata público.
  Future<String> accountFingerprintText(String accountId) async {
    final account = await repository.loadAccount();
    if (account == null || account.accountId != accountId) {
      throw IdentityNotFoundError('account', accountId);
    }
    return FingerprintService.accountFingerprintText(
      accountId: account.accountId,
      identityPublicKeyBytes: _decodePublicKey(account.identityPublicKeyBase64),
    );
  }

  /// DEVICE_FINGERPRINT (texto de 20 chars) a partir del metadata público.
  Future<String> deviceFingerprintText(String deviceId) async {
    final device = await repository.loadDevice(deviceId);
    if (device == null) {
      throw IdentityNotFoundError('device', deviceId);
    }
    return FingerprintService.deviceFingerprintText(
      accountId: device.accountId,
      deviceId: device.deviceId,
      devicePublicKeyBytes: _decodePublicKey(device.devicePublicKeyBase64),
    );
  }

  static Uint8List _decodePublicKey(String base64) {
    try {
      return Uint8List.fromList(base64Decode(base64.trim()));
    } on FormatException {
      throw InvalidIdentityMetadataError('invalid base64 public key');
    }
  }
}
