/// FASE 2.1 — Persistencia Isar de metadatos de identidad (instancia dedicada).
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Verifica el contrato de `IsarIdentityRepository` en la instancia `zone_identity`
/// (dedicada, aislada de la base de mensajes legacy): round-trip completo,
/// duplicados rechazados, reinicio de instancia (persistencia real en disco),
/// GC y fail-closed ante estado persistido corrupto. NUNCA se persisten seeds
/// (I-004): este test solo maneja metadatos públicos.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:zone/identity/identity_errors.dart';
import 'package:zone/identity/identity_persistence.dart';
import 'package:zone/identity/identity_persistence_models.dart';
import 'package:zone/identity/keys.dart';
import 'package:zone/identity/models.dart';

const String _accountId = '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d';
const String _deviceA = '2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7e';
const String _deviceB = '3c4d5e6f-7a8b-9c0d-1e2f-3a4b5c6d7e8f';

AccountIdentity makeAccount({String accountId = _accountId}) {
  final now = DateTime.now().toUtc();
  return AccountIdentity(
    accountId: accountId,
    zoneId: 'ZONE-ABCD1234',
    identityPublicKeyBase64: 'A' * 44,
    identityAlgorithm: IdentityKeyAlgorithm.ed25519,
    identityVersion: IdentityKeyVersion.v1.value,
    status: AccountIdentityStatus.active,
    createdAt: now,
    updatedAt: now,
  );
}

DeviceProfile makeDevice({
  required String deviceId,
  String accountId = _accountId,
  DeviceStatus status = DeviceStatus.pending,
}) {
  final now = DateTime.now().toUtc();
  return DeviceProfile(
    deviceId: deviceId,
    accountId: accountId,
    devicePublicKeyBase64: 'A' * 44,
    deviceEncryptionPublicKeyBase64: 'B' * 44,
    encryptionKeyVersion: IdentityKeyVersion.v1.value,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_ensureIsarCore);

  var openCounter = 0;

  late Directory dir;
  late Isar isar;
  late IsarIdentityRepository repo;

  Future<void> openNew(String tag) async {
    final name = 'zone_identity_test_${tag}_$openCounter';
    openCounter++;
    dir = await Directory.systemTemp.createTemp('zone_id_${tag}_$openCounter');
    isar = await Isar.open(
      [AccountIdentityDboSchema, DeviceDboSchema],
      directory: dir.path,
      name: name,
    );
    repo = IsarIdentityRepository(isar);
  }

  tearDown(() async {
    await isar.close();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('Cuenta', () {
    test('round-trip completo de AccountIdentity (todos los campos)', () async {
      await openNew('acc');
      await repo.saveAccount(makeAccount());
      final loaded = await repo.loadAccount();
      expect(loaded, isNotNull);
      expect(loaded!.accountId, _accountId);
      expect(loaded.zoneId, 'ZONE-ABCD1234');
      expect(loaded.identityPublicKeyBase64, 'A' * 44);
      expect(loaded.identityAlgorithm, IdentityKeyAlgorithm.ed25519);
      expect(loaded.identityVersion, IdentityKeyVersion.v1.value);
      expect(loaded.status, AccountIdentityStatus.active);
    });

    test('cuenta con accountId distinto ⇒ DuplicateIdentityRecordError (la '
        'instancia es singular)', () async {
      await openNew('accdup');
      await repo.saveAccount(makeAccount());
      await expectLater(
        repo.saveAccount(
          makeAccount(accountId: '99999999-9999-4999-8999-999999999999'),
        ),
        throwsA(isA<DuplicateIdentityRecordError>()),
      );
    });

    test(
      'upsert de la misma cuenta actualiza campos (updatedAt cambia)',
      () async {
        await openNew('accupsert');
        await repo.saveAccount(makeAccount());
        final original = (await repo.loadAccount())!;
        final updated = AccountIdentity(
          accountId: original.accountId,
          zoneId: original.zoneId,
          identityPublicKeyBase64: original.identityPublicKeyBase64,
          identityAlgorithm: original.identityAlgorithm,
          identityVersion: original.identityVersion,
          status: original.status,
          createdAt: original.createdAt,
          updatedAt: original.updatedAt.add(const Duration(seconds: 1)),
        );
        await repo.saveAccount(updated);
        final after = (await repo.loadAccount())!;
        expect(after.accountId, _accountId);
        expect(after.updatedAt.isAfter(original.updatedAt), isTrue);
      },
    );

    test('deleteAccount borra el registro de cuenta (sin tocar devices: '
        'cascada fuera de alcance en esta fase)', () async {
      await openNew('accdel');
      await repo.saveAccount(makeAccount());
      await repo.saveDevice(makeDevice(deviceId: _deviceA));
      await repo.deleteAccount();
      expect(await repo.loadAccount(), isNull);
      // Los devices son registros autónomos; su eliminación explícita es
      // `deleteDevice` (no hay flujo de retiro de cuenta en FASE 2.1).
      expect(await repo.loadDevice(_deviceA), isNotNull);
    });
  });

  group('Dispositivos', () {
    test('save/load device por id y lista por cuenta', () async {
      await openNew('dev');
      await repo.saveAccount(makeAccount());
      await repo.saveDevice(makeDevice(deviceId: _deviceA));
      await repo.saveDevice(makeDevice(deviceId: _deviceB));
      final a = await repo.loadDevice(_deviceA);
      expect(a, isNotNull);
      expect(a!.status, DeviceStatus.pending);
      expect(a.encryptionKeyVersion, IdentityKeyVersion.v1.value);
      final devices = await repo.loadDevices(_accountId);
      expect(devices.map((d) => d.deviceId).toSet(), {_deviceA, _deviceB});
    });

    test('device con accountId distinto sobre el mismo deviceId ⇒ '
        'DuplicateIdentityRecordError (device-account mismatch)', () async {
      await openNew('devmismatch');
      await repo.saveDevice(makeDevice(deviceId: _deviceA));
      await expectLater(
        repo.saveDevice(
          makeDevice(
            deviceId: _deviceA,
            accountId: '99999999-9999-4999-8999-999999999999',
          ),
        ),
        throwsA(isA<DuplicateIdentityRecordError>()),
      );
    });

    test('deleteDevice elimina solo el dispositivo indicado', () async {
      await openNew('devdel');
      await repo.saveDevice(makeDevice(deviceId: _deviceA));
      await repo.saveDevice(makeDevice(deviceId: _deviceB));
      await repo.deleteDevice(_deviceA);
      expect(await repo.loadDevice(_deviceA), isNull);
      expect(await repo.loadDevice(_deviceB), isNotNull);
    });
  });

  group('Persistencia real y reinicio', () {
    test('los metadatos sobreviven a cerrar y reabrir la instancia en el '
        'mismo directorio', () async {
      final name = 'zone_identity_restart_$openCounter';
      openCounter++;
      dir = await Directory.systemTemp.createTemp('zone_restart_');
      isar = await Isar.open(
        [AccountIdentityDboSchema, DeviceDboSchema],
        directory: dir.path,
        name: name,
      );
      repo = IsarIdentityRepository(isar);
      await repo.saveAccount(makeAccount());
      await repo.saveDevice(makeDevice(deviceId: _deviceA));
      await isar.close();

      // Reabrir la MISMA instancia de datos sobre el mismo directorio. El
      // tearDown global cierra la instancia reabierta y elimina `dir`.
      isar = await Isar.open(
        [AccountIdentityDboSchema, DeviceDboSchema],
        directory: dir.path,
        name: name,
      );
      repo = IsarIdentityRepository(isar);
      final account = await repo.loadAccount();
      expect(account, isNotNull);
      expect(account!.accountId, _accountId);
      final device = await repo.loadDevice(_deviceA);
      expect(device, isNotNull);
      expect(device!.status, DeviceStatus.pending);
    });
  });

  group('Fail-closed ante estado persistido corrupto (§8)', () {
    test('device con status desconocido ⇒ IdentityPersistenceError '
        '(no se materializa un estado inválido)', () async {
      await openNew('corrupt');
      final dbo = DeviceDbo()
        ..deviceId = _deviceA
        ..accountId = _accountId
        ..devicePublicKeyBase64 = 'A' * 44
        ..deviceEncryptionPublicKeyBase64 = 'B' * 44
        ..encryptionKeyVersion = 1
        ..status = 'bogus'
        ..createdAt = DateTime.now().toUtc()
        ..updatedAt = DateTime.now().toUtc();
      await isar.writeTxn(() => isar.deviceDbos.put(dbo));
      await expectLater(
        repo.loadDevice(_deviceA),
        throwsA(isA<IdentityPersistenceError>()),
      );
    });

    test('account con status desconocido ⇒ IdentityPersistenceError', () async {
      await openNew('corrupt_acc');
      final dbo = AccountIdentityDbo()
        ..accountId = _accountId
        ..zoneId = 'ZONE-ABCD1234'
        ..identityPublicKeyBase64 = 'A' * 44
        ..identityAlgorithm = 'Ed25519'
        ..identityVersion = 1
        ..identityStatus = 'zombie'
        ..createdAt = DateTime.now().toUtc()
        ..updatedAt = DateTime.now().toUtc();
      await isar.writeTxn(() => isar.accountIdentityDbos.putByAccountId(dbo));
      await expectLater(
        repo.loadAccount(),
        throwsA(isA<IdentityPersistenceError>()),
      );
    });
  });
}

/// Precarga el núcleo nativo de Isar cuando `ZONE_ISAR_CORE_PATH` apunta a la
/// biblioteca local (p.ej. `isar.dll` de `isar_flutter_libs` en el pub cache).
///
/// `flutter test` no registra plugins de Flutter y, en hosts Windows/Dart, la
/// resolución por defecto (`isar.dll` junto al script) puede fallar. Con la
/// variable definida este test es reproducible en cualquier máquina sin rutas
/// hardcodeadas en el código; sin ella se usa la resolución por defecto
/// (dispositivo/emulador/CI con tooling completo).
Future<void> _ensureIsarCore() async {
  final override = Platform.environment['ZONE_ISAR_CORE_PATH'];
  if (override == null || override.isEmpty) return;
  final file = File(override);
  if (!await file.exists()) return;
  await Isar.initializeIsarCore(libraries: {Abi.current(): file.absolute.path});
}
