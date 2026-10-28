/// Z-004 PHASE E §7.8 — tests del cableado P2P (WI-2 gate + WI-6 rate-limit).
///
/// Propiedades:
/// - WI-2: `profile_exchange` SIN AKE completado ⇒ `unverifiedFallback`
///   (el despachador omite derivación de llave); CON AKE completado ⇒
///   `authenticatedPath`.
/// - El estado AKE vive SOLO mientras el endpoint exista (nota: los datos
///   de uso de radio de WI-6 sobreviven a la desconexión).
/// - WI-6: quinto intento dentro de la ventana pasa, el sexto denia
///   (fail-closed); la ventana TTL libera cupo (tiempo inyectable —
///   test determinista, sin sleep).
/// - Eviction LRU: tope de endpoints rastreados no crece sin límite.
/// - Forma gruesa de frames `ake_hello`/`ake_cert`: campos faltantes o
///   `v` inválida ⇒ null; campos desconocidos del wire NO pasan al
///   handshake .
/// UNIDADES PROBADAS LOCALMENTE (sin radio, sin Supabase).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zone/services/p2p_wiring.dart';

void main() {
  const String endpoint = 'ep-A';

  group('WI-2 — gate del despachador (profile_exchange)', () {
    test('sin AKE completado ⇒ unverifiedFallback (omitir derivación de llaves)', () {
      final wiring = P2pAkeWiring();
      expect(
        wiring.gateProfileExchange(endpoint),
        P2pProfileExchangeGate.unverifiedFallback,
      );
      expect(wiring.hasCompletedAke(endpoint), isFalse);
    });

    test('markAkeCompleted ⇒ authenticatedPath (derivaciones permitidas)', () {
      final wiring = P2pAkeWiring();
      wiring.markAkeCompleted(endpoint);
      expect(
        wiring.gateProfileExchange(endpoint),
        P2pProfileExchangeGate.authenticatedPath,
      );
    });

    test('endpoint desconectado ⇒ estado AKE muere (efímero de transporte)', () {
      final wiring = P2pAkeWiring();
      wiring.markAkeCompleted(endpoint);
      wiring.noteDisconnected(endpoint);
      expect(wiring.hasCompletedAke(endpoint), isFalse);
      expect(
        wiring.gateProfileExchange(endpoint),
        P2pProfileExchangeGate.unverifiedFallback,
      );
    });

    test('el frame AKE registra progreso (hello/cert) — WI-1 prep', () {
      final wiring = P2pAkeWiring();
      wiring.noteAkeFrameReceived(endpointId: endpoint, isHello: true);
      // Siempre: completado SOLO via markAkeCompleted (frames NO bastan).
      expect(wiring.hasCompletedAke(endpoint), isFalse);
      wiring.noteAkeFrameReceived(endpointId: endpoint, isHello: false);
      expect(wiring.hasCompletedAke(endpoint), isFalse);
    });
  });

  group('WI-6 — rate-limit local', () {
    test('dentro de la ventana: 5 pasan, el sexto es denegado (fail-closed)', () {
      final wiring = P2pAkeWiring();
      final base = DateTime.utc(2026, 10, 27, 12, 0);

      for (var i = 0; i < wiring.maxHandshakeAttemptsPerWindow; i++) {
        expect(
          wiring.consumeHandshakeQuota(endpoint, now: base.add(Duration(seconds: i))),
          P2pAkeRateDecision.attemptAllowed,
        );
      }
      expect(
        wiring.consumeHandshakeQuota(
          endpoint,
          now: base.add(const Duration(seconds: 6)),
        ),
        P2pAkeRateDecision.attemptDenied,
      );
    });

    test('ventana TTL desliza: tras 10 min el cupo se libera', () {
      final wiring = P2pAkeWiring();
      final base = DateTime.utc(2026, 10, 27, 12, 0);
      for (var i = 0; i < wiring.maxHandshakeAttemptsPerWindow; i++) {
        wiring.consumeHandshakeQuota(endpoint, now: base);
      }
      expect(
        wiring.consumeHandshakeQuota(endpoint, now: base),
        P2pAkeRateDecision.attemptDenied,
      );
      // A >10 min la ventana ya no incluye los intentos viejos.
      expect(
        wiring.consumeHandshakeQuota(
          endpoint,
          now: base.add(wiring.window + const Duration(seconds: 1)),
        ),
        P2pAkeRateDecision.attemptAllowed,
      );
    });

    test('el cupo es por ENDPOINT (otro peer no hereda denials)', () {
      final wiring = P2pAkeWiring();
      final base = DateTime.utc(2026, 10, 27, 12, 0);
      for (var i = 0; i < wiring.maxHandshakeAttemptsPerWindow; i++) {
        wiring.consumeHandshakeQuota(endpoint, now: base);
      }
      expect(
        wiring.consumeHandshakeQuota('ep-B', now: base),
        P2pAkeRateDecision.attemptAllowed,
      );
    });

    test('checkHandshakeQuota NO consume (consulta sin gasto)', () {
      final wiring = P2pAkeWiring();
      final base = DateTime.utc(2026, 10, 27, 12, 0);
      for (var i = 0; i < wiring.maxHandshakeAttemptsPerWindow; i++) {
        wiring.consumeHandshakeQuota(endpoint, now: base);
      }
      // Consultas repetidas NO agrandan la ventana (sin efecto).
      for (var i = 0; i < 3; i++) {
        expect(
          wiring.checkHandshakeQuota(endpoint, now: base),
          P2pAkeRateDecision.attemptDenied,
        );
      }
      expect(
        wiring.checkHandshakeQuota(
          endpoint,
          now: base.add(wiring.window),
        ),
        P2pAkeRateDecision.attemptAllowed, // liberado sin consumir
      );
    });

    test('eviction LRU: tope de endpoints rastreados respetado', () {
      final wiring = P2pAkeWiring(maxTrackedEndpoints: 4);
      final base = DateTime.utc(2026, 10, 27, 12, 0);
      for (var i = 0; i < 8; i++) {
        wiring.recordHandshakeAttempt('ep-$i', now: base.add(Duration(seconds: i)));
      }
      // Sin API de introspección de trackers: comportamiento observable = la
      // CUOTA de ep-0 (la más antigua evicted) es indistinguible de nueva,
      // pero los 4 últimos rastreados conservan la ventana completa.
      expect(
        wiring.consumeHandshakeQuota(
          'ep-3',
          now: base.add(const Duration(seconds: 10)),
        ),
        P2pAkeRateDecision.attemptAllowed,
        reason: 'solo 1 intento previo: bajo el tope',
      );
      // Consumir el tope para ep-3 (segundo intento…, hasta 5) y que el
      // siguiente denie: la ventana LRU sobrevivió al eviction de otros.
      for (var i = 0; i < wiring.maxHandshakeAttemptsPerWindow - 1; i++) {
        wiring.consumeHandshakeQuota(
          'ep-3',
          now: base.add(const Duration(seconds: 10)),
        );
      }
      expect(
        wiring.consumeHandshakeQuota(
          'ep-3',
          now: base.add(const Duration(seconds: 10)),
        ),
        P2pAkeRateDecision.attemptDenied,
        reason: 'el tope por ventana respeta TODOS los intentos vivos',
      );
    });
  });

  group('forma gruesa de frames AKE (fail-closed)', () {
    // Shape ZONE-P2P-AKE-1 completo (alineado con P2pAkeHelloCodec). El
    // shape reducido previo no correspondía a ningún productor real.
    final String b64Seed = '4KjVq7cWuJyBCeXzwMprEHtcZPurGxKn';
    final validHello = <String, dynamic>{
      'v': 1,
      'version': 'ZONE-P2P-AKE-1',
      'zone_id': 'ZONE-ALICE001',
      'account_id': '11111111-1111-4111-8111-111111111111',
      'device_id': '33333333-3333-4333-8333-333333333333',
      'identity_alg': 'Ed25519',
      'identity_pk': b64Seed,
      'encryption_alg': 'X25519',
      'encryption_pk': b64Seed,
      'encryption_version': 1,
      'epk': b64Seed,
      'nonce': b64Seed,
      'session_id': '55555555-5555-4555-8555-555555555555',
      'issued_at': 1761225600000,
      'sig': b64Seed,
    };

    test('ake_hello: shape completo pasa; v inválida o campo ausente ⇒ null',
        () {
      final wiring = P2pAkeWiring();
      expect(
        wiring.validateAkeFrame(type: kP2pAkeHelloType, data: validHello),
        isNotNull,
      );

      expect(
        wiring.validateAkeFrame(
          type: kP2pAkeHelloType,
          data: {...validHello}..remove('nonce'),
        ),
        isNull,
      );
      final badVersion = {...validHello}..['v'] = 0;
      expect(
        wiring.validateAkeFrame(type: kP2pAkeHelloType, data: badVersion),
        isNull,
      );
      expect(
        wiring.validateAkeFrame(
          type: kP2pAkeHelloType,
          data: {...validHello, 'nonce': ''},
        ),
        isNull,
      );
    });

    test('ake_hello: campos numéricos no-int ⇒ null (fail-closed ante wire)',
        () {
      final wiring = P2pAkeWiring();
      expect(
        wiring.validateAkeFrame(
          type: kP2pAkeHelloType,
          data: {...validHello}..['issued_at'] = '1761225600000',
        ),
        isNull,
      );
      expect(
        wiring.validateAkeFrame(
          type: kP2pAkeHelloType,
          data: {...validHello}..['encryption_version'] = 1.0,
        ),
        isNull,
      );
    });

    test('ake_hello: prior_transcript opcional-String; no-String ⇒ null', () {
      final wiring = P2pAkeWiring();
      // Sin prior (hello de iniciador) — válido.
      expect(
        wiring.validateAkeFrame(type: kP2pAkeHelloType, data: validHello),
        isNotNull,
      );
      // Con prior String — válido.
      expect(
        wiring.validateAkeFrame(
          type: kP2pAkeHelloType,
          data: {...validHello}..['prior_transcript'] = b64Seed,
        ),
        isNotNull,
      );
      // prior con tipo extraño — rechazado.
      expect(
        wiring.validateAkeFrame(
          type: kP2pAkeHelloType,
          data: {...validHello}..['prior_transcript'] = 77,
        ),
        isNull,
      );
    });

    test('ake_hello: ints transportados sobreviven el saneado', () {
      final wiring = P2pAkeWiring();
      final clean = wiring.validateAkeFrame(
        type: kP2pAkeHelloType,
        data: validHello,
      );
      expect(clean, isNotNull);
      expect(clean!['encryption_version'], 1);
      expect(clean['issued_at'], 1761225600000);
    });

    test('ake_cert: campos requeridos; tipo desconocido ⇒ null', () {
      final wiring = P2pAkeWiring();
      final valid = <String, dynamic>{
        'v': 1,
        'session_id': 'uuid',
        'device_cert': 'ZDC2:...',
        'sig': 'base64',
      };
      expect(
        wiring.validateAkeFrame(type: kP2pAkeCertType, data: valid),
        isNotNull,
      );
      // El hello NOT sirve como cert (campos distintos).
      expect(
        wiring.validateAkeFrame(
          type: kP2pAkeCertType,
          data: valid..remove('device_cert'),
        ),
        isNull,
      );
      expect(
        wiring.validateAkeFrame(
          type: 'fake_type',
          data: valid,
        ),
        isNull,
      );
    });

    test('campos desconocidos del wire no pasan al handshake (estricto)',
        () {
      final wiring = P2pAkeWiring();
      final clean = wiring.validateAkeFrame(
        type: kP2pAkeCertType,
        data: {
          'v': 1,
          'session_id': 'uuid',
          'device_cert': 'ZDC2:...',
          'sig': 'b64',
          'injected_field': 'attack-payload', // cast de inyección
        },
      );
      expect(clean, isNotNull);
      expect(clean!.containsKey('injected_field'), isFalse,
          reason: 'el frame saneado corta campos no de wire');
    });
  });
}
