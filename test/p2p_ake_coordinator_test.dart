/// Z-004 PHASE E/G — INTEGRACIÓN del cableado REAL del handshake
/// `ZONE-P2P-AKE-1` (coordinador `lib/services/p2p_ake_coordinator.dart`).
///
/// Coordinadores REALES intercambian frames vía un transporte en memoria
/// (`_Tape`). Criptografía REAL: Ed25519, X25519, HKDF-SHA256 y
/// ChaCha20-Poly1305. Sin mocks de cripto, sin plugin nativo, sin
/// `NearbyService` (el despachador queda cubierto por el test de contrato
/// de fuente y por `p2p_wiring_test.dart`).
///
/// ALCANCE HONESTO: estas son pruebas SIMULADAS (transporte en memoria).
/// La demo física entre dos dispositivos (H-01…H-15) sigue NOT RUN.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/ed25519_identity_service.dart';
import 'package:zone/identity/x25519_device_service.dart';
import 'package:zone/services/p2p_ake_coordinator.dart';
import 'package:zone/services/p2p_auth_policy.dart';
import 'package:zone/services/p2p_handshake_session.dart';

const String _endpoint = 'ep-AB';
const String _endpointM = 'ep-M';

const String _zoneA = 'ZONE-ALICE001';
const String _zoneB = 'ZONE-BOB00002';
const String _zoneM = 'ZONE-MAL00003';
const String _accountA = '11111111-1111-4111-8111-111111111111';
const String _accountB = '22222222-2222-4222-8222-222222222222';
const String _accountM = '99999999-9999-4999-8999-999999999999';
const String _deviceA = '33333333-3333-4333-8333-333333333333';
const String _deviceB = '44444444-4444-4444-8444-444444444444';
const String _deviceM = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

/// Transporte en memoria por caja: `send(to, frame)` deja el frame en la
/// caja del peer destino; [deliver] lo entrega al coordinador destino y
/// procesa el outcome. [dropNext] simula pérdida de radio determinista.
class _Tape {
  final Map<String, List<Map<String, dynamic>>> _boxes =
      <String, List<Map<String, dynamic>>>{};

  /// El PRÓXIMO `send` se pierde (el emisor cree que fue entregado — igual
  /// que `sendBytesPayload` puede fallar silencioso por radio).
  bool dropNext = false;

  /// Resultado del ÚLTIMO `onPeerHello` procesado en [deliver], por peer.
  final Map<String, P2pAkeHelloOutcome?> lastOutcome =
      <String, P2pAkeHelloOutcome?>{};

  Future<bool> send(String toPeer, Map<String, dynamic> frame) async {
    if (dropNext) {
      dropNext = false;
      return true;
    }
    (_boxes[toPeer] ??= <Map<String, dynamic>>[]).add(frame);
    return true;
  }

  List<Map<String, dynamic>> pending(String peer) =>
      List<Map<String, dynamic>>.unmodifiable(
        _boxes[peer] ?? const <Map<String, dynamic>>[],
      );

  void clear(String peer) => _boxes.remove(peer);

  /// Entrega TODOS los frames pendientes del peer a su coordinador.
  Future<void> deliver(_TestPeer peer, String endpointId) async {
    final box = _boxes.remove(peer.name);
    if (box == null) return;
    for (final frame in box) {
      if (frame['type'] != 'ake_hello') continue;
      final outcome = await peer.coordinator.onPeerHello(
        endpointId,
        Map<String, dynamic>.from(frame['data'] as Map),
      );
      lastOutcome[peer.name] = outcome;
    }
  }
}

/// Peer de prueba: identidad REAL (seeds fijas → pares fundacionales) +
/// coordinador REAL + su caja de transporte.
class _TestPeer {
  _TestPeer._(
    this.name,
    this.material,
    this.tape,
    this.destinationPeer, {
    this.routes = const <String, String>{},
    Future<P2pAkeIdentityMaterial?> Function()? identityLoader,
  }) : _identityLoaderOverride = identityLoader;

  final String name;
  final P2pAkeIdentityMaterial material;
  final _Tape tape;

  /// Nombre del peer destino POR DEFECTO para frames ENVIADOS por este nodo.
  final String destinationPeer;

  /// Ruta específica por endpoint: `endpointId → peer destino`. En radio real
  /// la respuesta vuelve por la MISMA conexión (endpoint); esto reproduce eso
  /// sin acoplar el harness a una topología fija.
  final Map<String, String> routes;

  String _routeTo(String endpointId) =>
      routes[endpointId] ?? destinationPeer;

  final Future<P2pAkeIdentityMaterial?> Function()? _identityLoaderOverride;

  final Map<String, P2PSessionKeyMaterial> settled =
      <String, P2PSessionKeyMaterial>{};

  /// Cupo WI-6 análogo al wiring real (5 por ventana).
  int quotaLeft = 5;
  bool quotaOpen = true;

  P2pAkeCoordinator? _coordinator;

  P2pAkeCoordinator get coordinator =>
      _coordinator ??= P2pAkeCoordinator(
        identityLoader: _identityLoaderOverride ?? (() async => material),
        frameSender: (endpointId, frame) =>
            tape.send(_routeTo(endpointId), frame),
        quotaGate: (endpointId) {
          if (!quotaOpen || quotaLeft <= 0) return false;
          quotaLeft--;
          return true;
        },
        keyMaterialListener: (endpointId, m) => settled[endpointId] = m,
        settlementWait: const Duration(seconds: 30),
      );

  P2pAkeChannel? channel(String endpointId) => coordinator.channel(endpointId);

  static Future<_TestPeer> create({
    required String name,
    required String zoneId,
    required String accountId,
    required String deviceId,
    required List<int> identitySeed,
    required List<int> encryptionSeed,
    required String destinationPeer,
    _Tape? tape,
    Map<String, String> routes = const <String, String>{},
    Future<P2pAkeIdentityMaterial?> Function()? identityLoader,
  }) async {
    return _TestPeer._(
      name,
      P2pAkeIdentityMaterial(
        zoneId: zoneId,
        accountId: accountId,
        deviceId: deviceId,
        identityKeyPair: await Ed25519IdentityService.keyPairFromSeed(
          identitySeed,
        ),
        encryptionKeyPair: await X25519DeviceEncryptionService.keyPairFromSeed(
          encryptionSeed,
        ),
        encryptionKeyVersion: 1,
      ),
      tape ?? _Tape(),
      destinationPeer,
      routes: routes,
      identityLoader: identityLoader,
    );
  }
}

Future<(_TestPeer, _TestPeer)> _peers(
  _Tape tape, {
  String? aZone,
  Map<String, String> bRoutes = const <String, String>{},
}) async {
  final a = await _TestPeer.create(
    name: 'A',
    zoneId: aZone ?? _zoneA,
    accountId: _accountA,
    deviceId: _deviceA,
    identitySeed: List<int>.generate(32, (i) => i),
    encryptionSeed: List<int>.generate(32, (i) => 255 - i),
    destinationPeer: 'B',
    tape: tape,
  );
  final b = await _TestPeer.create(
    name: 'B',
    zoneId: _zoneB,
    accountId: _accountB,
    deviceId: _deviceB,
    identitySeed: List<int>.generate(32, (i) => (i * 7 + 1) & 0xff),
    encryptionSeed: List<int>.generate(32, (i) => (i * 11 + 3) & 0xff),
    destinationPeer: 'A',
    tape: tape,
    routes: bRoutes,
  );
  return (a, b);
}

/// Handshake estándar: A autostart (iniciador), B passivo (responder).
Future<(_TestPeer, _TestPeer)> _handshakeStandard(
  _Tape tape, {
  String? aZone,
  Map<String, String> bRoutes = const <String, String>{},
}) async {
  final (a, b) = await _peers(tape, aZone: aZone, bRoutes: bRoutes);
  expect(await a.coordinator.onConnected(_endpoint), isTrue);
  await tape.deliver(b, _endpoint);
  await tape.deliver(a, _endpoint);
  return (a, b);
}

void main() {
  test('handshake estándar: ambos lados derivan la MISMA clave de sesión',
      () async {
    final tape = _Tape();
    final (a, b) = await _handshakeStandard(tape);

    expect(a.settled[_endpoint], isNotNull);
    expect(b.settled[_endpoint], isNotNull);
    expect(a.coordinator.hasCompletedAkeFor(_endpoint), isTrue);
    expect(b.coordinator.hasCompletedAkeFor(_endpoint), isTrue);
    expect(
      a.settled[_endpoint]!.keyBytes,
      equals(b.settled[_endpoint]!.keyBytes),
    );
    expect(a.settled[_endpoint]!.keyBytes.length, 32);
    expect(
      a.settled[_endpoint]!.transcriptHash,
      equals(b.settled[_endpoint]!.transcriptHash),
    );
    expect(
      a.settled[_endpoint]!.initiatorSessionId,
      isNot(equals(a.settled[_endpoint]!.responderSessionId)),
    );
  });

  test('canal protegido: frames cruzan solo entre sesiones enlazadas',
      () async {
    final tape = _Tape();
    final (a, b) = await _handshakeStandard(tape);

    final chA = a.channel(_endpoint);
    final chB = b.channel(_endpoint);
    expect(chA, isNotNull);
    expect(chB, isNotNull);

    // A → B
    final msgAB = await chA!.seal(utf8.encode('hola B protegido'));
    final plainAB = await chB!.open(Uint8List.fromList(msgAB));
    expect(utf8.decode(plainAB), 'hola B protegido');

    // B → A
    final msgBA = await chB.seal(utf8.encode('hola A protegido'));
    final plainBA = await chA.open(Uint8List.fromList(msgBA));
    expect(utf8.decode(plainBA), 'hola A protegido');

    // Replay del MISMO frame entrante ⇒ rechazado (seq monótono por lado).
    await expectLater(
      chB.open(Uint8List.fromList(msgAB)),
      throwsA(
        isA<P2pAkeChannelError>().having(
          (e) => e.reason,
          'reason',
          'replayed_or_out_of_order',
        ),
      ),
    );

    // Manipulación del ciphertext ⇒ decrypt_failed (fail-closed). Frame
    // FRESCO (libre de consumo replay-previo): B sella, se altera un byte y
    // A intenta abrirlo. El tag del emisor ('r') es correcto ⇒ fallo en MAC.
    final freshB = await chB.seal(utf8.encode('para manipular'));
    final tampered = Uint8List.fromList(freshB);
    tampered[12] ^= 0x40;
    await expectLater(
      chA.open(tampered),
      throwsA(
        isA<P2pAkeChannelError>().having(
          (e) => e.reason,
          'reason',
          'decrypt_failed',
        ),
      ),
    );

    // Rol del emisor invertido ⇒ invalid_sender_role (tag del AAD). Otro
    // frame fresco de B ('r') con el byte de rol cambiado a 'i'.
    final freshB2 = await chB.seal(utf8.encode('para flip de rol'));
    final roleFlipped = Uint8List.fromList(freshB2);
    roleFlipped[8] = 0x69; // 'i'
    await expectLater(
      chA.open(roleFlipped),
      throwsA(
        isA<P2pAkeChannelError>().having(
          (e) => e.reason,
          'reason',
          'invalid_sender_role',
        ),
      ),
    );

    // Frame corto ⇒ frame_too_short.
    await expectLater(
      chA.open(Uint8List(10)),
      throwsA(
        isA<P2pAkeChannelError>().having(
          (e) => e.reason,
          'reason',
          'frame_too_short',
        ),
      ),
    );
  });

  test('reordenación descendente se rechaza (anti-replay RX)', () async {
    final tape = _Tape();
    final (a, b) = await _handshakeStandard(tape);
    final chA = a.channel(_endpoint)!;
    final chB = b.channel(_endpoint)!;

    final seq1 = await chA.seal(utf8.encode('uno'));
    final seq2 = await chA.seal(utf8.encode('dos'));

    // B abre el seq2 PRIMERO (adelantado: permitido). El seq1 posterior es
    // retroceso ⇒ rechazado.
    await chB.open(Uint8List.fromList(seq2));
    await expectLater(
      chB.open(Uint8List.fromList(seq1)),
      throwsA(
        isA<P2pAkeChannelError>().having(
          (e) => e.reason,
          'reason',
          'replayed_or_out_of_order',
        ),
      ),
    );
  });

  test('firma manipulada del hello ⇒ rechazo del policy (sin derivación)',
      () async {
    final tape = _Tape();
    final (a, b) = await _peers(tape);
    expect(await a.coordinator.onConnected(_endpoint), isTrue);

    final frame = tape.pending('B').single;
    final data = Map<String, dynamic>.from(frame['data'] as Map);
    // Firma sustituida por ZEROS de 64 bytes (mismo shape; otra firma).
    data['sig'] = base64Encode(Uint8List(64));

    final outcome = await b.coordinator.onPeerHello(_endpoint, data);
    expect(outcome.accepted, isFalse);
    expect(
      outcome.rejection!.reason,
      P2PAuthRejectReason.invalidSignature,
    );
    expect(b.coordinator.hasCompletedAkeFor(_endpoint), isFalse);
    expect(b.settled[_endpoint], isNull);
    expect(b.channel(_endpoint), isNull, reason: 'sin AKE NO hay canal');
  });

  test('hello fuera de TTL ⇒ staleHandshake y sin canal', () async {
    final tape = _Tape();
    final (a, b) = await _peers(tape);
    expect(await a.coordinator.onConnected(_endpoint), isTrue);

    final frame = tape.pending('B').single;
    tape.clear('B');
    final lateNow = DateTime.now().toUtc().add(const Duration(minutes: 3));
    final outcome = await b.coordinator.onPeerHello(
      _endpoint,
      Map<String, dynamic>.from(frame['data'] as Map),
      nowOverride: lateNow,
    );
    expect(outcome.accepted, isFalse);
    expect(outcome.rejection!.reason, P2PAuthRejectReason.staleHandshake);
    expect(b.channel(_endpoint), isNull);
    // A nunca recibió respuesta: su pista sigue sin settle (fail-closed).
    expect(a.coordinator.hasCompletedAkeFor(_endpoint), isFalse);
  });

  test('conflicto simultáneo: ambos derivan la MISMA clave (selección min)',
      () async {
    final tape = _Tape();
    final (a, b) = await _peers(tape);

    // AMBOS creen ser iniciador (la conexión reportó OK en los dos lados).
    expect(await a.coordinator.onConnected(_endpoint), isTrue);
    expect(await b.coordinator.onConnected(_endpoint), isTrue);

    // El hello de A llega a B (B ya autoenvió el suyo) → fork responder en B.
    await tape.deliver(b, _endpoint);
    // El hello de B llega a A (A ya autoenvió) → fork responder en A.
    await tape.deliver(a, _endpoint);
    // Los PRIORED cruzan: la pista iniciador de cada lado resulta terminal.
    await tape.deliver(b, _endpoint);
    await tape.deliver(a, _endpoint);

    expect(a.coordinator.hasCompletedAkeFor(_endpoint), isTrue);
    expect(b.coordinator.hasCompletedAkeFor(_endpoint), isTrue);
    expect(
      a.settled[_endpoint]!.transcriptHash,
      equals(b.settled[_endpoint]!.transcriptHash),
      reason: 'la selección min del transcript converge en ambos lados',
    );
    expect(
      a.settled[_endpoint]!.keyBytes,
      equals(b.settled[_endpoint]!.keyBytes),
    );

    final chA = a.channel(_endpoint)!;
    final chB = b.channel(_endpoint)!;
    final msgAB = await chA.seal(utf8.encode('conflicto A-B'));
    final plain = await chB.open(Uint8List.fromList(msgAB));
    expect(utf8.decode(plain), 'conflicto A-B');
  });

  test('pérdida de la respuesta del responder ⇒ settle asimétrico fail-closed',
      () async {
    // Escenario radiorealista: A autostart (iniciador), B passivo (responder).
    // La RESPUESTA priored de B se pierde en radio: B completa (recibió el
    // hello de A), A jamás recibe respuesta ⇒ sin candidatos ⇒ sin settle y
    // SIN canal (fail-closed). La sesión huérfana envía frames que el peer
    // no puede abrir ⇒ el intercambio protegido nunca ocurre a medias.
    final tape = _Tape();
    final (a, b) = await _peers(tape);

    expect(await a.coordinator.onConnected(_endpoint), isTrue);
    tape.dropNext = true; // la respuesta priored del responder se pierde
    await tape.deliver(b, _endpoint);

    // B completó su pista responder con UN candidato: settle posible al
    // expirar (o inmediato aquí: sin pista iniciador, el settle es directo).
    expect(b.coordinator.hasCompletedAkeFor(_endpoint), isTrue);

    // A no recibió NADA: sin candidatos ⇒ sin settle ⇒ SIN canal.
    await a.coordinator.expirePendingSettlement(_endpoint);
    expect(a.coordinator.hasCompletedAkeFor(_endpoint), isFalse);
    expect(a.channel(_endpoint), isNull);
  });

  test('identidad no lista (bootstrap pendiente) ⇒ fail-closed sin frames',
      () async {
    final tape = _Tape();
    final a = await _TestPeer.create(
      name: 'A',
      zoneId: _zoneA,
      accountId: _accountA,
      deviceId: _deviceA,
      identitySeed: List<int>.generate(32, (i) => i),
      encryptionSeed: List<int>.generate(32, (i) => 255 - i),
      destinationPeer: 'B',
      tape: tape,
      identityLoader: () async => null,
    );
    expect(await a.coordinator.onConnected(_endpoint), isFalse);
    expect(tape.pending('B'), isEmpty, reason: 'nada se firma sin identidad');
  });

  test('zone_id no canónico ⇒ fail-closed (no firma, no envía)', () async {
    final tape = _Tape();
    final (a, _) = await _peers(tape, aZone: 'ZONE-SHORTX9');
    expect(await a.coordinator.onConnected(_endpoint), isFalse);
    expect(tape.pending('B'), isEmpty);
  });

  test('cupo WI-6 agotado ⇒ no envía hello ni responde', () async {
    final tape = _Tape();
    final (a, _) = await _peers(tape);
    a.quotaLeft = 0;
    expect(await a.coordinator.onConnected(_endpoint), isFalse);
    expect(tape.pending('B'), isEmpty);
  });

  test('transcripts distintos NO cruzan canales (binding de transcript)',
      () async {
    // Sesión legítima A ↔ B en 'ep-AB'; por separado, Mallory ↔ B en 'ep-M'
    // (TOFU de primer contacto, documentado). El frame de M usa OTRO
    // transcript ⇒ NO se abre en el canal de A↔B. B necesita una ruta
    // separada para responder a M por "su" conexión (ep-M).
    final tape = _Tape();
    final (a, b) = await _handshakeStandard(tape, bRoutes: {_endpointM: 'M'});
    final hashBefore = b.settled[_endpoint]!.transcriptHash;

    final mallory = await _TestPeer.create(
      name: 'M',
      zoneId: _zoneM,
      accountId: _accountM,
      deviceId: _deviceM,
      identitySeed: List<int>.generate(32, (i) => (i * 17 + 7) & 0xff),
      encryptionSeed: List<int>.generate(32, (i) => (i * 19 + 9) & 0xff),
      destinationPeer: 'B',
      tape: tape,
    );
    expect(await mallory.coordinator.onConnected(_endpointM), isTrue);
    await tape.deliver(b, _endpointM);
    await tape.deliver(mallory, _endpointM);
    expect(b.coordinator.hasCompletedAkeFor(_endpointM), isTrue);
    // La sesión A↔B NO fue perturbada (cada endpoint = estado propio).
    expect(
      b.settled[_endpoint]!.transcriptHash,
      equals(hashBefore),
    );

    final chM = mallory.channel(_endpointM)!;
    final chA = a.channel(_endpoint)!;
    final chB = b.channel(_endpoint)!;
    final evil = await chM.seal(utf8.encode('inyección cross-transcript'));

    // B (responder en ep-AB, canal DISTINTO del transcript de M): el tag de
    // rol coincide ('i') pero la MAC No — el AAD/clave de M no aplica aquí ⇒
    // decrypt_failed (→ PROBADO el binding de transcript).
    await expectLater(
      chB.open(Uint8List.fromList(evil)),
      throwsA(
        isA<P2pAkeChannelError>().having(
          (e) => e.reason,
          'reason',
          'decrypt_failed',
        ),
      ),
    );

    // A (iniciador en ep-AB): rechazo aún más temprano por rol del emisor.
    await expectLater(
      chA.open(Uint8List.fromList(evil)),
      throwsA(
        isA<P2pAkeChannelError>().having(
          (e) => e.reason,
          'reason',
          'invalid_sender_role',
        ),
      ),
    );
  });

  test('desconexión destruye el estado AKE (material efímero por-conexión)',
      () async {
    final tape = _Tape();
    final (a, b) = await _handshakeStandard(tape);

    a.coordinator.onDisconnected(_endpoint);
    b.coordinator.onDisconnected(_endpoint);
    expect(a.coordinator.hasCompletedAkeFor(_endpoint), isFalse);
    expect(b.coordinator.hasCompletedAkeFor(_endpoint), isFalse);
    expect(a.channel(_endpoint), isNull);
    expect(b.channel(_endpoint), isNull);
  });

  test('¿endpoint ya settleado? hellos adicionales se ignoran (sin doble clave)',
      () async {
    final tape = _Tape();
    final (a, b) = await _handshakeStandard(tape);
    final hashBefore = b.settled[_endpoint]!.transcriptHash;

    // Un hello NUEVO (iniciador distinto, Mallory) llega al endpoint YA
    // settleado de B: ignorado, la sesión establecida no cambia.
    final mallory = await _TestPeer.create(
      name: 'M',
      zoneId: _zoneM,
      accountId: _accountM,
      deviceId: _deviceM,
      identitySeed: List<int>.generate(32, (i) => (i * 17 + 7) & 0xff),
      encryptionSeed: List<int>.generate(32, (i) => (i * 19 + 9) & 0xff),
      destinationPeer: 'B',
      tape: tape,
    );
    expect(await mallory.coordinator.onConnected(_endpoint), isTrue);
    await tape.deliver(b, _endpoint);

    expect(
      b.settled[_endpoint]!.transcriptHash,
      equals(hashBefore),
      reason: 'el settle NO se sobreescribe',
    );
  });
}
