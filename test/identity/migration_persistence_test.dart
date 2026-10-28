/// PHASE 2.2.1 — Persistencia Isar de la migración de identidad.
///
/// NEW FOUNDATION EXTENSION — NOT YET INTEGRATED IN THE APP FLOW.
///
/// Verifica el contrato de `IsarMigrationRepository` en la instancia
/// `zone_identity`: round-trip completo, singleton (nunca dos registros),
/// idempotencia de escritura (`putByMigrationId`), reinicio real en disco y
/// fail-closed ante estado persistido corrupto (no se materializa un estado ni
/// un evento inventado). NUNCA persiste seeds (I-004).
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:zone/identity/identity_errors.dart';
import 'package:zone/identity/migration_models.dart';
import 'package:zone/identity/migration_persistence.dart';
import 'package:zone/identity/migration_state_machine.dart';

MigrationRecord makeRecord({
  MigrationState state = MigrationState.bridged,
  String? legacyZoneId = 'ZONE-ABCD1234',
  String? boundAccountId = '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d',
  String? boundDeviceId = '2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7e',
  int attemptCount = 0,
  int rollbackCount = 0,
  List<String>? audit,
}) {
  final now = DateTime.now().toUtc();
  return MigrationRecord(
    state: state,
    createdAt: now,
    updatedAt: now,
    lastEvent: MigrationEvent.bridgeCompleted,
    attemptCount: attemptCount,
    rollbackCount: rollbackCount,
    legacyZoneId: legacyZoneId,
    boundAccountId: boundAccountId,
    boundDeviceId: boundDeviceId,
    fingerprintAcc: 'ACF1GSCB6GVT6DNV8C83',
    fingerprintDev: 'DEV93WMSUNKRR4-9WV433',
    verificationChecksum: 'sha256:deadbeef',
    failedCause: null,
    audit: audit ?? ['2026-09-25T00:00:00.000Z|legacy|migrationStarted|'],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_ensureIsarCore);

  var openCounter = 0;

  late Directory dir;
  late Isar isar;
  late IsarMigrationRepository repo;

  Future<void> openNew(String tag) async {
    final name = 'zone_identity_migration_${tag}_$openCounter';
    openCounter++;
    dir = await Directory.systemTemp.createTemp('zone_mig_${tag}_$openCounter');
    isar = await Isar.open(
      [MigrationDboSchema],
      directory: dir.path,
      name: name,
    );
    repo = IsarMigrationRepository(isar);
  }

  tearDown(() async {
    await isar.close();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('Round-trip y singleton', () {
    test('round-trip completo de MigrationRecord (todos los campos públicos)',
        () async {
      await openNew('full');
      final original = makeRecord();
      await repo.save(original);
      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.state, MigrationState.bridged);
      expect(loaded.lastEvent, MigrationEvent.bridgeCompleted);
      expect(loaded.legacyZoneId, 'ZONE-ABCD1234');
      expect(loaded.boundAccountId, '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d');
      expect(loaded.boundDeviceId, '2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7e');
      expect(loaded.fingerprintAcc, 'ACF1GSCB6GVT6DNV8C83');
      expect(loaded.fingerprintDev, 'DEV93WMSUNKRR4-9WV433');
      expect(loaded.verificationChecksum, 'sha256:deadbeef');
      expect(loaded.attemptCount, 0);
      expect(loaded.rollbackCount, 0);
      expect(loaded.audit, hasLength(1));
    });

    test('escrituras repetidas sobre el mismo registro NO crean duplicados '
        '(idempotencia putByMigrationId)', () async {
      await openNew('idem');
      await repo.save(makeRecord());
      await repo.save(makeRecord(state: MigrationState.verified));
      await repo.save(makeRecord(state: MigrationState.finalized));
      final all = await isar.migrationDbos.where().count();
      expect(all, 1, reason: 'el singleton nunca se duplica');
      final loaded = await repo.load();
      expect(loaded!.state, MigrationState.finalized);
      expect(loaded.audit, hasLength(1));
    });

    test('un registro con migrationId ajeno no puede coexistir con el '
        'singleton (DuplicateIdentityRecordError)', () async {
      await openNew('foreign');
      final now = DateTime.now().toUtc();
      final foreign = MigrationDbo()
        ..migrationId = 'another-record'
        ..state = 'legacy'
        ..createdAt = now
        ..updatedAt = now;
      await isar.writeTxn(() => isar.migrationDbos.put(foreign));
      await expectLater(
        repo.save(makeRecord()),
        throwsA(isA<DuplicateIdentityRecordError>()),
      );
    });

    test('ausencia de registro ⇒ load() devuelve null (implica LEGACY)',
        () async {
      await openNew('empty');
      expect(await repo.load(), isNull);
    });
  });

  group('Persistencia real y reinicio', () {
    test('el registro sobrevive a cerrar y reabrir la instancia en el mismo '
        'directorio', () async {
      final name = 'zone_identity_migration_restart_$openCounter';
      openCounter++;
      dir = await Directory.systemTemp.createTemp('zone_mig_restart_');
      isar = await Isar.open(
        [MigrationDboSchema],
        directory: dir.path,
        name: name,
      );
      repo = IsarMigrationRepository(isar);
      await repo.save(makeRecord(state: MigrationState.authorized));
      await isar.close();

      isar = await Isar.open(
        [MigrationDboSchema],
        directory: dir.path,
        name: name,
      );
      repo = IsarMigrationRepository(isar);
      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.state, MigrationState.authorized);
      expect(loaded.boundAccountId, '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d');
    });
  });

  group('Fail-closed ante registro persistido corrupto', () {
    test('estado desconocido ⇒ MigrationRecordCorruptError (no se inventa '
        'un estado)', () async {
      await openNew('corrupt_state');
      final now = DateTime.now().toUtc();
      final dbo = MigrationDbo()
        ..migrationId = kMigrationSingletonId
        ..state = 'zombie'
        ..createdAt = now
        ..updatedAt = now;
      await isar.writeTxn(() => isar.migrationDbos.putByMigrationId(dbo));
      await expectLater(
        repo.load(),
        throwsA(isA<MigrationRecordCorruptError>()),
      );
    });

    test('evento desconocido ⇒ MigrationRecordCorruptError', () async {
      await openNew('corrupt_event');
      final now = DateTime.now().toUtc();
      final dbo = MigrationDbo()
        ..migrationId = kMigrationSingletonId
        ..state = 'bridged'
        ..lastEvent = 'nonsense'
        ..createdAt = now
        ..updatedAt = now;
      await isar.writeTxn(() => isar.migrationDbos.putByMigrationId(dbo));
      await expectLater(
        repo.load(),
        throwsA(isA<MigrationRecordCorruptError>()),
      );
    });

    test('los errores tipados nunca exponen material privado (I-004)',
        () async {
      await openNew('nosecret');
      final err = InvalidMigrationStateTransitionError('legacy', 'finalized');
      expect(err.message, isNot(contains('private_key')));
      expect(err.message, isNot(contains('seed')));
      final corrupt = MigrationRecordCorruptError('unknown state');
      expect(corrupt.message, isNot(contains('seed')));
    });
  });
}

/// Precarga el núcleo nativo de Isar cuando `ZONE_ISAR_CORE_PATH` apunta a la
/// biblioteca local (mismo helper que `identity_persistence_test.dart`).
Future<void> _ensureIsarCore() async {
  final override = Platform.environment['ZONE_ISAR_CORE_PATH'];
  if (override == null || override.isEmpty) return;
  final file = File(override);
  if (!await file.exists()) return;
  await Isar.initializeIsarCore(libraries: {Abi.current(): file.absolute.path});
}