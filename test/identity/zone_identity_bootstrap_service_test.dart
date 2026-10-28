/// PHASE 2.2 — Servicio de bootstrap de identidad del producto: tests.
///
/// PRODUCT INTEGRATION SLICE (autorizado CTO 2026-09-25).
///
/// Verifica el contrato del PUNTO ÚNICO de inicialización usado por el boot
/// productivo: idempotencia de la caché (una sola inicialización por sesión),
/// fail-closed sin caché parcial tras fallo (se cierra la instancia y se
/// re-lanza el error tipado), y `context` inaccesible antes de inicializar.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/identity_bootstrap.dart';
import 'package:zone/identity/identity_errors.dart';
import 'package:zone/identity/identity_registry.dart';
import 'package:zone/identity/keys.dart';
import 'package:zone/identity/migration_state_machine.dart';
import 'package:zone/identity/secure_key_store.dart';
import 'package:zone/services/zone_identity_bootstrap_service.dart';

import 'test_doubles.dart';

const String _accountId = '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d';
const String _deviceId = '2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7e';

void main() {
  test('bootstrap() inicializa una sola vez y reutiliza la caché (single path)',
      () async {
    var factoryCalls = 0;
    final backend = InMemoryKeyValueBackend();
    final repo = InMemoryIdentityRepository();
    final service = ZoneIdentityBootstrapService.forTest(
      bootstrapFactory: () async {
        factoryCalls++;
        return makeBootstrap(repo: repo, backend: backend);
      },
    );

    final first = await service.bootstrap();
    expect(service.isInitialized, isTrue);
    expect(factoryCalls, 1);

    final second = await service.bootstrap();
    expect(identical(first, second), isTrue);
    expect(factoryCalls, 1, reason: 'nunca se inicializa dos veces por sesión');
    expect(service.context.accountId, first.accountId);
  });

  test('fail-closed: fallo de inicialización ⇒ rethrow tipado, sin caché '
      'parcial, instancia cerrada y context inaccesible', () async {
    var closed = false;
    final backend = InMemoryKeyValueBackend();
    final repo = InMemoryIdentityRepository();
    final service = ZoneIdentityBootstrapService.forTest(
      bootstrapFactory: () async => IdentityBootstrap(
        registry: IdentityRegistry(
          keyStore: VersionedSecureKeyStore(backend),
          repository: repo,
        ),
        migrationStateReader: () async => MigrationState.legacy,
        onClose: () async {
          closed = true;
        },
      ),
    );

    // Primer arranque OK para que exista metadata sin seed (consistencia rota).
    await service.bootstrap();
    await VersionedSecureKeyStore(backend).deleteSecret(
      const SecretKeyRef(
        scope: 'account',
        purpose: KeyPurpose.accountIdentitySigning,
      ),
    );

    // Simular reinicio de sesión (nuevo proceso/service) sobre almacén dañado.
    final failed = ZoneIdentityBootstrapService.forTest(
      bootstrapFactory: () async => IdentityBootstrap(
        registry: IdentityRegistry(
          keyStore: VersionedSecureKeyStore(backend),
          repository: repo,
        ),
        migrationStateReader: () async => MigrationState.legacy,
        onClose: () async {
          closed = true;
        },
      ),
    );

    await expectLater(
      failed.bootstrap(),
      throwsA(isA<InconsistentIdentityStateError>()),
    );
    expect(failed.isInitialized, isFalse);
    expect(
      () => failed.context,
      throwsA(isA<StateError>()),
    );
    // Fail-closed: la instancia abierta se cerró (no quedan recursos colgados).
    expect(closed, isTrue);
  });
}

/// Bootstrap unitario con dobles y generador determinista (reutiliza la
/// convención del test de `IdentityBootstrap`).
IdentityBootstrap makeBootstrap({
  required InMemoryIdentityRepository repo,
  required InMemoryKeyValueBackend backend,
}) {
  final queue = [_accountId, _deviceId];
  return IdentityBootstrap(
    registry: IdentityRegistry(
      keyStore: VersionedSecureKeyStore(backend),
      repository: repo,
      generateId: () => queue.removeAt(0),
    ),
    migrationStateReader: () async => MigrationState.legacy,
  );
}