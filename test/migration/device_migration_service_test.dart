/// Z-213 PHASE F/G — tests del servicio de migración de dispositivo.
///
/// Propiedades (no solo happy path):
/// 1. IDs estables de pendiente (idempotencia de begin, reutilización exacta).
/// 2. Transiciones forward-only (salto ilegal ⇒ error, cero mutación).
/// 3. NO-destroy-before-confirm: denied/expired/fallo backend ⇒ activo previo
///    INTACTO (regla central del pipeline B).
/// 4. Confirm idempotente (revocación del previo SOLO una vez).
/// 5. D(revoke) exige confirmReason explícita ('replaced' reservada a B).
/// 6. Backend no provisionado ⇒ error propagado, cero cambios destructivos,
///    jamás interpretado como denied.
/// 7. Fresco tras intento terminal: id NUEVO (auditoría limpia).
/// UNIDADES PROBADAS LOCALMENTE (in-memory persistence + backend doble).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zone/migration/device_migration_service.dart';
import 'package:zone/migration/device_migration_state.dart';

/// Backend doble configurable (no RFC, no secretos) — a file scope (Dart
/// no permite clases declaradas dentro de funciones).
class RecordingBackend implements DeviceMigrationBackend {
  RecordingBackend(this.verdict);

  DeviceMigrationBackendOutcome? verdict;
  Object? throwInstead;
  final List<DeviceMigrationPending> requests = <DeviceMigrationPending>[];

  @override
  Future<DeviceMigrationBackendOutcome> requestDeviceBinding(
    DeviceMigrationPending pending,
  ) async {
    requests.add(pending);
    final t = throwInstead;
    if (t != null) throw t;
    return verdict!;
  }
}

void main() {
  const String deviceFp =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; // 64 hex
  const String oldDeviceId = 'device-old-1111';
  const String newDeviceId = 'device-new-2222';

  group('beginMigration — ids estables + idempotencia', () {
    test('mismo (plan, fp) no-terminal ⇒ MISMO id sin duplicados', () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final service = DeviceMigrationService(persistence: persistence);

      final p1 = await service.beginMigration(
        plan: DeviceMigrationPlan.addDevice,
        deviceFingerprint: deviceFp,
      );
      final p2 = await service.beginMigration(
        plan: DeviceMigrationPlan.addDevice,
        deviceFingerprint: deviceFp,
      );

      expect(p1.id, p2.id);
      expect(
        (await persistence.loadPendings()).length,
        1,
        reason: 'begin idempotente NO duplica registros',
      );
    });

    test('otro fingerprint/plan ⇒ pendiente distinto (id distinto)', () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final service = DeviceMigrationService(persistence: persistence);

      final a = await service.beginMigration(
        plan: DeviceMigrationPlan.addDevice,
        deviceFingerprint: deviceFp,
      );
      final b = await service.beginMigration(
        plan: DeviceMigrationPlan.addDevice,
        deviceFingerprint: 'b' * 64,
      );

      expect(a.id, isNot(b.id));
      expect((await persistence.loadPendings()).length, 2);
    });

    test('replace exige oldActiveDeviceId (regla NO-TOFU/tampón)', () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final service = DeviceMigrationService(persistence: persistence);

      expect(
        () => service.beginMigration(
          plan: DeviceMigrationPlan.replaceDevice,
          deviceFingerprint: deviceFp,
        ),
        throwsA(isA<MigrationStateError>()),
      );
      expect(
        (await persistence.loadPendings()).length,
        0,
        reason: 'el error tipado NO deja registros parciales',
      );
    });

    test('después del intento terminal: intento NUEVO con id NUEVO', () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final backend = RecordingBackend(DeviceMigrationBackendOutcome.approved);
      final service = DeviceMigrationService(
        persistence: persistence,
        backend: backend,
      );

      final first = await service.beginMigration(
        plan: DeviceMigrationPlan.addDevice,
        deviceFingerprint: deviceFp,
      );
      await service.markRequested(first.id);
      await service.awaitBackendDecision(first.id);
      await service.confirmAndActivate(
        pendingId: first.id,
        newDeviceId: newDeviceId,
      );

      final second = await service.beginMigration(
        plan: DeviceMigrationPlan.addDevice,
        deviceFingerprint: deviceFp,
      );
      expect(second.id, isNot(first.id));
      expect(
        (await persistence.loadPendings()).length,
        2,
        reason: 'dos intentos ⇒ dos registros (auditoría limpia)',
      );
    });
  });

  group('transiciones forward-only (fail-closed)', () {
    test('salto de fase (draft → approved) ⇒ error tipado, sin mutación',
        () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final service = DeviceMigrationService(persistence: persistence);
      final p = await service.beginMigration(
        plan: DeviceMigrationPlan.addDevice,
        deviceFingerprint: deviceFp,
      );
      final before = (await persistence.loadPendings()).single;

      expect(
        () => service.markBackendVerdict(
          pendingId: p.id,
          outcome: DeviceMigrationBackendOutcome.approved,
        ),
        throwsA(
          isA<MigrationStateError>()
              .having((e) => e.reason, 'reason', 'illegal_transition'),
        ),
      );
      final after = (await persistence.loadPendings()).single;
      expect(after.phase, before.phase);
      expect(
        after.updatedAt.millisecondsSinceEpoch,
        before.updatedAt.millisecondsSinceEpoch,
        reason: 'cero mutaciones persistidas con operación fail-closed',
      );
    });

    test('requested → denied es terminal: NO se puede re-aprobar', () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final backend = RecordingBackend(DeviceMigrationBackendOutcome.denied);
      final service = DeviceMigrationService(
        persistence: persistence,
        backend: backend,
      );
      final p = await service.beginMigration(
        plan: DeviceMigrationPlan.addDevice,
        deviceFingerprint: deviceFp,
      );
      await service.markRequested(p.id);
      await service.awaitBackendDecision(p.id);
      expect(p.isTerminal, isFalse);
      final denied = await service.pending(p.id);
      expect(denied!.phase, DeviceMigrationPhase.denied);
      expect(denied.isTerminal, isTrue);

      expect(
        () => service.markBackendVerdict(
          pendingId: p.id,
          outcome: DeviceMigrationBackendOutcome.approved,
        ),
        throwsA(isA<MigrationStateError>().having(
          (e) => e.reason,
          'reason',
          'illegal_transition',
        )),
      );
    });

    test('awaitBackendDecision sin fase requested ⇒ error de precondición',
        () async {
      final service = DeviceMigrationService(
        persistence: InMemoryDeviceMigrationPersistence(),
      );
      final p = await service.beginMigration(
        plan: DeviceMigrationPlan.addDevice,
        deviceFingerprint: deviceFp,
      );
      // Aún en draft (sin markRequested).
      expect(
        service.awaitBackendDecision(p.id),
        throwsA(
          isA<MigrationStateError>()
              .having((e) => e.reason, 'reason', 'preconditions'),
        ),
      );
    });
  });

  group('B(replace) — NO-destroy-before-confirm', () {
    test('approved NO destruye: solo confirmAndActivate', () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final backend = RecordingBackend(DeviceMigrationBackendOutcome.approved);
      final service = DeviceMigrationService(
        persistence: persistence,
        backend: backend,
      );
      await persistence.saveActiveDeviceId(oldDeviceId);

      final p = await service.beginMigration(
        plan: DeviceMigrationPlan.replaceDevice,
        deviceFingerprint: deviceFp,
        oldActiveDeviceId: oldDeviceId,
      );
      await service.markRequested(p.id);
      await service.awaitBackendDecision(p.id); // → approved

      // CRÍTICA: tras approval, el activo previo SIGUE activo (sin revoke).
      expect(
        await persistence.loadActiveDeviceId(),
        oldDeviceId,
        reason: 'NO-destroy-before-confirm: apenas se aprueba, no destruye',
      );
      expect(
        (await persistence.loadRevocations()),
        isEmpty,
        reason: 'no revocación registrada antes de confirm',
      );

      await service.confirmAndActivate(
        pendingId: p.id,
        newDeviceId: newDeviceId,
      );
      // Ahora sí: activo nuevo + revocación de previo 'replaced'.
      expect(await persistence.loadActiveDeviceId(), newDeviceId);
      final revocations = await persistence.loadRevocations();
      expect(revocations, hasLength(1));
      expect(revocations.single.deviceId, oldDeviceId);
      expect(revocations.single.reason, 'replaced');
    });

    test(
        'denied/expired/fallo backend ⇒ activo previo INTACTO (sin destroy)',
        () async {
      for (final outcome in <DeviceMigrationBackendOutcome>[
        DeviceMigrationBackendOutcome.denied,
        DeviceMigrationBackendOutcome.expired,
      ]) {
        final persistence = InMemoryDeviceMigrationPersistence();
        final backend = RecordingBackend(outcome);
        final service = DeviceMigrationService(
          persistence: persistence,
          backend: backend,
        );
        await persistence.saveActiveDeviceId(oldDeviceId);

        final p = await service.beginMigration(
          plan: DeviceMigrationPlan.replaceDevice,
          deviceFingerprint: deviceFp,
          oldActiveDeviceId: oldDeviceId,
        );
        await service.markRequested(p.id);
        await service.awaitBackendDecision(p.id);

        expect(await persistence.loadActiveDeviceId(), oldDeviceId);
        expect(
          await persistence.loadRevocations(),
          isEmpty,
          reason: 'denied/expired NO destruyen el activo previo',
        );
      }
    });

    test('backend LANZA excepción ⇒ propagada sin cambios de fase/estado',
        () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final backend = RecordingBackend(null)..throwInstead = Exception('x');
      final service = DeviceMigrationService(
        persistence: persistence,
        backend: backend,
      );
      await persistence.saveActiveDeviceId(oldDeviceId);

      final p = await service.beginMigration(
        plan: DeviceMigrationPlan.replaceDevice,
        deviceFingerprint: deviceFp,
        oldActiveDeviceId: oldDeviceId,
      );
      await service.markRequested(p.id);

      expect(
        service.awaitBackendDecision(p.id),
        throwsA(isA<Exception>()),
      );
      // El pendiente SIGUE requested (no mutado a denied).
      final still = await service.pending(p.id);
      expect(still!.phase, DeviceMigrationPhase.requested);
      expect(await persistence.loadActiveDeviceId(), oldDeviceId);
      expect(await persistence.loadRevocations(), isEmpty);
    });

    test('RemoteDeviceMigrationBackend SIEMPRE fail-closed (no provisioned)',
        () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final service = DeviceMigrationService(persistence: persistence);
      final p = await service.beginMigration(
        plan: DeviceMigrationPlan.addDevice,
        deviceFingerprint: deviceFp,
      );
      await service.markRequested(p.id);

      expect(
        service.awaitBackendDecision(p.id),
        throwsA(isA<BackendNotProvisionedError>()),
      );
      final still = await service.pending(p.id);
      expect(still!.phase, DeviceMigrationPhase.requested);
    });

    test(
        'confirm idempotente: revocación del previo EXACTAMENTE una vez',
        () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final backend = RecordingBackend(DeviceMigrationBackendOutcome.approved);
      final service = DeviceMigrationService(
        persistence: persistence,
        backend: backend,
      );
      await persistence.saveActiveDeviceId(oldDeviceId);

      final p = await service.beginMigration(
        plan: DeviceMigrationPlan.replaceDevice,
        deviceFingerprint: deviceFp,
        oldActiveDeviceId: oldDeviceId,
      );
      await service.markRequested(p.id);
      await service.awaitBackendDecision(p.id);
      await service.confirmAndActivate(
        pendingId: p.id,
        newDeviceId: newDeviceId,
      );
      // Segundo confirm sobre el MISMO pendiente (reintento UI) — no-op.
      await service.confirmAndActivate(
        pendingId: p.id,
        newDeviceId: newDeviceId,
      );

      final revocations = await persistence.loadRevocations();
      expect(revocations, hasLength(1));
      expect(await persistence.loadActiveDeviceId(), newDeviceId);
    });
  });

  group('D(revoke) — acción directa con confirm explícita', () {
    test('sin razón de confirmación válida ⇒ error, NADA se destruye',
        () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final service = DeviceMigrationService(persistence: persistence);
      await persistence.saveActiveDeviceId(oldDeviceId);

      for (final bad in const ['', 'replaced', 'otra']) {
        expect(
          () => service.revokeActive(
            deviceId: oldDeviceId,
            confirmReason: bad,
          ),
          throwsA(isA<MigrationStateError>()),
        );
      }
      expect(await persistence.loadActiveDeviceId(), oldDeviceId);
      expect(await persistence.loadRevocations(), isEmpty);
    });

    test('dispositivo no es el activo ⇒ error (no destroy de otros)', () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final service = DeviceMigrationService(persistence: persistence);
      await persistence.saveActiveDeviceId(oldDeviceId);

      expect(
        () => service.revokeActive(
          deviceId: 'device-otro-9999',
          confirmReason: 'user_initiated',
        ),
        throwsA(isA<MigrationStateError>()),
      );
      expect(await persistence.loadActiveDeviceId(), oldDeviceId);
    });

    test('con confirm válida ⇒ revoke + clear active + nota en el ledger',
        () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final service = DeviceMigrationService(persistence: persistence);
      await persistence.saveActiveDeviceId(oldDeviceId);

      await service.revokeActive(
        deviceId: oldDeviceId,
        confirmReason: 'lost',
      );
      expect(await persistence.loadActiveDeviceId(), isNull);
      final revocations = await persistence.loadRevocations();
      expect(revocations, hasLength(1));
      expect(revocations.single.deviceId, oldDeviceId);
      expect(revocations.single.reason, 'lost');
    });
  });

  group('persistence — roundtrip de persistencia tipada', () {
    test('load/save pendings preserves plan/fase/oldActiveDeviceId', () async {
      final persistence = InMemoryDeviceMigrationPersistence();
      final service = DeviceMigrationService(persistence: persistence);

      final p = await service.beginMigration(
        plan: DeviceMigrationPlan.replaceDevice,
        deviceFingerprint: deviceFp,
        oldActiveDeviceId: oldDeviceId,
      );
      final stored = (await persistence.loadPendings()).single;
      expect(stored.id, p.id);
      expect(stored.plan, DeviceMigrationPlan.replaceDevice);
      expect(stored.oldActiveDeviceId, oldDeviceId);
      expect(stored.phase, DeviceMigrationPhase.draft);
      expect(stored.deviceFingerprint, deviceFp);
    });

    test('pending() para id inexistente ⇒ null (no throw en lectura UI)',
        () async {
      final service = DeviceMigrationService(
        persistence: InMemoryDeviceMigrationPersistence(),
      );
      expect(await service.pending('no-existe'), isNull);
    });
  });
}
