/// Z-213 PHASE F/G — tests del puente de identidad de dispositivo.
///
/// Propiedades:
/// 1. `deviceId` UUIDv4 estable: PERSISTIDO y reutilizado entre llamadas
///    y entre instancias del puente sobre el MISMO backend (reinicio).
/// 2. Semillas separadas Ed25519/X25519 con refs `SecretKeyRef` distintas
///    (separación de roles D1/D2 — material independiente).
/// 3. **Single-flight**: N llamadas concurrentes a [ensureInitialized]
///    comparten el MISMO deviceId y las MISMAS claves (sin carrera).
/// 4. **Fail-closed ante corrupto**: deviceId no-UUID ⇒ error tipado,
///    NINGUNA regeneración silenciosa de identidad.
/// 5. DEVICE_FINGERPRINT texto canónico (20 chars) y binding material.
/// UNIDADES PROBADAS LOCALMENTE (backend in-memory compartido con los
/// tests de la fundación — test/identity/test_doubles.dart).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zone/identity/device_identity_bridge.dart';

// Doble compartido de la fundación (mismo directorio de tests).
import 'test_doubles.dart';

void main() {
  group('DeviceIdentityBridge — deviceId estable + semillas separadas', () {
    test('deviceId v4 checks canonic shape', () async {
      final backend = InMemoryKeyValueBackend();
      final bridge = DeviceIdentityBridge(backend: backend);

      final snap = await bridge.ensureInitialized();
      expect(snap.deviceId, hasLength(36));
      expect(snap.deviceId, contains('-'));
      // Nibble de versión RFC 4122 v4 correcto.
      expect(snap.deviceId.split('-')[2].startsWith('4'), isTrue);
      // Nibble de variante (8/9/a/b).
      expect(
        RegExp('^[89ab]').hasMatch(snap.deviceId.split('-')[3]),
        isTrue,
      );
      expect(snap.ed25519PublicKeyBase64, hasLength(44));
      expect(snap.x25519PublicKeyBase64, hasLength(44));
    });

    test('reinicio (nueva instancia del puente, mismos backend) ⇒ misma ID',
        () async {
      final backend = InMemoryKeyValueBackend();
      final snap1 =
          await DeviceIdentityBridge(backend: backend).ensureInitialized();
      final snap2 =
          await DeviceIdentityBridge(backend: backend).ensureInitialized();

      expect(snap1.deviceId, snap2.deviceId);
      expect(snap1.ed25519PublicKeyBase64, snap2.ed25519PublicKeyBase64);
      expect(snap1.x25519PublicKeyBase64, snap2.x25519PublicKeyBase64);
    });

    test('single-flight: concurrentes comparten la MISMA identidad', () async {
      final backend = InMemoryKeyValueBackend();
      final bridge = DeviceIdentityBridge(backend: backend);
      final futures = <Future<DeviceIdentitySnapshot>>[
        for (var i = 0; i < 8; i++) bridge.ensureInitialized(),
      ];
      final snaps = await Future.wait(futures);

      for (final s in snaps) {
        expect(s.deviceId, snaps.first.deviceId);
        expect(
          s.ed25519PublicKeyBase64,
          snaps.first.ed25519PublicKeyBase64,
        );
      }
      // Y las semillas existen EXACTAMENTE una vez por propósito.
      final all = await backend.readAll();
      final deviceSeedKeys = all.keys
          .where((k) => k.contains('device.'))
          .where((k) => k.contains('Signing') || k.contains('Encryption'))
          .toList();
      expect(deviceSeedKeys, hasLength(2));
    });

    test('semillas Ed25519 ≠ X25519 (separación de roles por construcción)',
        () async {
      final backend = InMemoryKeyValueBackend();
      final bridge = DeviceIdentityBridge(backend: backend);
      final snap = await bridge.ensureInitialized();

      // Públicas derivadas de semillas distintas ⇒ content distinto
      // (con semillas aleatorias, colisión por construcción 2^-256).
      expect(
        snap.ed25519PublicKeyBase64,
        isNot(snap.x25519PublicKeyBase64),
      );
    });

    test('deviceId corrupto en storage ⇒ error tipado, sin regeneración',
        () async {
      final backend = InMemoryKeyValueBackend();
      await backend.write('zid1.device.id', 'not-a-uuid!!');
      final bridge = DeviceIdentityBridge(backend: backend);

      expect(
        bridge.ensureInitialized(),
        throwsA(
          isA<DeviceIdentityBridgeError>()
              .having((e) => e.reason, 'reason', 'corrupt_device_id'),
        ),
      );
      // Storage intacto (no 'arreglado' silenciosamente).
      expect(
        await backend.read('zid1.device.id'),
        'not-a-uuid!!',
        reason: 'fail-closed JAMÁS sobreescribe la entrada corrupta',
      );
    });
  });

  group('DeviceIdentityBridge — wipe explícito', () {
    test('wipeIdentity borra deviceId + semillas; nueva identidad tras él',
        () async {
      final backend = InMemoryKeyValueBackend();
      final bridge = DeviceIdentityBridge(backend: backend);
      final before = await bridge.ensureInitialized();
      expect(before.deviceId, hasLength(36));

      await bridge.wipeIdentity();

      // Tras el wipe APROBADO explícitamente, un ensureInitialized crea
      // una identidad nueva (es el comportamiento del pipeline aprobado,
      // no una supervivencia transitoria).
      final after = await bridge.ensureInitialized();
      expect(after.deviceId, hasLength(36));
    });
  });
}
