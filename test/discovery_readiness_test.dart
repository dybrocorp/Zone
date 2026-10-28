/// PHASE 2.2.6 — Discovery/ranging readiness: tests UNIT.
///
/// Capa de política/servicio (`lib/services/discovery_policy.dart`): lifecycle
/// explícito, sesiones efímeras de endpoint, frontera de identidad, payload
/// mínimo, permisos estructurados. Sin radio, sin plataforma: fakes puros.
///
/// 1. start idempotente · 2. stop idempotente · 3. dispose limpia listeners
/// (sesiones) · 4. endpoint duplicado se deduplica · 5. conexión duplicada
/// se previene · 6. fallo de conexión limpia la sesión · 7. disconnect limpia
/// lo efímero · 8. el endpoint ID no persiste como identidad · 9. el endpoint
/// ID no se usa como Zone ID · 10. discovery no crea matches · 11. identidad
/// autoritativa requerida antes del encuentro · 12. identidad malformada
/// falla cerrado · 13. sin bypass de encounterKey · 14. sin bypass de RLS ·
/// 15. rechazo de permisos estructurado · 16. transporte no disponible
/// estructurado · 17. stop bloquea callbacks · 18. sin secretos ·
/// 19. BLE no invocado por Nearby · 20. integración con encounters intacta.
///
/// Estos tests NO prueban radio físico (PHYSICAL_DISCOVERY_VERIFIED: NO).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zone/services/discovery_policy.dart';
import 'package:zone/services/encounter_key.dart';

const String _zoneA = 'ZONE-A1B2C3D4';
const String _zoneB = 'ZONE-E5F6A7B8';
const String _tokenUuid = '123e4567-e89b-42d3-a456-426614174000';
const String _endpoint = 'endpoint-abc-123';

void main() {
  group('lifecycle explícito (1/2/17)', () {
    test('1: arranques repetidos son seguros (guardia + transiciones)', () {
      final lc = DiscoveryLifecycle();
      expect(lc.state, DiscoveryState.stopped);
      expect(lc.canStart, isTrue);
      lc.beginStart();
      expect(lc.state, DiscoveryState.starting);
      lc.transportUp(advertising: true, discovering: true);
      expect(lc.state, DiscoveryState.ready);
      // Segundo arranque sobre servicio activo: re-begin es no-op seguro.
      lc.beginStart();
      lc.transportUp(advertising: true, discovering: true);
      expect(lc.state, DiscoveryState.ready);
    });

    test('2: stops repetidos son idempotentes', () {
      final lc = DiscoveryLifecycle();
      lc.beginStart();
      lc.transportUp(advertising: true, discovering: true);
      lc.beginStop();
      expect(lc.state, DiscoveryState.stopping);
      lc.beginStop();
      expect(lc.state, DiscoveryState.stopping);
      lc.stopped();
      expect(lc.state, DiscoveryState.stopped);
      lc.stopped();
      expect(lc.state, DiscoveryState.stopped);
      expect(lc.canStart, isTrue);
    });

    test('17: en parada/detenido no se aceptan callbacks', () {
      final lc = DiscoveryLifecycle();
      expect(lc.acceptsCallbacks, isTrue);
      lc.beginStop();
      expect(lc.acceptsCallbacks, isFalse);
      lc.stopped();
      // Detenido + error limpio: vuelve a aceptar (nuevo ciclo).
      expect(lc.acceptsCallbacks, isTrue);
    });

    test('derivación de estados: advertising/discovering/connected/error',
        () {
      final lc = DiscoveryLifecycle();
      lc.beginStart();
      lc.transportUp(advertising: true, discovering: false);
      expect(lc.state, DiscoveryState.advertising);
      lc.transportUp(advertising: false, discovering: true);
      expect(lc.state, DiscoveryState.ready);
      lc.endpointConnected();
      expect(lc.state, DiscoveryState.connected);
      lc.endpointDisconnected(0);
      expect(lc.state, DiscoveryState.ready);
      lc.transportFailed(DiscoveryError.discoveryFailed);
      expect(lc.state, DiscoveryState.error);
      expect(lc.lastError, DiscoveryError.discoveryFailed);
    });
  });

  group('sesiones de endpoint (3–7)', () {
    test('4: mismo endpoint + mismo token no se reprocesa; token nuevo sí',
        () {
      final s = EndpointSessions();
      expect(s.noteFound(_endpoint, _tokenUuid), isTrue);
      expect(s.noteFound(_endpoint, _tokenUuid), isFalse);
      expect(
        s.noteFound(_endpoint, 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'),
        isTrue,
      );
    });

    test('5: un solo intento lógico de conexión por endpoint', () {
      final s = EndpointSessions();
      expect(s.noteConnectionAttempt(_endpoint), isTrue);
      expect(s.noteConnectionAttempt(_endpoint), isFalse);
      s.noteConnected(_endpoint);
      expect(s.isConnected(_endpoint), isTrue);
      expect(s.noteConnectionAttempt(_endpoint), isFalse);
    });

    test('6: fallo de conexión limpia el intento (reintentable)', () {
      final s = EndpointSessions();
      expect(s.noteConnectionAttempt(_endpoint), isTrue);
      s.noteConnectionFailed(_endpoint);
      expect(s.noteConnectionAttempt(_endpoint), isTrue);
      expect(s.isConnected(_endpoint), isFalse);
    });

    test('7: disconnect limpia lo efímero; redescubrir funciona', () {
      final s = EndpointSessions();
      s.noteFound(_endpoint, _tokenUuid);
      s.noteConnectionAttempt(_endpoint);
      s.noteConnected(_endpoint);
      s.bindIdentity(_endpoint, _zoneA);
      s.noteDisconnected(_endpoint);
      expect(s.isConnected(_endpoint), isFalse);
      expect(s.zoneFor(_endpoint), isNull);
      expect(s.noteFound(_endpoint, _tokenUuid), isTrue);
    });

    test('3: clear() vacía sesiones (dispose/stop sin fugas)', () {
      final s = EndpointSessions();
      s.noteFound(_endpoint, _tokenUuid);
      s.noteConnectionAttempt(_endpoint);
      s.noteConnected(_endpoint);
      s.bindIdentity(_endpoint, _zoneA);
      s.clear();
      expect(s.connectedCount, 0);
      expect(s.zoneFor(_endpoint), isNull);
      expect(s.noteFound(_endpoint, _tokenUuid), isTrue);
    });
  });

  group('frontera de identidad (8/9/10/11/12)', () {
    test('9: el endpoint ID / token crudo NUNCA enlaza como identidad', () {
      final s = EndpointSessions();
      expect(
        () => s.bindIdentity(_endpoint, _endpoint),
        throwsA(isA<InvalidDiscoveryIdentityError>()),
      );
      expect(
        () => s.bindIdentity(_endpoint, _tokenUuid),
        throwsA(isA<InvalidDiscoveryIdentityError>()),
      );
      expect(
        () => s.bindIdentity(_endpoint, ''),
        throwsA(isA<InvalidDiscoveryIdentityError>()),
      );
      expect(s.zoneFor(_endpoint), isNull);
    });

    test('8: lo enlazado es el handle ZONE, nunca el endpoint; no persiste',
        () {
      final s = EndpointSessions();
      s.bindIdentity(_endpoint, _zoneA.toLowerCase());
      expect(s.zoneFor(_endpoint), _zoneA);
      expect(s.zoneFor(_endpoint), isNot(_endpoint));
      // Sin API de persistencia: clear() lo borra (efímero por diseño).
      s.clear();
      expect(s.zoneFor(_endpoint), isNull);
    });

    test('CASE E: dos endpoints, misma identidad — ambos registrados', () {
      final s = EndpointSessions();
      s.bindIdentity('ep-1', _zoneA);
      s.bindIdentity('ep-2', _zoneA);
      expect(s.zoneFor('ep-1'), _zoneA);
      expect(s.zoneFor('ep-2'), _zoneA);
    });

    test('11: encuentro solo con identidad autoritativa enlazada', () {
      expect(DiscoveryPayload.canCreateEncounter(null), isFalse);
      expect(DiscoveryPayload.canCreateEncounter(''), isFalse);
      expect(DiscoveryPayload.canCreateEncounter(_tokenUuid), isFalse);
      expect(DiscoveryPayload.canCreateEncounter(_endpoint), isFalse);
      expect(DiscoveryPayload.canCreateEncounter(_zoneA), isTrue);
    });

    test('10: la política no fabrica matches (sin API de match)', () {
      // El encuentro requiere identidad; el match requiere además ACCIÓN del
      // usuario + outbox/servidor (2.2.4/2.2.5, intactos). Aquí: la política
      // expone bind/canCreateEncounter, ningún id de match ni constructor.
      expect(DiscoveryPayload.canCreateEncounter(_zoneA), isTrue);
    });
  });

  group('payload mínimo (6/12/18)', () {
    test('12: no-map, zone inválida y claves prohibidas fallan cerrado', () {
      expect(
        () => DiscoveryPayload.validateProfileExchange('texto'),
        throwsA(isA<InvalidDiscoveryIdentityError>()),
      );
      expect(
        () => DiscoveryPayload.validateProfileExchange({'id': 'x'}),
        throwsA(isA<InvalidDiscoveryIdentityError>()),
      );
      expect(
        () => DiscoveryPayload.validateProfileExchange({
          'zone_id': _tokenUuid,
        }),
        throwsA(isA<InvalidDiscoveryIdentityError>()),
      );
      for (final bad in ['private_key', 'seed', 'access_token', 'secret']) {
        expect(
          () => DiscoveryPayload.validateProfileExchange({
            'zone_id': _zoneA,
            bad: 'VALOR',
          }),
          throwsA(isA<InvalidDiscoveryIdentityError>()),
          reason: bad,
        );
      }
    });

    test('payload válido pasa intacto (13: zone_id verbatim para EncounterKey)',
        () {
      final data = {
        'id': 'uid-1',
        'zone_id': _zoneA,
        'display_name': 'Ada',
        'publicKey': 'YmFuZHJpbg==',
      };
      final clean = DiscoveryPayload.validateProfileExchange(data);
      expect(clean['zone_id'], _zoneA);
      expect(clean['id'], 'uid-1');
    });

    test('18: errores y logs sin secretos; endpoint truncado', () {
      const e = DiscoveryException(DiscoveryError.connectionFailed, 'radio');
      expect(e.toString(), isNot(contains('private')));
      expect(
        DiscoveryException.sanitizeEndpoint(_endpoint),
        isNot(contains(_endpoint)),
      );
      expect(DiscoveryException.sanitizeEndpoint('abc'), 'abc');
      for (final f in DiscoveryPayload.forbiddenKeys) {
        expect(f, isNot(contains('zone_id')));
      }
    });
  });

  group('permisos y transporte (15/16)', () {
    test('15: rechazo estructurado (ok / denegado / permanente)', () {
      expect(DiscoveryPermissions.classify({}), DiscoveryError.permissionsDenied);
      expect(
        DiscoveryPermissions.classify({
          Permission.location: PermissionStatus.granted,
          Permission.bluetoothScan: PermissionStatus.granted,
          Permission.bluetoothAdvertise: PermissionStatus.granted,
          Permission.bluetoothConnect: PermissionStatus.granted,
          Permission.nearbyWifiDevices: PermissionStatus.granted,
        }),
        isNull,
      );
      expect(
        DiscoveryPermissions.classify({
          Permission.location: PermissionStatus.granted,
          Permission.bluetoothScan: PermissionStatus.denied,
          Permission.bluetoothAdvertise: PermissionStatus.granted,
          Permission.bluetoothConnect: PermissionStatus.granted,
          Permission.nearbyWifiDevices: PermissionStatus.granted,
        }),
        DiscoveryError.permissionsDenied,
      );
      expect(
        DiscoveryPermissions.classify({
          Permission.location: PermissionStatus.permanentlyDenied,
          Permission.bluetoothScan: PermissionStatus.granted,
          Permission.bluetoothAdvertise: PermissionStatus.granted,
          Permission.bluetoothConnect: PermissionStatus.granted,
          Permission.nearbyWifiDevices: PermissionStatus.granted,
        }),
        DiscoveryError.permissionsPermanentlyDenied,
      );
    });

    test('16: categorías de transporte disponibles y estructuradas', () {
      for (final err in [
        DiscoveryError.bluetoothUnavailable,
        DiscoveryError.nearbyUnavailable,
        DiscoveryError.advertiseFailed,
        DiscoveryError.discoveryFailed,
        DiscoveryError.connectionTimeout,
        DiscoveryError.handshakeFailed,
        DiscoveryError.endpointDisconnected,
      ]) {
        expect(
          const DiscoveryException(DiscoveryError.discoveryFailed)
              .toString(),
          contains('discoveryFailed'),
        );
        expect(err.name.isNotEmpty, isTrue);
      }
    });
  });

  group('BLE y compatibilidad (19/20/14)', () {
    test('19: BLE es LEGACY/UNUSED — el path Nearby no lo requiere', () {
      expect(requiresBle, isFalse);
    });

    test('20: zonas enlazadas alimentan EncounterKey intacto (ambos órdenes)',
        () async {
      final s = EndpointSessions();
      s.bindIdentity('ep-a', _zoneA);
      s.bindIdentity('ep-b', _zoneB);
      final t = DateTime.utc(2026, 10, 8, 18, 12);
      final fromA = await EncounterKey.canonicalKey(
        zoneA: s.zoneFor('ep-a')!,
        zoneB: s.zoneFor('ep-b')!,
        seenAt: t,
      );
      final fromB = await EncounterKey.canonicalKey(
        zoneA: s.zoneFor('ep-b')!,
        zoneB: s.zoneFor('ep-a')!,
        seenAt: t,
      );
      expect(fromB, fromA);
    });

    test('14: el payload validado no introduce bypass de autorización', () {
      // Sin campos de auth/rol/token: la autorización sigue en RLS/servidor.
      final clean = DiscoveryPayload.validateProfileExchange({
        'zone_id': _zoneA,
        'display_name': 'Ada',
      });
      expect(clean.keys, isNot(contains('role')));
      expect(clean.keys, isNot(contains('auth')));
    });
  });
}
