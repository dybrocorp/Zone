/// PHASE 2.2 — Bootstrap de identidad en runtime: test INTEGRATION.
///
/// PRODUCT INTEGRATION SLICE (autorizado CTO 2026-09-25).
///
/// Verifica el bootstrap PRODUCTIVO con Isar REAL en directorio temporal:
/// - materializa físicamente `zone_identity.isar` y NO crea `default.isar`
///   (persistencia dedicada, §15 — nunca se mezclan bases);
/// - el reinicio de la app (cerrar instancia → reabrir en la misma ruta con el
///   mismo almacén seguro) mantiene account_id/device_id/fingerprints estables
///   con un único device_1 (no se regenera);
/// - la migración queda intacta (sin registro ⇒ legacy, ningún evento ejecutado);
/// - fail-closed en dispositivo tras pérdida de seed (corrupción simulada).
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:zone/identity/identity_bootstrap.dart';
import 'package:zone/identity/identity_errors.dart';
import 'package:zone/identity/keys.dart';
import 'package:zone/identity/migration_persistence.dart';
import 'package:zone/identity/secure_key_store.dart';

import 'test_doubles.dart';

const String _accountId = '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d';
const String _deviceId = '2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7e';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_ensureIsarCore);

  test('arranque productivo con Isar real crea zone_identity.isar y NO crea '
      'default.isar (persistencia dedicada)', () async {
    final dir = await Directory.systemTemp.createTemp('zone_boot_a');
    try {
      final backend = InMemoryKeyValueBackend();
      final boot = await IdentityBootstrap.initialize(
        directory: dir,
        secretBackend: backend,
        generateId: _queue([_accountId, _deviceId]),
      );
      final ctx = await boot.run();

      expect(ctx.accountCreated, isTrue);
      expect(ctx.deviceCreated, isTrue);
      expect(ctx.deviceStatus, 'pending');

      await boot.close();

      // Evidencia física (equivalente on-device a §15).
      expect(await File('${dir.path}/zone_identity.isar').exists(), isTrue,
          reason: 'la fundación debe materializar su propia instancia');
      expect(await File('${dir.path}/default.isar').exists(), isFalse,
          reason: 'nunca se reutiliza la base legacy');
    } finally {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  test('reinicio real (misma ruta + mismo almacén): ids y fingerprints '
      'estables, único device_1, migración intacta (ningún evento)', () async {
    final dir = await Directory.systemTemp.createTemp('zone_boot_b');
    try {
      final backend = InMemoryKeyValueBackend();

      // ── PRIMER ARRANQUE (CREATE) ──
      final first = await IdentityBootstrap.initialize(
        directory: dir,
        secretBackend: backend,
        generateId: _queue([_accountId, _deviceId]),
      );
      final ctx1 = await first.run();
      expect(ctx1.accountCreated, isTrue);
      await first.close();

      // ── SEGUNDO ARRANQUE (LOAD) — proceso "reiniciado" ──
      final second = await IdentityBootstrap.initialize(
        directory: dir,
        secretBackend: backend,
        // Cualquier regeneración accidental ⇒ este generador lanza (FAIL).
        generateId: _regenGuard(),
      );
      final ctx2 = await second.run();

      expect(ctx2.accountId, ctx1.accountId,
          reason: 'R03: account_id estable tras reinicio');
      expect(ctx2.deviceId, ctx1.deviceId,
          reason: 'R04: device_id estable');
      expect(ctx2.accountCreated, isFalse);
      expect(ctx2.deviceCreated, isFalse);
      expect(ctx2.accountFingerprint, ctx1.accountFingerprint,
          reason: 'R05: fingerprint de cuenta estable');
      expect(ctx2.deviceFingerprint, ctx1.deviceFingerprint,
          reason: 'R05: fingerprint de dispositivo estable');

      // Un único device_1.
      final devices = await second.registry.listDevices(ctx2.accountId);
      expect(devices.length, 1);
      expect(devices.single.status.statusId, 'pending');

      // Migración NO tocada en este slice: sin registro persistido ⇒ legacy.
      final migrationRecord =
          await IsarMigrationRepository(second.isar!).load();
      expect(migrationRecord, isNull,
          reason: 'el bootstrap NO ejecuta eventos de migración (2.2.2 intacta)');

      await second.close();
    } finally {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  test('fail-closed en dispositivo: seed de cuenta borrada tras reinicio ⇒ '
      'InconsistentIdentityStateError (sin regenerar, sin tocar la base)',
      () async {
    final dir = await Directory.systemTemp.createTemp('zone_boot_c');
    try {
      final backend = InMemoryKeyValueBackend();

      final first = await IdentityBootstrap.initialize(
        directory: dir,
        secretBackend: backend,
        generateId: _queue([_accountId, _deviceId]),
      );
      final ctx1 = await first.run();
      await first.close();

      // Corrupción simulada del almacén seguro (metadata sobrevive).
      await VersionedSecureKeyStore(backend).deleteSecret(
        const SecretKeyRef(
          scope: 'account',
          purpose: KeyPurpose.accountIdentitySigning,
        ),
      );

      final restarted = await IdentityBootstrap.initialize(
        directory: dir,
        secretBackend: backend,
        generateId: _regenGuard(),
      );
      await expectLater(
        restarted.run(),
        throwsA(isA<InconsistentIdentityStateError>()),
      );
      // Fail-closed: la base dedicada sigue existiendo con su contenido previo.
      expect(await File('${dir.path}/zone_identity.isar').exists(), isTrue);
      expect((await restarted.registry.listDevices(ctx1.accountId)).length, 1);
      await restarted.close();
    } finally {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });
}

/// Cola determinista de ids para arranques CREATE.
String Function() _queue(List<String> ids) {
  final queue = List<String>.of(ids);
  return () => queue.removeAt(0);
}

/// Guardia contra regeneración: si se invoca, el test FAILS (una identidad
/// existente JAMÁS se regenera silenciosamente).
String Function() _regenGuard() => () {
  throw StateError('REGRESSION: bootstrap regeneró identidad existente');
};

/// Precarga el núcleo nativo de Isar (misma convención que los tests de
/// persistencia de la fundación: `ZONE_ISAR_CORE_PATH` → isar.dll).
Future<void> _ensureIsarCore() async {
  final override = Platform.environment['ZONE_ISAR_CORE_PATH'];
  if (override == null || override.isEmpty) return;
  final file = File(override);
  if (!await file.exists()) return;
  await Isar.initializeIsarCore(libraries: {Abi.current(): file.absolute.path});
}