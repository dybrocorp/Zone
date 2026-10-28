/// PHASE 2.2 — Bootstrap de identidad en runtime: tests UNIT.
///
/// PRODUCT INTEGRATION SLICE (autorizado CTO 2026-09-25).
///
/// Verifica con dobles en memoria (sin plataforma): primer arranque ⇒ CREATE
/// (cuenta `active` + device_1 `pending` + seeds en el almacén seguro), arranques
/// siguientes ⇒ LOAD sin regenerar ni duplicar devices, fingerprints estables,
/// y fail-closed ante cualquier inconsistencia seed↔metadatos (NUNCA se fabrica
/// identidad alternativa, NUNCA se crean devices nuevos tras un fallo).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/identity_bootstrap.dart';
import 'package:zone/identity/identity_errors.dart';
import 'package:zone/identity/identity_registry.dart';
import 'package:zone/identity/keys.dart';
import 'package:zone/identity/migration_state_machine.dart';
import 'package:zone/identity/models.dart';
import 'package:zone/identity/secure_key_store.dart';

import 'test_doubles.dart';

const String _accountId = '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d';
const String _deviceId = '2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7e';

SecretKeyRef accountSeedRef() => const SecretKeyRef(
  scope: 'account',
  purpose: KeyPurpose.accountIdentitySigning,
);

SecretKeyRef deviceSignSeedRef(String deviceId) => SecretKeyRef(
  scope: 'device',
  purpose: KeyPurpose.deviceIdentitySigning,
  deviceId: deviceId,
);

SecretKeyRef deviceEncSeedRef(String deviceId) => SecretKeyRef(
  scope: 'device',
  purpose: KeyPurpose.deviceEncryption,
  deviceId: deviceId,
);

/// Bootstrap con dobles en memoria y generador de ids determinista.
/// En arranques LOAD pasar `ids: []`: cualquier regeneración accidental lanza
/// RangeError y FAILS el test (una regeneración NUNCA debe ocurrir).
IdentityBootstrap makeBootstrap({
  required InMemoryIdentityRepository repo,
  required InMemoryKeyValueBackend backend,
  required List<String> ids,
}) {
  final queue = List<String>.of(ids);
  return IdentityBootstrap(
    registry: IdentityRegistry(
      keyStore: VersionedSecureKeyStore(backend),
      repository: repo,
      generateId: () => queue.removeAt(0),
    ),
    migrationStateReader: () async => MigrationState.legacy,
  );
}

void main() {
  group('Primer arranque (CREATE)', () {
    late InMemoryIdentityRepository repo;
    late InMemoryKeyValueBackend backend;

    setUp(() {
      repo = InMemoryIdentityRepository();
      backend = InMemoryKeyValueBackend();
    });

    test('crea cuenta active + device_1 pending y devuelve contexto público',
        () async {
      final boot = makeBootstrap(
        repo: repo,
        backend: backend,
        ids: [_accountId, _deviceId],
      );
      final ctx = await boot.run();

      expect(ctx.accountCreated, isTrue);
      expect(ctx.deviceCreated, isTrue);
      expect(ctx.accountId, _accountId);
      expect(ctx.deviceId, _deviceId);
      expect(ctx.deviceStatus, DeviceStatus.pending.statusId);
      expect(ctx.migrationState, MigrationState.legacy.statusId);

      // Fingerprints públicos normalizados (20 chars, KAT FASE 2.1).
      expect(ctx.accountFingerprint.length, 20);
      expect(ctx.deviceFingerprint.length, 20);

      // Persistencia en metadatos.
      final account = repo.account;
      expect(account, isNotNull);
      expect(account!.status, AccountIdentityStatus.active);
      expect(account.identityAlgorithm, IdentityKeyAlgorithm.ed25519);
      expect(account.identityVersion, IdentityKeyVersion.v1.value);
      expect(repo.devices.length, 1);
      expect(repo.devices.values.single.status, DeviceStatus.pending);
    });

    test('persiste las 3 seeds en el almacén seguro (account, device sign, '
        'device enc) bajo namespace zid1.', () async {
      await makeBootstrap(
        repo: repo,
        backend: backend,
        ids: [_accountId, _deviceId],
      ).run();

      final snapshot = backend.snapshot;
      expect(snapshot.containsKey(accountSeedRef().storageKey), isTrue);
      expect(snapshot.containsKey(deviceSignSeedRef(_deviceId).storageKey), isTrue);
      expect(snapshot.containsKey(deviceEncSeedRef(_deviceId).storageKey), isTrue);
      // Envelope versionado presente (nunca seed en claro).
      expect(snapshot[accountSeedRef().storageKey], startsWith('zidk1:'));
    });
  });

  group('Arranques siguientes (LOAD) — idempotencia', () {
    late InMemoryIdentityRepository repo;
    late InMemoryKeyValueBackend backend;

    setUp(() {
      repo = InMemoryIdentityRepository();
      backend = InMemoryKeyValueBackend();
    });

    test('segundo arranque (nuevo bootstrap, mismo storage) carga sin '
        'regenerar ni duplicar: ids estables, flags LOAD, 1 solo device',
        () async {
      final first = await makeBootstrap(
        repo: repo,
        backend: backend,
        ids: [_accountId, _deviceId],
      ).run();
      final second = await makeBootstrap(
        repo: repo,
        backend: backend,
        ids: [], // regeneración accidental ⇒ RangeError (FAIL)
      ).run();

      expect(second.accountId, first.accountId);
      expect(second.deviceId, first.deviceId);
      expect(second.accountCreated, isFalse);
      expect(second.deviceCreated, isFalse);
      expect(second.accountFingerprint, first.accountFingerprint);
      expect(second.deviceFingerprint, first.deviceFingerprint);
      expect(second.migrationState, first.migrationState);
      expect(repo.devices.length, 1);
    });

    test('tercer arranque mantiene la misma identidad (estabilidad)',
        () async {
      final first = await makeBootstrap(
        repo: repo,
        backend: backend,
        ids: [_accountId, _deviceId],
      ).run();
      for (var i = 0; i < 2; i++) {
        final again = await makeBootstrap(
          repo: repo,
          backend: backend,
          ids: [],
        ).run();
        expect(again.accountId, first.accountId);
        expect(again.deviceId, first.deviceId);
        expect(again.accountCreated, isFalse);
        expect(again.deviceCreated, isFalse);
        expect(again.accountFingerprint, first.accountFingerprint);
        expect(again.deviceFingerprint, first.deviceFingerprint);
      }
      expect(repo.devices.length, 1);
    });
  });

  group('Fail-closed (integridad seed ↔ metadata)', () {
    late InMemoryIdentityRepository repo;
    late InMemoryKeyValueBackend backend;

    setUp(() {
      repo = InMemoryIdentityRepository();
      backend = InMemoryKeyValueBackend();
    });

    test('seed de cuenta borrada tras el primer arranque ⇒ '
        'InconsistentIdentityStateError (no regenera)', () async {
      final ctx1 = await makeBootstrap(
        repo: repo,
        backend: backend,
        ids: [_accountId, _deviceId],
      ).run();

      await VersionedSecureKeyStore(backend).deleteSecret(accountSeedRef());

      await expectLater(
        makeBootstrap(repo: repo, backend: backend, ids: []).run(),
        throwsA(isA<InconsistentIdentityStateError>()),
      );
      // Fail-closed: nada cambia, no se crean devices nuevos.
      expect(repo.account!.accountId, ctx1.accountId);
      expect(repo.devices.length, 1);
    });

    test('metadatos de cuenta con clave pública alterada (seed intacta) ⇒ '
        'InconsistentIdentityStateError (integridad clave↔seed)', () async {
      final ctx1 = await makeBootstrap(
        repo: repo,
        backend: backend,
        ids: [_accountId, _deviceId],
      ).run();
      final original = repo.account!;
      final tampered = AccountIdentity(
        accountId: original.accountId,
        zoneId: original.zoneId,
        // Clave pública "legítima" pero DISTINTA de la derivada de la seed.
        identityPublicKeyBase64: base64Encode(List.filled(32, 1)),
        identityAlgorithm: original.identityAlgorithm,
        identityVersion: original.identityVersion,
        status: original.status,
        createdAt: original.createdAt,
        updatedAt: original.updatedAt,
      );
      await repo.saveAccount(tampered);

      await expectLater(
        makeBootstrap(repo: repo, backend: backend, ids: []).run(),
        throwsA(isA<InconsistentIdentityStateError>()),
      );
      expect(repo.account!.accountId, ctx1.accountId);
      expect(repo.devices.length, 1);
    });

    test('seed de firma del device borrada ⇒ SecureKeyMissingError '
        '(fail-closed, no deja el arranque "funcionando")', () async {
      await makeBootstrap(
        repo: repo,
        backend: backend,
        ids: [_accountId, _deviceId],
      ).run();

      await VersionedSecureKeyStore(backend).deleteSecret(
        deviceSignSeedRef(_deviceId),
      );

      await expectLater(
        makeBootstrap(repo: repo, backend: backend, ids: []).run(),
        throwsA(isA<SecureKeyMissingError>()),
      );
      expect(repo.devices.length, 1);
    });
  });
}