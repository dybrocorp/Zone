/// FASE 2.1 — Registro de identidad y ciclo de vida de dispositivo (I-013/I-030).
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Verifica sobre dobles en memoria: creación idempotente de cuenta (nunca se
/// regenera silenciosamente), estados inconsistentes fail-closed, fingerprints
/// estables, registración de dispositivo nacida `pending`, máquina de estados
/// formal (GONE ⇒ GC de artefactos) y borrado explícito.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/device_lifecycle.dart';
import 'package:zone/identity/ed25519_identity_service.dart';
import 'package:zone/identity/fingerprint_service.dart';
import 'package:zone/identity/identity_errors.dart';
import 'package:zone/identity/identity_registry.dart';
import 'package:zone/identity/keys.dart';
import 'package:zone/identity/secure_key_store.dart';
import 'package:zone/identity/x25519_device_service.dart';

import 'test_doubles.dart';

const String _accountId = '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d';
const String _deviceId = '2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7e';
const String _deviceId2 = '3c4d5e6f-7a8b-9c0d-1e2f-3a4b5c6d7e8f';

SecretKeyRef accountRef() => const SecretKeyRef(
  scope: 'account',
  purpose: KeyPurpose.accountIdentitySigning,
);

SecretKeyRef deviceSignRef(String deviceId) => SecretKeyRef(
  scope: 'device',
  purpose: KeyPurpose.deviceIdentitySigning,
  deviceId: deviceId,
);

SecretKeyRef deviceEncRef(String deviceId) => SecretKeyRef(
  scope: 'device',
  purpose: KeyPurpose.deviceEncryption,
  deviceId: deviceId,
);

/// Registro nuevo con IDs deterministas y dobles en memoria (sin plataforma).
IdentityRegistry freshRegistry({required List<String> ids}) {
  final queue = List<String>.of(ids);
  return IdentityRegistry(
    keyStore: VersionedSecureKeyStore(InMemoryKeyValueBackend()),
    repository: InMemoryIdentityRepository(),
    generateId: () => queue.removeAt(0),
  );
}

void main() {
  group('Identidad de cuenta', () {
    test('ensureAccountIdentity crea (id determinista) y es idempotente '
        '(nunca regenera)', () async {
      final registry = freshRegistry(ids: [_accountId, _deviceId, _deviceId2]);
      final account = await registry.ensureAccountIdentity(
        zoneId: 'ZONE-ABCD1234',
      );
      expect(account.accountId, _accountId);
      expect(account.zoneId, 'ZONE-ABCD1234');
      expect(account.status, AccountIdentityStatus.active);
      expect(account.identityVersion, IdentityKeyVersion.v1.value);
      expect(account.identityAlgorithm, IdentityKeyAlgorithm.ed25519);
      expect(account.identityPublicKeyBase64.length, 44);
      // seed + metadatos persistidos.
      final repo = registry.repository as InMemoryIdentityRepository;
      expect(await registry.keyStore.hasSecret(accountRef()), isTrue);
      expect(repo.account, isNotNull);

      // Segunda llamada ⇒ misma entidad, misma clave pública (sin regenerar).
      final again = await registry.ensureAccountIdentity();
      expect(again.accountId, account.accountId);
      expect(again.identityPublicKeyBase64, account.identityPublicKeyBase64);
      final material = await registry.loadAccountKeyMaterial(_accountId);
      expect(await material.publicKeyBase64(), account.identityPublicKeyBase64);
    });

    test('el material de cuenta firma con Ed25519 y verifica', () async {
      final registry = freshRegistry(ids: [_accountId]);
      await registry.ensureAccountIdentity();
      final material = await registry.loadAccountKeyMaterial(_accountId);
      final pubBytes = await material.publicKeyBytes();
      const message = <int>[9, 8, 7];
      final signature = await material.sign(message);
      expect(signature.length, kEd25519SignatureLength);
      expect(
        await Ed25519IdentityService.verify(
          publicKeyBytes: pubBytes,
          message: message,
          signatureBytes: signature,
        ),
        isTrue,
      );
    });

    test('estado inconsistente (metadatos sin seed) ⇒ '
        'InconsistentIdentityStateError — no regenera', () async {
      final registry = freshRegistry(ids: [_accountId]);
      await registry.ensureAccountIdentity();
      // Simula pérdida de la seed en el almacén seguro (sin tocar metadatos).
      await registry.keyStore.deleteSecret(accountRef());
      await expectLater(
        registry.ensureAccountIdentity(),
        throwsA(isA<InconsistentIdentityStateError>()),
      );
    });

    test('estado inconsistente (seed sin metadatos) ⇒ '
        'InconsistentIdentityStateError — no regenera', () async {
      final registry = freshRegistry(ids: [_accountId]);
      await registry.ensureAccountIdentity();
      final repo = registry.repository as InMemoryIdentityRepository;
      await repo.deleteAccount();
      await expectLater(
        registry.ensureAccountIdentity(),
        throwsA(isA<InconsistentIdentityStateError>()),
      );
    });

    test('loadAccountKeyMaterial / accountFingerprintText con cuenta '
        'desconocida ⇒ IdentityNotFoundError', () async {
      final registry = freshRegistry(ids: [_accountId]);
      await registry.ensureAccountIdentity();
      await expectLater(
        registry.loadAccountKeyMaterial('00000000-0000-4000-8000-000000000000'),
        throwsA(isA<IdentityNotFoundError>()),
      );
      await expectLater(
        registry.accountFingerprintText('00000000-0000-4000-8000-000000000000'),
        throwsA(isA<IdentityNotFoundError>()),
      );
    });
  });

  group('Fingerprints desde metadatos públicos', () {
    test(
      'account fingerprint es estable y coincide con FingerprintService',
      () async {
        final registry = freshRegistry(ids: [_accountId]);
        final account = await registry.ensureAccountIdentity();
        final fp1 = await registry.accountFingerprintText(_accountId);
        final fp2 = await registry.accountFingerprintText(_accountId);
        expect(fp1, fp2);
        expect(fp1.length, 20);
        // Coincide con el cálculo directo desde la clave pública persistida.
        final expected = await FingerprintService.accountFingerprintText(
          accountId: account.accountId,
          identityPublicKeyBytes: _decode(account.identityPublicKeyBase64),
        );
        expect(fp1, expected);
      },
    );

    test('device fingerprint es estable y distinto del de cuenta', () async {
      final registry = freshRegistry(ids: [_accountId, _deviceId]);
      await registry.ensureAccountIdentity();
      final device = await registry.registerDevice(accountId: _accountId);
      final dfp1 = await registry.deviceFingerprintText(_deviceId);
      final dfp2 = await registry.deviceFingerprintText(_deviceId);
      expect(dfp1, dfp2);
      expect(dfp1.length, 20);
      final afp = await registry.accountFingerprintText(_accountId);
      expect(dfp1, isNot(afp), reason: 'account != device');
      final expected = await FingerprintService.deviceFingerprintText(
        accountId: _accountId,
        deviceId: device.deviceId,
        devicePublicKeyBytes: _decode(device.devicePublicKeyBase64),
      );
      expect(dfp1, expected);
    });
  });

  group('Dispositivos (I-013: pending, sin derechos)', () {
    test('registerDevice crea device pending con firma Ed25519 + cifrado '
        'X25519 y seeds separadas', () async {
      final registry = freshRegistry(ids: [_accountId, _deviceId]);
      await registry.ensureAccountIdentity();
      final device = await registry.registerDevice(accountId: _accountId);
      expect(device.deviceId, _deviceId);
      expect(device.status, DeviceStatus.pending);
      expect(device.encryptionKeyVersion, IdentityKeyVersion.v1.value);
      expect(
        device.devicePublicKeyBase64,
        isNot(device.deviceEncryptionPublicKeyBase64),
        reason: 'firma y cifrado son dominios distintos',
      );
      expect(
        await registry.keyStore.hasSecret(deviceSignRef(_deviceId)),
        isTrue,
      );
      expect(
        await registry.keyStore.hasSecret(deviceEncRef(_deviceId)),
        isTrue,
      );

      // El material del dispositivo firma con Ed25519 y hace ECDH con X25519.
      final material = await registry.loadDeviceKeyMaterial(_deviceId);
      final signature = await material.sign(<int>[1, 2, 3]);
      expect(signature.length, kEd25519SignatureLength);

      // ECDH propio (mismo par) es válido y determinista.
      final ownPub = X25519DeviceEncryptionService.publicKeyFromBytes(
        await material.encryptionPublicKeyBytes(),
      );
      final shared = await material.sharedSecretWith(ownPub);
      expect((await shared.extractBytes()).length, 32);
    });

    test(
      'registerDevice con cuenta inexistente ⇒ IdentityNotFoundError',
      () async {
        final registry = freshRegistry(ids: [_accountId]);
        await registry.ensureAccountIdentity();
        await expectLater(
          registry.registerDevice(
            accountId: '00000000-0000-4000-8000-000000000000',
          ),
          throwsA(isA<IdentityNotFoundError>()),
        );
      },
    );

    test(
      'carga/transición de device desconocido ⇒ IdentityNotFoundError',
      () async {
        final registry = freshRegistry(ids: [_accountId, _deviceId]);
        await registry.ensureAccountIdentity();
        await registry.registerDevice(accountId: _accountId);
        const unknown = '99999999-9999-4999-8999-999999999999';
        await expectLater(
          registry.loadDeviceKeyMaterial(unknown),
          throwsA(isA<IdentityNotFoundError>()),
        );
        await expectLater(
          registry.transitionDevice(
            unknown,
            DeviceLifecycleEvent.bootstrapConfirmed,
          ),
          throwsA(isA<IdentityNotFoundError>()),
        );
        await expectLater(
          registry.deviceFingerprintText(unknown),
          throwsA(isA<IdentityNotFoundError>()),
        );
      },
    );
  });

  group('Máquina de estados (I-030 / BOOTSTRAP_POLICY §4)', () {
    test('pending → confirm_bootstrap → ACTIVE (sin derechos antes)', () async {
      final registry = freshRegistry(ids: [_accountId, _deviceId]);
      await registry.ensureAccountIdentity();
      await registry.registerDevice(accountId: _accountId);
      final active = await registry.transitionDevice(
        _deviceId,
        DeviceLifecycleEvent.bootstrapConfirmed,
      );
      expect(active!.status, DeviceStatus.active);
      expect(active.revokedAt, isNull);
    });

    test('ACTIVE → revoke_device → REVOKED (revokedAt + motivo)', () async {
      final registry = freshRegistry(ids: [_accountId, _deviceId]);
      await registry.ensureAccountIdentity();
      await registry.registerDevice(accountId: _accountId);
      await registry.transitionDevice(
        _deviceId,
        DeviceLifecycleEvent.bootstrapConfirmed,
      );
      final revoked = await registry.transitionDevice(
        _deviceId,
        DeviceLifecycleEvent.deviceRevoked,
      );
      expect(revoked!.status, DeviceStatus.revoked);
      expect(revoked.revokedAt, isNotNull);
      expect(revoked.revocationReason, 'user_initiated');
    });

    test('ACTIVE → compromiso → COMPROMISED', () async {
      final registry = freshRegistry(ids: [_accountId, _deviceId]);
      await registry.ensureAccountIdentity();
      await registry.registerDevice(accountId: _accountId);
      await registry.transitionDevice(
        _deviceId,
        DeviceLifecycleEvent.bootstrapConfirmed,
      );
      final compromised = await registry.transitionDevice(
        _deviceId,
        DeviceLifecycleEvent.deviceCompromised,
      );
      expect(compromised!.status, DeviceStatus.compromised);
      expect(compromised.revokedAt, isNotNull);
    });

    test('terminales no admiten salida (fail-closed)', () async {
      final registry = freshRegistry(ids: [_accountId, _deviceId]);
      await registry.ensureAccountIdentity();
      await registry.registerDevice(accountId: _accountId);
      await registry.transitionDevice(
        _deviceId,
        DeviceLifecycleEvent.bootstrapConfirmed,
      );
      await registry.transitionDevice(
        _deviceId,
        DeviceLifecycleEvent.deviceRevoked,
      );
      await expectLater(
        registry.transitionDevice(
          _deviceId,
          DeviceLifecycleEvent.deviceCompromised,
        ),
        throwsA(isA<InvalidDeviceStateTransitionError>()),
      );
      await expectLater(
        registry.transitionDevice(
          _deviceId,
          DeviceLifecycleEvent.bootstrapConfirmed,
        ),
        throwsA(isA<InvalidDeviceStateTransitionError>()),
      );
    });

    test(
      'PENDING + revoke/compromiso son prohibidos (PENDING sin derechos)',
      () async {
        final registry = freshRegistry(ids: [_accountId, _deviceId]);
        await registry.ensureAccountIdentity();
        await registry.registerDevice(accountId: _accountId);
        await expectLater(
          registry.transitionDevice(
            _deviceId,
            DeviceLifecycleEvent.deviceRevoked,
          ),
          throwsA(isA<InvalidDeviceStateTransitionError>()),
        );
        await expectLater(
          registry.transitionDevice(
            _deviceId,
            DeviceLifecycleEvent.deviceCompromised,
          ),
          throwsA(isA<InvalidDeviceStateTransitionError>()),
        );
      },
    );

    test('pending → MAX_ATTEMPTS → LOCKED', () async {
      final registry = freshRegistry(ids: [_accountId, _deviceId]);
      await registry.ensureAccountIdentity();
      await registry.registerDevice(accountId: _accountId);
      final locked = await registry.transitionDevice(
        _deviceId,
        DeviceLifecycleEvent.maxAttemptsReached,
      );
      expect(locked!.status, DeviceStatus.locked);
    });

    test('pending → cancel → KILLED', () async {
      final registry = freshRegistry(ids: [_accountId, _deviceId]);
      await registry.ensureAccountIdentity();
      await registry.registerDevice(accountId: _accountId);
      final killed = await registry.transitionDevice(
        _deviceId,
        DeviceLifecycleEvent.cancelled,
      );
      expect(killed!.status, DeviceStatus.killed);
    });

    test(
      'pending → bootstrap expirado ⇒ GONE: GC de artefactos y registro',
      () async {
        final registry = freshRegistry(
          ids: [_accountId, _deviceId, _deviceId2],
        );
        await registry.ensureAccountIdentity();
        await registry.registerDevice(accountId: _accountId);
        final result = await registry.transitionDevice(
          _deviceId,
          DeviceLifecycleEvent.bootstrapExpired,
        );
        expect(result, isNull, reason: 'GONE no materializa estado');
        expect(await registry.findDevice(_deviceId), isNull);
        expect(
          await registry.keyStore.hasSecret(deviceSignRef(_deviceId)),
          isFalse,
        );
        expect(
          await registry.keyStore.hasSecret(deviceEncRef(_deviceId)),
          isFalse,
        );
        // La cuenta queda intacta pese al GC del device.
        expect(await registry.keyStore.hasSecret(accountRef()), isTrue);
      },
    );

    test('removeDevice borra seeds y metadatos', () async {
      final registry = freshRegistry(ids: [_accountId, _deviceId]);
      await registry.ensureAccountIdentity();
      await registry.registerDevice(accountId: _accountId);
      await registry.removeDevice(_deviceId);
      expect(await registry.findDevice(_deviceId), isNull);
      expect(
        await registry.keyStore.hasSecret(deviceSignRef(_deviceId)),
        isFalse,
      );
      expect(
        await registry.keyStore.hasSecret(deviceEncRef(_deviceId)),
        isFalse,
      );
      expect(await registry.keyStore.hasSecret(accountRef()), isTrue);
    });
  });
}

List<int> _decode(String base64) => base64Decode(base64.trim());
