/// FASE E/G — Tests de integración del handshake `ZONE-P2P-AKE-1`.
///
/// Ejercitan el orquestador [P2PHandshakeSession] de extremo a extremo:
/// dos peers reales, firmas Ed25519 reales, ECDH X25519 real y HKDF-SHA256.
/// No hay mocks de criptografía ni se toca `NearbyService`.
///
/// Estos tests **no** cierran Z-004: demuestran que la sustitución de clave
/// se detecta cuando ya existe un ancla. En el primer contacto el modelo sigue
/// siendo TOFU y exige verificación fuera de banda.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/ed25519_identity_service.dart';
import 'package:zone/identity/keys.dart';
import 'package:zone/identity/x25519_device_service.dart';
import 'package:zone/services/p2p_auth_policy.dart';
import 'package:zone/services/p2p_handshake_session.dart';

final DateTime _fixedNow = DateTime.utc(2026, 10, 23, 12);
const String _accountA = '11111111-1111-4111-8111-111111111111';
const String _accountB = '22222222-2222-4222-8222-222222222222';
const String _deviceA = '33333333-3333-4333-8333-333333333333';
const String _deviceB = '44444444-4444-4444-8444-444444444444';
const String _sessionA = '55555555-5555-4555-8555-555555555555';
const String _sessionB = '66666666-6666-4666-8666-666666666666';

void main() {
  late _Peer alice;
  late _Peer bob;
  late _Peer mallory;

  setUpAll(() async {
    alice = await _Peer.create(
      zoneId: 'ZONE-ALICE001',
      accountId: _accountA,
      deviceId: _deviceA,
      identitySeed: List<int>.generate(32, (i) => i),
      encryptionSeed: List<int>.generate(32, (i) => 255 - i),
      ephemeralSeed: List<int>.generate(32, (i) => 100 + i),
    );
    bob = await _Peer.create(
      zoneId: 'ZONE-BOB00002',
      accountId: _accountB,
      deviceId: _deviceB,
      identitySeed: List<int>.generate(32, (i) => (i * 7 + 1) & 0xff),
      encryptionSeed: List<int>.generate(32, (i) => (i * 11 + 3) & 0xff),
      ephemeralSeed: List<int>.generate(32, (i) => (i * 13 + 5) & 0xff),
    );
    mallory = await _Peer.create(
      zoneId: 'ZONE-MAL00003',
      accountId: '99999999-9999-4999-8999-999999999999',
      deviceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      identitySeed: List<int>.generate(32, (i) => (i * 17 + 7) & 0xff),
      encryptionSeed: List<int>.generate(32, (i) => (i * 19 + 9) & 0xff),
      ephemeralSeed: List<int>.generate(32, (i) => (i * 23 + 11) & 0xff),
    );
  });

  group('handshake completo', () {
    test('ambos lados derivan la misma clave y el mismo transcript', () async {
      final pair = _HandshakePair(alice, bob);
      await pair.exchange();
      expect(pair.decisionA?.accepted, isTrue);
      expect(pair.decisionB?.accepted, isTrue);

      final keys = await pair.completeBoth();
      expect(keys.$1.keyBytes.length, 32);
      expect(keys.$1.keyBytes, equals(keys.$2.keyBytes));
      expect(keys.$1.transcriptHash, equals(keys.$2.transcriptHash));
      expect(keys.$1.transcriptHash.length, 32);
      expect(keys.$1.initiatorSessionId, _sessionA);
      expect(keys.$1.responderSessionId, _sessionB);
    });

    test('la clave de sesión no es el secreto X25519 crudo (regresión Z-004)',
        () async {
      final pair = _HandshakePair(alice, bob);
      await pair.exchange();
      final keys = await pair.completeBoth();

      final rawDh4 = await X25519DeviceEncryptionService.sharedSecret(
        localKeyPair: alice.encryptionKeyPair,
        remotePublicKey: bob.encryptionPublicKey,
      );
      expect(keys.$1.keyBytes, isNot(equals(await rawDh4.extractBytes())));
    });

    test('efímeros frescos producen claves distintas para los mismos peers',
        () async {
      final first = _HandshakePair(alice, bob);
      await first.exchange();
      final firstKeys = await first.completeBoth();

      final second = _HandshakePair(
        alice,
        bob,
        initiatorEphemeral: await X25519DeviceEncryptionService.keyPairFromSeed(
          List<int>.generate(32, (i) => (0x5a + i) & 0xff),
        ),
        responderEphemeral: await X25519DeviceEncryptionService.keyPairFromSeed(
          List<int>.generate(32, (i) => (0xa5 + i) & 0xff),
        ),
      );
      await second.exchange();
      final secondKeys = await second.completeBoth();

      expect(firstKeys.$1.keyBytes, isNot(equals(secondKeys.$1.keyBytes)));
    });

    test('intercambiar los roles produce una clave distinta (domain sep.)',
        () async {
      final forward = _HandshakePair(alice, bob);
      await forward.exchange();
      final forwardKeys = await forward.completeBoth();

      final reverse = _HandshakePair(bob, alice);
      await reverse.exchange();
      final reverseKeys = await reverse.completeBoth();

      expect(forwardKeys.$1.keyBytes, isNot(equals(reverseKeys.$1.keyBytes)));
    });

    test('el primer contacto se marca firstContact y el segundo no', () async {
      final first = _HandshakePair(alice, bob);
      await first.exchange();
      expect(first.decisionB?.firstContact, isTrue);
      expect(first.decisionA?.firstContact, isTrue);

      final anchor = _anchorOf(bob);
      final second = _HandshakePair(alice, bob);
      await second.exchange(
        initiatorAnchor: anchor,
        responderAnchor: _anchorOf(alice),
      );
      expect(second.decisionB?.accepted, isTrue);
      expect(second.decisionB?.firstContact, isFalse);
    });
  });

  group('sustitución de identidad y MITM', () {
    test('alterar la X25519 del hello invalida la firma', () async {
      final pair = _HandshakePair(alice, bob);
      final helloA = await pair.initiatorSession.createHello(now: _fixedNow);
      final tampered = helloA.copyWith(
        encryptionPublicKeyBase64: _b64(List<int>.filled(32, 0x42)),
      );
      final decision = await pair.responderSession.acceptPeerHello(
        tampered,
        now: _fixedNow,
      );
      expect(decision.accepted, isFalse);
      expect(decision.reason, P2PAuthRejectReason.invalidSignature);
    });

    test('un atacante que re-firma con su identidad no supera el ancla',
        () async {
      final attackerSession = P2PHandshakeSession(
        role: P2PHandshakeRole.initiator,
        zoneId: mallory.zoneId,
        accountId: mallory.accountId,
        deviceId: mallory.deviceId,
        identityKeyPair: mallory.identityKeyPair,
        encryptionKeyPair: mallory.encryptionKeyPair,
        encryptionKeyVersion: 1,
        endpointId: 'ep-mallory',
        ephemeralKeyPair: mallory.ephemeralKeyPair,
        sessionId: _sessionA,
        nonce: List<int>.filled(32, 1),
      );
      final forged = await attackerSession.createHello(now: _fixedNow);

      final victimSession = _sessionFor(
        bob,
        P2PHandshakeRole.responder,
        sessionId: _sessionB,
      );
      final firstContact = await victimSession.acceptPeerHello(
        forged,
        now: _fixedNow,
      );
      // TOFU: sin ancla, la firma es válida y el primer contacto se acepta.
      expect(firstContact.accepted, isTrue);
      expect(firstContact.firstContact, isTrue);

      final secondSession = _sessionFor(
        bob,
        P2PHandshakeRole.responder,
        sessionId: _sessionB,
      );
      final knownPeer = await secondSession.acceptPeerHello(
        forged,
        trustAnchor: _anchorOf(alice),
        now: _fixedNow,
      );
      expect(knownPeer.accepted, isFalse);
      expect(
        knownPeer.reason,
        P2PAuthRejectReason.identityKeySubstitution,
      );
    });

    test('un prior distinto del transcript del iniciador se rechaza', () async {
      final pair = _HandshakePair(alice, bob);
      await pair.exchange();
      final wrongPrior = Uint8List.fromList(List<int>.filled(32, 0x7f));
      final freshInitiator = _sessionFor(alice, P2PHandshakeRole.initiator);
      final decision = await freshInitiator.acceptPeerHello(
        pair.helloB!,
        priorTranscriptHash: wrongPrior,
        now: _fixedNow,
      );
      expect(decision.accepted, isFalse);
      expect(decision.reason, P2PAuthRejectReason.invalidSignature);
    });
  });

  group('replay, TTL y estado del dispositivo', () {
    test('reutilizar el hello del iniciador se rechaza', () async {
      final cache = P2PSessionReplayCache();
      final first = _HandshakePair(alice, bob, responderCache: cache);
      final helloA = await first.initiatorSession.createHello(now: _fixedNow);
      final accepted = await first.responderSession.acceptPeerHello(
        helloA,
        now: _fixedNow,
      );
      expect(accepted.accepted, isTrue);

      final replaySession = _sessionFor(
        bob,
        P2PHandshakeRole.responder,
        sessionId: _sessionB,
        replayCache: cache,
      );
      final replayed = await replaySession.acceptPeerHello(
        helloA,
        now: _fixedNow,
      );
      expect(replayed.accepted, isFalse);
      expect(replayed.reason, P2PAuthRejectReason.replayedSession);
    });

    test('un handshake fuera de la ventana TTL se rechaza', () async {
      final pair = _HandshakePair(alice, bob);
      final helloA = await pair.initiatorSession.createHello(now: _fixedNow);
      final decision = await pair.responderSession.acceptPeerHello(
        helloA,
        now: _fixedNow.add(const Duration(minutes: 3)),
      );
      expect(decision.accepted, isFalse);
      expect(decision.reason, P2PAuthRejectReason.staleHandshake);
    });

    test('un dispositivo revocado se rechaza antes de derivar', () async {
      final pair = _HandshakePair(alice, bob);
      final helloA = await pair.initiatorSession.createHello(now: _fixedNow);
      final decision = await pair.responderSession.acceptPeerHello(
        helloA.copyWith(deviceStatus: DeviceStatus.revoked),
        now: _fixedNow,
      );
      expect(decision.accepted, isFalse);
      expect(decision.reason, P2PAuthRejectReason.revokedDevice);
    });
  });

  group('negociación incompleta y fail-closed', () {
    test('complete() sin hello remoto no deriva clave', () async {
      final session = _sessionFor(alice, P2PHandshakeRole.initiator);
      await session.createHello(now: _fixedNow);
      await expectLater(
        session.complete(),
        throwsA(
          isA<P2PHandshakeException>().having(
            (e) => e.failure,
            'failure',
            P2PHandshakeFailure.remoteHelloMissing,
          ),
        ),
      );
    });

    test('complete() tras un rechazo no deriva clave', () async {
      final pair = _HandshakePair(alice, bob);
      final helloA = await pair.initiatorSession.createHello(now: _fixedNow);
      final hashA = await P2PAuthPolicy.transcriptHash(hello: helloA);
      final accepted = await pair.responderSession.acceptPeerHello(
        helloA,
        now: _fixedNow,
      );
      expect(accepted.accepted, isTrue);

      final helloB = await pair.responderSession.createHello(
        priorTranscriptHash: hashA,
        now: _fixedNow,
      );
      final rejected = await pair.initiatorSession.acceptPeerHello(
        helloB.copyWith(
          nonceBase64: _b64(List<int>.filled(32, 0x24)),
        ),
        priorTranscriptHash: hashA,
        now: _fixedNow,
      );
      expect(rejected.accepted, isFalse);

      await expectLater(
        pair.initiatorSession.complete(),
        throwsA(
          isA<P2PHandshakeException>().having(
            (e) => e.failure,
            'failure',
            P2PHandshakeFailure.remoteHelloRejected,
          ),
        ),
      );
    });

    test('el iniciador exige el binding de transcript del responder',
        () async {
      final pair = _HandshakePair(alice, bob);
      final helloA = await pair.initiatorSession.createHello(now: _fixedNow);
      await pair.responderSession.acceptPeerHello(helloA, now: _fixedNow);
      final helloB = await pair.responderSession.createHello(
        priorTranscriptHash: await P2PAuthPolicy.transcriptHash(hello: helloA),
        now: _fixedNow,
      );
      await expectLater(
        pair.initiatorSession.acceptPeerHello(helloB, now: _fixedNow),
        throwsA(
          isA<P2PHandshakeException>().having(
            (e) => e.failure,
            'failure',
            P2PHandshakeFailure.transcriptBindingRequired,
          ),
        ),
      );
    });

    test('un hello sin firma se rechaza como negociación incompleta',
        () async {
      final pair = _HandshakePair(alice, bob);
      final helloA = await pair.initiatorSession.createHello(now: _fixedNow);
      final decision = await pair.responderSession.acceptPeerHello(
        helloA.copyWith(signatureBase64: ''),
        now: _fixedNow,
      );
      expect(decision.accepted, isFalse);
      expect(decision.reason, P2PAuthRejectReason.incompleteNegotiation);
    });

    test('una versión no soportada se rechaza (sin downgrade)', () async {
      final pair = _HandshakePair(alice, bob);
      final helloA = await pair.initiatorSession.createHello(now: _fixedNow);
      final decision = await pair.responderSession.acceptPeerHello(
        helloA.copyWith(version: 'ZONE-P2P-AKE-0'),
        now: _fixedNow,
      );
      expect(decision.accepted, isFalse);
      expect(decision.reason, P2PAuthRejectReason.unsupportedVersion);
    });

    test('un endpoint distinto invalida la sesión', () async {
      final session = _sessionFor(alice, P2PHandshakeRole.initiator);
      expect(
        () => session.assertEndpoint('ep-otro'),
        throwsA(
          isA<P2PHandshakeException>().having(
            (e) => e.failure,
            'failure',
            P2PHandshakeFailure.endpointMismatch,
          ),
        ),
      );
    });

    test('destroy() impide completar el handshake', () async {
      final pair = _HandshakePair(alice, bob);
      await pair.exchange();
      pair.initiatorSession.destroy();
      await expectLater(
        pair.initiatorSession.complete(),
        throwsA(
          isA<P2PHandshakeException>().having(
            (e) => e.failure,
            'failure',
            P2PHandshakeFailure.destroyed,
          ),
        ),
      );
    });
  });
}

class _Peer {
  _Peer({
    required this.zoneId,
    required this.accountId,
    required this.deviceId,
    required this.identityKeyPair,
    required this.encryptionKeyPair,
    required this.ephemeralKeyPair,
    required this.identityPublicKeyBase64,
    required this.encryptionPublicKeyBase64,
  });

  final String zoneId;
  final String accountId;
  final String deviceId;
  final SimpleKeyPair identityKeyPair;
  final SimpleKeyPair encryptionKeyPair;
  final SimpleKeyPair ephemeralKeyPair;
  final String identityPublicKeyBase64;
  final String encryptionPublicKeyBase64;

  SimplePublicKey get encryptionPublicKey => SimplePublicKey(
    base64Decode(encryptionPublicKeyBase64),
    type: KeyPairType.x25519,
  );

  static Future<_Peer> create({
    required String zoneId,
    required String accountId,
    required String deviceId,
    required List<int> identitySeed,
    required List<int> encryptionSeed,
    required List<int> ephemeralSeed,
  }) async {
    final identity = await Ed25519IdentityService.keyPairFromSeed(identitySeed);
    final encryption = await X25519DeviceEncryptionService.keyPairFromSeed(
      encryptionSeed,
    );
    final ephemeral = await X25519DeviceEncryptionService.keyPairFromSeed(
      ephemeralSeed,
    );
    return _Peer(
      zoneId: zoneId,
      accountId: accountId,
      deviceId: deviceId,
      identityKeyPair: identity,
      encryptionKeyPair: encryption,
      ephemeralKeyPair: ephemeral,
      identityPublicKeyBase64: await Ed25519IdentityService.publicKeyBase64(
        identity,
      ),
      encryptionPublicKeyBase64:
          await X25519DeviceEncryptionService.publicKeyBase64(encryption),
    );
  }
}

class _HandshakePair {
  _HandshakePair(
    this.initiator,
    this.responder, {
    P2PSessionReplayCache? initiatorCache,
    P2PSessionReplayCache? responderCache,
    SimpleKeyPair? initiatorEphemeral,
    SimpleKeyPair? responderEphemeral,
  }) : initiatorSession = _sessionFor(
         initiator,
         P2PHandshakeRole.initiator,
         sessionId: _sessionA,
         replayCache: initiatorCache,
         ephemeralKeyPair: initiatorEphemeral,
       ),
       responderSession = _sessionFor(
         responder,
         P2PHandshakeRole.responder,
         sessionId: _sessionB,
         replayCache: responderCache,
         ephemeralKeyPair: responderEphemeral,
       );

  final _Peer initiator;
  final _Peer responder;
  final P2PHandshakeSession initiatorSession;
  final P2PHandshakeSession responderSession;

  P2PAuthHello? helloA;
  P2PAuthHello? helloB;
  P2PAuthDecision? decisionA;
  P2PAuthDecision? decisionB;
  Uint8List? hashA;

  Future<void> exchange({
    P2PTrustAnchor? initiatorAnchor,
    P2PTrustAnchor? responderAnchor,
    String? initiatorExpectedZone,
    String? responderExpectedZone,
    DateTime? now,
  }) async {
    final at = now ?? _fixedNow;
    helloA = await initiatorSession.createHello(now: at);
    hashA = await P2PAuthPolicy.transcriptHash(hello: helloA!);

    decisionB = await responderSession.acceptPeerHello(
      helloA!,
      trustAnchor: responderAnchor,
      expectedZoneId: responderExpectedZone,
      now: at,
    );
    if (!decisionB!.accepted) return;

    helloB = await responderSession.createHello(
      priorTranscriptHash: hashA,
      now: at,
    );
    decisionA = await initiatorSession.acceptPeerHello(
      helloB!,
      trustAnchor: initiatorAnchor,
      expectedZoneId: initiatorExpectedZone,
      priorTranscriptHash: hashA,
      now: at,
    );
  }

  Future<(P2PSessionKeyMaterial, P2PSessionKeyMaterial)> completeBoth() async {
    final a = await initiatorSession.complete();
    final b = await responderSession.complete();
    return (a, b);
  }
}

P2PHandshakeSession _sessionFor(
  _Peer peer,
  P2PHandshakeRole role, {
  String? sessionId,
  P2PSessionReplayCache? replayCache,
  SimpleKeyPair? ephemeralKeyPair,
}) {
  return P2PHandshakeSession(
    role: role,
    zoneId: peer.zoneId,
    accountId: peer.accountId,
    deviceId: peer.deviceId,
    identityKeyPair: peer.identityKeyPair,
    encryptionKeyPair: peer.encryptionKeyPair,
    encryptionKeyVersion: 1,
    endpointId: 'ep-${peer.zoneId}',
    replayCache: replayCache,
    ephemeralKeyPair: ephemeralKeyPair ?? peer.ephemeralKeyPair,
    sessionId: sessionId,
    nonce: List<int>.filled(32, 0x11),
  );
}

P2PTrustAnchor _anchorOf(_Peer peer) {
  return P2PTrustAnchor(
    identityPublicKeyBase64: peer.identityPublicKeyBase64,
    encryptionPublicKeyBase64: peer.encryptionPublicKeyBase64,
    encryptionKeyVersion: 1,
  );
}

String _b64(List<int> bytes) => base64Encode(bytes);
