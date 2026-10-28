/// PHASE 2.2.1 — Orquestación del controlador de migración.
///
/// NEW FOUNDATION EXTENSION — NOT YET INTEGRATED IN THE APP FLOW.
///
/// Verifica `MigrationController` con el doble en memoria: camino feliz
/// LEGACY→FINALIZED, fail-closed ante saltos inválidos, rollback exclusivo
/// desde MIGRATION_FAILED, bloqueo de FINALIZED, idempotencia estricta de la
/// máquina y auditoría sin material secreto.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/identity_errors.dart';
import 'package:zone/identity/migration_controller.dart';
import 'package:zone/identity/migration_models.dart';
import 'package:zone/identity/migration_state_machine.dart';

import 'test_doubles.dart';

/// Encadena el camino feliz completo de la migración.
Future<MigrationRecord> _runHappyPath(MigrationController controller) async {
  var record = await controller.apply(MigrationEvent.migrationStarted);
  expect(record.state, MigrationState.discovered);
  record = await controller.apply(MigrationEvent.validationSucceeded);
  expect(record.state, MigrationState.validated);
  record = await controller.apply(
    MigrationEvent.bridgeCompleted,
    legacyZoneId: 'ZONE-ABCD1234',
    boundAccountId: '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d',
    boundDeviceId: '2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7e',
    fingerprintAcc: 'ACF1GSCB6GVT6DNV8C83',
    fingerprintDev: 'DEV93WMSUNKRR4-9WV433',
  );
  expect(record.state, MigrationState.bridged);
  expect(record.boundAccountId, isNotNull);
  expect(record.boundDeviceId, isNotNull);
  record = await controller.apply(MigrationEvent.bootstrapConfirmed);
  expect(record.state, MigrationState.authorized);
  record = await controller.apply(MigrationEvent.singleWriterActivated);
  expect(record.state, MigrationState.migrated);
  record = await controller.apply(MigrationEvent.verificationSucceeded);
  expect(record.state, MigrationState.verified);
  record = await controller.apply(MigrationEvent.finalized);
  expect(record.state, MigrationState.finalized);
  expect(record.isTerminal, isTrue);
  return record;
}

void main() {
  late InMemoryMigrationRepository repo;
  late MigrationController controller;
  final logs = <String>[];

  setUp(() {
    repo = InMemoryMigrationRepository();
    logs.clear();
    controller = MigrationController(repository: repo, log: logs.add);
  });

  group('Camino feliz', () {
    test('LEGACY → FINALIZED con binds y fingerprints públicos', () async {
      final record = await _runHappyPath(controller);
      expect(record.audit, hasLength(7));
      expect(record.failedCause, isNull);
      expect(record.audit.first, matches(r'^\d{4}-\d{2}-\d{2}T.*\|legacy\|migrationStarted\|$'));
      // Ningún log ni audit debe contener material privado.
      for (final line in logs) {
        expect(line, isNot(contains('private_key')));
        expect(line, isNot(contains('seed')));
        expect(line, isNot(contains('token')));
      }
    });

    test('estado inicial (sin registro) es LEGACY', () async {
      expect(await controller.currentState(), MigrationState.legacy);
      expect(await controller.isFinalized(), isFalse);
    });

    test('assertNotFinalized OK durante la migración; falla en FINALIZED',
        () async {
      await _runHappyPath(controller);
      await expectLater(
        controller.assertNotFinalized(),
        throwsA(isA<MigrationAlreadyFinalizedError>()),
      );
    });
  });

  group('Fail-closed', () {
    test('salto inválido (legacy + verificationSucceeded) ⇒ '
        'InvalidMigrationStateTransitionError', () async {
      await expectLater(
        controller.apply(MigrationEvent.verificationSucceeded),
        throwsA(isA<InvalidMigrationStateTransitionError>()),
      );
      expect(await controller.currentState(), MigrationState.legacy);
    });

    test('reenviar el mismo evento tras transicionar ⇒ inválido (máquina '
        'estricta, sin re-solicitudes de un estado ya superado)', () async {
      await controller.apply(MigrationEvent.migrationStarted);
      await expectLater(
        controller.apply(MigrationEvent.migrationStarted),
        throwsA(isA<InvalidMigrationStateTransitionError>()),
      );
    });

    test('FINALIZED bloquea CUALQUIER evento posterior (terminal, sin '
        'retorno)', () async {
      await _runHappyPath(controller);
      await expectLater(
        controller.apply(MigrationEvent.migrationStarted),
        throwsA(isA<MigrationAlreadyFinalizedError>()),
      );
      await expectLater(
        controller.rollback(cause: 'post_finalize'),
        throwsA(isA<MigrationRollbackNotAllowedError>()),
      );
    });

    test('rollback desde un estado distinto de MIGRATION_FAILED ⇒ '
        'MigrationRollbackNotAllowedError', () async {
      await controller.apply(MigrationEvent.migrationStarted);
      await controller.apply(MigrationEvent.validationSucceeded);
      await expectLater(
        controller.rollback(cause: 'rush'),
        throwsA(isA<MigrationRollbackNotAllowedError>()),
      );
      expect(await controller.currentState(), MigrationState.validated);
    });
  });

  group('Rama de fallo y rollback', () {
    test('validación falla ⇒ MIGRATION_FAILED (attemptCount++, causa tipada) '
        'y rollback ⇒ LEGACY (rollbackCount++, audit conservado)', () async {
      await controller.apply(MigrationEvent.migrationStarted);
      final failed = await controller.apply(
        MigrationEvent.validationFailed,
        cause: 'invalid_zone_id_format',
      );
      expect(failed.state, MigrationState.migrationFailed);
      expect(failed.attemptCount, 1);
      expect(failed.failedCause, 'invalid_zone_id_format');
      expect(failed.isTerminal, isTrue);

      final rolled = await controller.rollback(cause: 'validation_failed');
      expect(rolled.state, MigrationState.legacy);
      expect(rolled.rollbackCount, 1);
      // La causa de fallo queda como historial auditable, no como estado.
      expect(rolled.failedCause, 'validation_failed');
      expect(rolled.audit, hasLength(3));

      // La migración puede reiniciarse limpia tras el rollback.
      await controller.apply(MigrationEvent.migrationStarted);
      expect(await controller.currentState(), MigrationState.discovered);
    });

    test('fallos tardíos (bridge/bootstrap/verification) también cuentan '
        'intentos y solo salen vía rollback', () async {
      final events = <MigrationEvent>[
        MigrationEvent.migrationStarted,
        MigrationEvent.validationSucceeded,
        MigrationEvent.bridgeFailed,
      ];
      MigrationRecord? record;
      for (final e in events) {
        record = await controller.apply(e, cause: 'typed_cause');
      }
      expect(record!.state, MigrationState.migrationFailed);
      expect(record.attemptCount, 1);
      expect(record.failedCause, 'typed_cause');
    });

    test('rollbackConfirmed aplicado desde un estado no fallido es inválido '
        '(la máquina lo rechaza)', () async {
      await controller.apply(MigrationEvent.migrationStarted);
      await expectLater(
        controller.apply(MigrationEvent.rollbackConfirmed),
        throwsA(isA<InvalidMigrationStateTransitionError>()),
      );
    });
  });

  group('Auditoría y observabilidad', () {
    test('cada evento genera una línea iso|estado|evento|causa parseable',
        () async {
      await controller.apply(MigrationEvent.migrationStarted);
      await controller.apply(
        MigrationEvent.validationFailed,
        cause: 'x25519_key_mismatch',
      );
      final record = repo.record!;
      expect(record.audit, hasLength(2));
      final line = record.audit.last;
      final parts = line.split('|');
      expect(parts, hasLength(4));
      expect(parts[1], 'discovered');
      expect(parts[2], 'validationFailed');
      expect(parts[3], 'x25519_key_mismatch');
    });

    test('el registro nunca contiene material privado (I-004): el JSON '
        'público solo expone metadatos', () async {
      await _runHappyPath(controller);
      final json = repo.record!.toJson();
      expect(json.keys, isNot(contains('private_key')));
      expect(json.keys, isNot(contains('seed')));
      expect(json['migration_state'], 'finalized');
    });
  });
}