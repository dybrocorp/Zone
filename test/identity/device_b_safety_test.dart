/// PHASE 2.2.2 — Identity coherence / Device B safety: tests UNIT.
///
/// Verifica con dobles en memoria (sin plataforma, sin Isar nativo):
/// 1. fresh device crea identidad nueva (account + device_1 pending).
/// 2. reinicio carga la misma identidad (LOAD, sin regenerar ni duplicar).
/// 3. identidad parcial falla cerrado (NUNCA regenera en silencio).
/// 4. el claim legacy same-account está en cuarentena (fail-closed, sin I/O).
/// 5. legacy no puede sobrescribir la identidad de la fundación
///    (namespaces disjuntos + instancia Isar dedicada).
/// 6./7. Device A y Device B tienen device IDs y material independientes.
/// 8. el estado permanece consistente tras reinicio (fingerprints estables).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/identity_bootstrap.dart';
import 'package:zone/identity/identity_errors.dart';
import 'package:zone/identity/identity_registry.dart';
import 'package:zone/identity/keys.dart';
import 'package:zone/identity/migration_state_machine.dart';
import 'package:zone/identity/models.dart';
import 'package:zone/identity/secure_key_store.dart';
import 'package:zone/services/same_account_claim_policy.dart';

import 'test_doubles.dart';

// UUIDs deterministas (formato canónico lowercase) para los dobles.
const String _accountA = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const String _deviceA = 'aaaaaaaa-2222-4222-8222-aaaaaaaaaaaa';
const String _accountB = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb';
const String _deviceB = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';

SecretKeyRef _accountRef() => const SecretKeyRef(
  scope: 'account',
  purpose: KeyPurpose.accountIdentitySigning,
);

SecretKeyRef _deviceSignRef(String deviceId) => SecretKeyRef(
  scope: 'device',
  purpose: KeyPurpose.deviceIdentitySigning,
  deviceId: deviceId,
);

SecretKeyRef _deviceEncRef(String deviceId) => SecretKeyRef(
  scope: 'device',
  purpose: KeyPurpose.deviceEncryption,
  deviceId: deviceId,
);

IdentityRegistry _registry({
  required InMemoryIdentityRepository repo,
  required InMemoryKeyValueBackend backend,
  required List<String> ids,
}) {
  final queue = List<String>.of(ids);
  return IdentityRegistry(
    keyStore: VersionedSecureKeyStore(backend),
    repository: repo,
    generateId: () => queue.removeAt(0),
  );
}

IdentityBootstrap _bootstrap({
  required IdentityRegistry registry,
}) => IdentityBootstrap(
  registry: registry,
  migrationStateReader: () async => MigrationState.legacy,
);

AccountIdentity _metadataOnly(String accountId) => AccountIdentity(
  accountId: accountId,
  identityPublicKeyBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  identityAlgorithm: IdentityKeyAlgorithm.ed25519,
  identityVersion: IdentityKeyVersion.v1.value,
  status: AccountIdentityStatus.active,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  group('1. fresh device crea identidad nueva', () {
    test('CREATE: account active + device_1 pending, ids UUID distintos',
        () async {
      final repo = InMemoryIdentityRepository();
      final backend = InMemoryKeyValueBackend();
      // El bootstrap consume 2 ids (account + device_1).
      final boot = _bootstrap(
        registry: _registry(
          repo: repo,
          backend: backend,
          ids: [_accountA, _deviceA],
        ),
      );
      final ctx = await boot.run();
      expect(ctx.accountId, _accountA);
      expect(ctx.deviceId, _deviceA);
      expect(ctx.accountId, isNot(ctx.deviceId));
      expect(ctx.deviceStatus, DeviceStatus.pending.statusId);
      expect(ctx.accountCreated, isTrue);
      expect(ctx.deviceCreated, isTrue);
      expect(ctx.migrationState, MigrationState.legacy.statusId);
      // Fingerprints públicos presentes y con formato canónico (20 chars).
      expect(ctx.accountFingerprint, hasLength(20));
      expect(ctx.deviceFingerprint, hasLength(20));
    });
  });

  group('2. reinicio carga la misma identidad', () {
    test('LOAD: mismos ids, sin regenerar (ids: [] ⇒ regenerar lanzaría)',
        () async {
      final repo = InMemoryIdentityRepository();
      final backend = InMemoryKeyValueBackend();
      final first = await _bootstrap(
        registry: _registry(
          repo: repo,
          backend: backend,
          ids: [_accountA, _deviceA],
        ),
      ).run();
      // Nota: repo+backend ya poblados por el primer run, por lo que el
      // segundo run debe ser LOAD.
      expect(first.accountCreated, isTrue);

      final second = await _bootstrap(
        registry: _registry(repo: repo, backend: backend, ids: const []),
      ).run();
      expect(second.accountId, first.accountId);
      expect(second.deviceId, first.deviceId);
      expect(second.accountCreated, isFalse);
      expect(second.deviceCreated, isFalse);
      final devices = await _registry(
        repo: repo,
        backend: backend,
        ids: const [],
      ).listDevices(first.accountId);
      expect(devices, hasLength(1));
    });
  });

  group('3. identidad parcial falla cerrado', () {
    test('metadata sin seed ⇒ InconsistentIdentityStateError (sin regenerar)',
        () async {
      final repo = InMemoryIdentityRepository();
      final backend = InMemoryKeyValueBackend();
      await repo.saveAccount(_metadataOnly(_accountA));
      final registry = _registry(repo: repo, backend: backend, ids: const []);
      await expectLater(
        registry.ensureAccountIdentity(),
        throwsA(isA<InconsistentIdentityStateError>()),
      );
      // Sin regeneración silenciosa: el metadata sigue intacto, sin seed nueva.
      expect((await repo.loadAccount())?.accountId, _accountA);
      expect(await registry.keyStore.hasSecret(_accountRef()), isFalse);
    });

    test('seed sin metadata ⇒ InconsistentIdentityStateError (sin regenerar)',
        () async {
      final repo = InMemoryIdentityRepository();
      final backend = InMemoryKeyValueBackend();
      final registry = _registry(repo: repo, backend: backend, ids: const []);
      await registry.keyStore.writeSecret(
        _accountRef(),
        List<int>.filled(kIdentitySeedLength, 7),
      );
      await expectLater(
        registry.ensureAccountIdentity(),
        throwsA(isA<InconsistentIdentityStateError>()),
      );
      expect(await repo.loadAccount(), isNull);
    });
  });

  group('4. claim legacy same-account en cuarentena', () {
    tearDown(() {
      SameAccountClaimPolicy.allowSameAccountClaim = false;
    });

    test('por defecto BLOQUEA con estado migración-no-disponible', () {
      SameAccountClaimPolicy.allowSameAccountClaim = false;
      expect(
        () => SameAccountClaimPolicy.ensureAllowed('ZONE-ABCD1234'),
        throwsA(isA<SameAccountClaimBlockedError>()),
      );
    });

    test('el error es explícito y no expone material secreto', () {
      try {
        SameAccountClaimPolicy.ensureAllowed('ZONE-ABCD1234');
        fail('debió lanzar SameAccountClaimBlockedError');
      } on SameAccountClaimBlockedError catch (e) {
        final msg = e.toString();
        expect(msg, contains('migración'));
        expect(msg.toLowerCase(), isNot(contains('seed')));
        expect(msg.toLowerCase(), isNot(contains('private')));
        expect(msg.toLowerCase(), isNot(contains('zidk1')));
      }
    });

    test('el kill-switch solo lo puede levantar el futuro puente', () {
      SameAccountClaimPolicy.allowSameAccountClaim = true;
      expect(
        () => SameAccountClaimPolicy.ensureAllowed('ZONE-ABCD1234'),
        returnsNormally,
      );
    });
  });

  group('5. legacy no puede sobrescribir la fundación', () {
    test('todas las claves de la fundación viven bajo zid1.*', () {
      final refs = [
        _accountRef(),
        _deviceSignRef(_deviceA),
        _deviceEncRef(_deviceA),
        _deviceSignRef(_deviceB),
        _deviceEncRef(_deviceB),
      ];
      const legacyKeys = {
        'zone_id',
        'supabase_uid',
        'private_key',
        'public_key',
      };
      for (final ref in refs) {
        expect(ref.storageKey, startsWith('$kSecureKeyNamespacePrefix.'));
        expect(legacyKeys, isNot(contains(ref.storageKey)));
        expect(ref.storageKey.startsWith('sk_'), isFalse);
        expect(ref.storageKey.startsWith('pseudo_'), isFalse);
      }
      // Las claves de dispositivo están acotadas por deviceId: no colisionan
      // entre dispositivos aunque compartan propósito.
      expect(
        _deviceSignRef(_deviceA).storageKey,
        isNot(_deviceSignRef(_deviceB).storageKey),
      );
    });

    test('ninguna clave legacy usa el namespace de la fundación', () {
      const legacyKeys = [
        'zone_id',
        'supabase_uid',
        'private_key',
        'public_key',
        'sk_ZONE-X',
        'pseudo_abc',
      ];
      for (final key in legacyKeys) {
        expect(key.startsWith('$kSecureKeyNamespacePrefix.'), isFalse);
      }
    });

    test('la fundación usa instancia Isar dedicada, no la legacy', () {
      expect(kIdentityIsarInstanceName, 'zone_identity');
      expect(kIdentityIsarInstanceName, isNot('default'));
    });
  });

  group('6./7. Device A y Device B independientes', () {
    test('distintos account_id, device_id y material de claves', () async {
      final repoA = InMemoryIdentityRepository();
      final backendA = InMemoryKeyValueBackend();
      final repoB = InMemoryIdentityRepository();
      final backendB = InMemoryKeyValueBackend();

      final regA = _registry(
        repo: repoA,
        backend: backendA,
        ids: [_accountA, _deviceA],
      );
      final regB = _registry(
        repo: repoB,
        backend: backendB,
        ids: [_accountB, _deviceB],
      );

      final ctxA = await _bootstrap(registry: regA).run();
      final ctxB = await _bootstrap(registry: regB).run();

      // 6. Identificadores independientes.
      expect(ctxA.accountId, isNot(ctxB.accountId));
      expect(ctxA.deviceId, isNot(ctxB.deviceId));
      expect(ctxA.deviceId, isNot(ctxA.accountId));

      // 7. Material independiente (claves públicas derivadas distintas).
      final matA = await regA.loadAccountKeyMaterial(ctxA.accountId);
      final matB = await regB.loadAccountKeyMaterial(ctxB.accountId);
      expect(await matA.publicKeyBase64(), isNot(await matB.publicKeyBase64()));

      final devA = await regA.loadDeviceKeyMaterial(ctxA.deviceId);
      final devB = await regB.loadDeviceKeyMaterial(ctxB.deviceId);
      expect(
        await devA.devicePublicKeyBase64(),
        isNot(await devB.devicePublicKeyBase64()),
      );
      expect(
        await devA.encryptionPublicKeyBase64(),
        isNot(await devB.encryptionPublicKeyBase64()),
      );

      // Huellas distintas por construcción (distinto dispositivo).
      expect(ctxA.deviceFingerprint, isNot(ctxB.deviceFingerprint));

      // B no reutiliza nada de A: las claves acotadas por dispositivo no se
      // solapan, y el envelope de cuenta (misma key name por diseño,
      // ámbito account) contiene un valor distinto.
      final keysA = backendA.snapshot.keys.toSet();
      final keysB = backendB.snapshot.keys.toSet();
      final deviceKeysA = keysA.where((k) => k.contains(ctxA.deviceId));
      final deviceKeysB = keysB.where((k) => k.contains(ctxB.deviceId));
      expect(deviceKeysA, isNotEmpty);
      expect(deviceKeysB, isNotEmpty);
      for (final key in deviceKeysA) {
        expect(deviceKeysB, isNot(contains(key)));
      }
      const accountKey = 'zid1.account.accountIdentitySigning';
      expect(backendA.snapshot[accountKey], isNotNull);
      expect(backendB.snapshot[accountKey], isNotNull);
      expect(backendA.snapshot[accountKey], isNot(backendB.snapshot[accountKey]));
    });
  });

  group('8. estado consistente tras reinicio', () {
    test('segundo arranque: mismos ids + fingerprints estables', () async {
      final repo = InMemoryIdentityRepository();
      final backend = InMemoryKeyValueBackend();
      final first = await _bootstrap(
        registry: _registry(
          repo: repo,
          backend: backend,
          ids: [_accountA, _deviceA],
        ),
      ).run();
      final second = await _bootstrap(
        registry: _registry(repo: repo, backend: backend, ids: const []),
      ).run();

      expect(second.accountId, first.accountId);
      expect(second.deviceId, first.deviceId);
      expect(second.accountFingerprint, first.accountFingerprint);
      expect(second.deviceFingerprint, first.deviceFingerprint);
      expect(second.deviceStatus, DeviceStatus.pending.statusId);
    });
  });
}
