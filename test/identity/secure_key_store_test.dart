/// FASE 2.1 — Almacén seguro de seeds (envelope versionado `zidk1:`).
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Verifica el contrato de `SecureKeyStore` sobre un doble en memoria del
/// backend de `flutter_secure_storage`: envelope canónico, fallos cerrados y
/// tipados (ausente/corrupto/versión errónea), nunca regeneración silenciosa y
/// ausencia de material secreto en mensajes de error.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/identity_errors.dart';
import 'package:zone/identity/keys.dart';
import 'package:zone/identity/secure_key_store.dart';

import 'test_doubles.dart';

SecretKeyRef accountRef() => const SecretKeyRef(
  scope: 'account',
  purpose: KeyPurpose.accountIdentitySigning,
);

void main() {
  late InMemoryKeyValueBackend backend;
  late VersionedSecureKeyStore store;

  setUp(() {
    backend = InMemoryKeyValueBackend();
    store = VersionedSecureKeyStore(backend);
  });

  test(
    'write/read round-trip con envelope `zidk1:` + payload base64',
    () async {
      final seed = List<int>.generate(32, (i) => i);
      await store.writeSecret(accountRef(), seed);
      final stored = backend.snapshot[accountRef().storageKey]!;
      expect(stored, startsWith('$kSecureKeyEnvelopeV1:'));
      final payload = base64Decode(stored.split(':').last);
      expect(payload, seed);
      expect(await store.readSecret(accountRef()), seed);
    },
  );

  test(
    'hasSecret refleja presencia de envelope con versión soportada',
    () async {
      expect(await store.hasSecret(accountRef()), isFalse);
      await store.writeSecret(accountRef(), List.filled(32, 7));
      expect(await store.hasSecret(accountRef()), isTrue);
      await store.deleteSecret(accountRef());
      expect(await store.hasSecret(accountRef()), isFalse);
    },
  );

  test(
    'write con longitud ≠ 32 ⇒ InvalidSeedLengthError (fail-closed)',
    () async {
      await expectLater(
        store.writeSecret(accountRef(), List.filled(31, 0)),
        throwsA(isA<InvalidSeedLengthError>()),
      );
      await expectLater(
        store.writeSecret(accountRef(), List.filled(33, 0)),
        throwsA(isA<InvalidSeedLengthError>()),
      );
    },
  );

  test('lectura ausente ⇒ SecureKeyMissingError y no se regenera', () async {
    await expectLater(
      store.readSecret(accountRef()),
      throwsA(isA<SecureKeyMissingError>()),
    );
  });

  test(
    'envelope de versión no soportada ⇒ SecureKeyVersionMismatchError',
    () async {
      await backend.write(accountRef().storageKey, 'zidk9:AAAA');
      await expectLater(
        store.readSecret(accountRef()),
        throwsA(isA<SecureKeyVersionMismatchError>()),
      );
      // Una versión desconocida NO se considera secreto presente (fail-closed).
      expect(await store.hasSecret(accountRef()), isFalse);
    },
  );

  test('envelope con base64 inválido ⇒ SecureKeyCorruptError', () async {
    await backend.write(accountRef().storageKey, 'zidk1:###not-base64###');
    await expectLater(
      store.readSecret(accountRef()),
      throwsA(isA<SecureKeyCorruptError>()),
    );
  });

  test('payload de longitud incorrecta ⇒ SecureKeyCorruptError', () async {
    await backend.write(
      accountRef().storageKey,
      'zidk1:${base64Encode(List.filled(16, 0))}',
    );
    await expectLater(
      store.readSecret(accountRef()),
      throwsA(isA<SecureKeyCorruptError>()),
    );
  });

  test('borrado por prefijo elimina solo el namespace `zid1.*`', () async {
    await store.writeSecret(accountRef(), List.filled(32, 1));
    await backend.write('private_key', 'legacy-survives');
    await store.deleteByPrefix('$kSecureKeyNamespacePrefix.');
    expect(await store.hasSecret(accountRef()), isFalse);
    expect(await backend.read('private_key'), 'legacy-survives');
  });

  test('los errores tipados no exponen el material secreto (I-004)', () async {
    final seed = List.filled(32, 0x42);
    await store.writeSecret(accountRef(), seed);
    final seedB64 = base64Encode(seed);
    await backend.write(accountRef().storageKey, '$kSecureKeyEnvelopeV1:###');
    try {
      await store.readSecret(accountRef());
      fail('expected SecureKeyCorruptError');
    } on SecureKeyCorruptError catch (e) {
      final rendered = e.toString();
      expect(rendered, isNot(contains(seedB64)));
      expect(rendered, isNot(contains('QkJC')), reason: 'nada del payload');
      expect(
        rendered,
        contains('ref:'),
        reason: 'identificador de ref únicamente',
      );
    }
  });
}
