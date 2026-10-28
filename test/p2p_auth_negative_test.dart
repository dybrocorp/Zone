/// FASE E — Tests negativos del contrato de autenticación P2P (Z-004).
///
/// Ejercitan `P2PAuthPolicy` con firmas Ed25519 reales (no mocks de
/// criptografía) y cubren los siete vectores exigidos:
/// key substitution, wrong identity, replay, modified transcript, revoked key,
/// incomplete negotiation y session reuse. También fijan el transcript canónico
/// y el comportamiento del caché anti-replay.
///
/// El handshake completo y el key schedule NO están implementados: estos tests
/// validan la política de verificación que la Fase G deberá integrar.
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/ed25519_identity_service.dart';
import 'package:zone/identity/keys.dart';
import 'package:zone/identity/x25519_device_service.dart';
import 'package:zone/services/p2p_auth_policy.dart';

const String _zoneId = 'ZONE-ABCD1234';
const String _otherZoneId = 'ZONE-OTHER123';
const String _accountId = '11111111-1111-4111-8111-111111111111';
const String _deviceId = '22222222-2222-4222-8222-222222222222';
const String _sessionId = '33333333-3333-4333-8333-333333333333';
const String _sessionIdB = '44444444-4444-4444-8444-444444444444';

final DateTime _fixedNow = DateTime.utc(2026, 10, 23, 12);
final int _fixedNowMs = _fixedNow.millisecondsSinceEpoch;

void main() {
  late _Peer victim;
  late _Peer attacker;

  setUpAll(() async {
    victim = await _Peer.create(
      identitySeed: List<int>.generate(32, (i) => i),
      encryptionSeed: List<int>.generate(32, (i) => 255 - i),
      ephemeralSeed: List<int>.generate(32, (i) => 100 + i),
    );
    attacker = await _Peer.create(
      identitySeed: List<int>.generate(32, (i) => (i * 7 + 1) & 0xff),
      encryptionSeed: List<int>.generate(32, (i) => (i * 11 + 3) & 0xff),
      ephemeralSeed: List<int>.generate(32, (i) => (i * 13 + 5) & 0xff),
    );
  });

  group('transcript canónico ZONE-P2P-AKE-1', () {
    test('es determinista para el mismo hello', () async {
      final hello = _hello(peer: victim);
      final a = P2PAuthPolicy.canonicalTranscript(hello: hello);
      final b = P2PAuthPolicy.canonicalTranscript(hello: hello);
      expect(a, equals(b));

      final hashA = await P2PAuthPolicy.transcriptHash(hello: hello);
      final hashB = await P2PAuthPolicy.transcriptHash(hello: hello);
      expect(hashA, equals(hashB));
      expect(hashA.length, 32);
    });

    test('cambiar un campo o el transcript previo cambia el hash', () async {
      final hello = _hello(peer: victim);
      final base = await P2PAuthPolicy.transcriptHash(hello: hello);

      final variants = <P2PAuthHello>[
        hello.copyWith(zoneId: _otherZoneId),
        hello.copyWith(nonceBase64: _b64(List<int>.filled(32, 7))),
        hello.copyWith(ephemeralPublicKeyBase64: _b64(List<int>.filled(32, 8))),
        hello.copyWith(encryptionKeyVersion: 2),
        hello.copyWith(issuedAtMs: hello.issuedAtMs + 1),
      ];
      for (final variant in variants) {
        final hash = await P2PAuthPolicy.transcriptHash(hello: variant);
        expect(hash, isNot(equals(base)));
      }

      final withPrior = await P2PAuthPolicy.transcriptHash(
        hello: hello,
        priorTranscriptHash: List<int>.filled(32, 9),
      );
      expect(withPrior, isNot(equals(base)));
    });
  });

  group('verificación positiva', () {
    test('hello firmado por la identidad anclada se acepta', () async {
      final hello = await _sign(_hello(peer: victim), victim);
      final decision = await _verify(hello, anchor: _anchorFor(victim));

      expect(decision.accepted, isTrue);
      expect(decision.reason, P2PAuthRejectReason.none);
      expect(decision.firstContact, isFalse);
      expect(decision.transcriptHashHex, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test(
      'primer contacto sin ancla se acepta pero exige verificación OOB',
      () async {
        final hello = await _sign(_hello(peer: victim), victim);
        final decision = await _verify(hello);

        expect(decision.accepted, isTrue);
        expect(decision.firstContact, isTrue);
      },
    );

    test(
      'hello_B firmado sobre el hash de hello_A se acepta; otro hash no',
      () async {
        final helloA = await _sign(
          _hello(peer: victim, sessionId: _sessionId),
          victim,
        );
        final prior = await P2PAuthPolicy.transcriptHash(hello: helloA);

        final helloB = await _sign(
          _hello(peer: attacker, sessionId: _sessionIdB),
          attacker,
          prior: prior,
        );

        final ok = await _verify(
          helloB,
          anchor: _anchorFor(attacker),
          prior: prior,
        );
        expect(ok.accepted, isTrue);

        final wrongPrior = await P2PAuthPolicy.transcriptHash(
          hello: helloA.copyWith(nonceBase64: _b64(List<int>.filled(32, 1))),
        );
        final rejected = await _verify(
          helloB,
          anchor: _anchorFor(attacker),
          prior: wrongPrior,
        );
        expect(rejected.accepted, isFalse);
        expect(rejected.reason, P2PAuthRejectReason.invalidSignature);
      },
    );
  });

  group('key substitution', () {
    test('identidad distinta a la anclada ⇒ identityKeySubstitution', () async {
      final hello = await _sign(_hello(peer: attacker), attacker);
      final decision = await _verify(hello, anchor: _anchorFor(victim));

      expect(decision.accepted, isFalse);
      expect(decision.reason, P2PAuthRejectReason.identityKeySubstitution);
    });

    test('X25519 distinta a la anclada ⇒ encryptionKeySubstitution', () async {
      final hello = await _sign(
        _hello(peer: victim, encryptionPublicKeyBase64: attacker.encryptionPub),
        victim,
      );
      final decision = await _verify(hello, anchor: _anchorFor(victim));

      expect(decision.accepted, isFalse);
      expect(decision.reason, P2PAuthRejectReason.encryptionKeySubstitution);
    });

    test('rollback de versión de clave ⇒ keyVersionRollback', () async {
      final hello = await _sign(
        _hello(peer: victim, encryptionKeyVersion: 1),
        victim,
      );
      final decision = await _verify(
        hello,
        anchor: _anchorFor(victim, version: 2),
      );

      expect(decision.reason, P2PAuthRejectReason.keyVersionRollback);
    });

    test(
      'subida de versión sin registro firmado ⇒ keyRotationRequired',
      () async {
        final hello = await _sign(
          _hello(peer: victim, encryptionKeyVersion: 2),
          victim,
        );
        final decision = await _verify(
          hello,
          anchor: _anchorFor(victim, version: 1),
        );

        expect(decision.reason, P2PAuthRejectReason.keyRotationRequired);
      },
    );
  });

  group('wrong identity', () {
    test(
      'firma válida pero zone_id distinto del enlazado ⇒ identityMismatch',
      () async {
        final hello = await _sign(_hello(peer: victim), victim);
        final decision = await _verify(
          hello,
          anchor: _anchorFor(victim),
          expectedZoneId: _otherZoneId,
        );

        expect(decision.accepted, isFalse);
        expect(decision.reason, P2PAuthRejectReason.identityMismatch);
      },
    );

    test('zone_id no canónico ⇒ invalidZoneId', () async {
      final hello = await _sign(
        _hello(peer: victim, zoneId: 'zone-ABCD1234'),
        victim,
      );
      final decision = await _verify(hello, anchor: _anchorFor(victim));

      expect(decision.reason, P2PAuthRejectReason.invalidZoneId);
    });

    test('account_id/device_id no canónicos ⇒ rechazo tipado', () async {
      final badAccount = await _sign(
        _hello(peer: victim, accountId: '11111111-1111-4111-8111-11111111111A'),
        victim,
      );
      expect(
        (await _verify(badAccount, anchor: _anchorFor(victim))).reason,
        P2PAuthRejectReason.invalidAccountId,
      );

      final badDevice = await _sign(
        _hello(peer: victim, deviceId: '22222222-2222-4222-8222-22222222222B'),
        victim,
      );
      expect(
        (await _verify(badDevice, anchor: _anchorFor(victim))).reason,
        P2PAuthRejectReason.invalidDeviceId,
      );
    });
  });

  group('replay y session reuse', () {
    test('mismo session_id dos veces ⇒ replayedSession', () async {
      final cache = P2PSessionReplayCache();
      final hello = await _sign(_hello(peer: victim), victim);

      final first = await _verify(
        hello,
        anchor: _anchorFor(victim),
        cache: cache,
      );
      expect(first.accepted, isTrue);

      final second = await _verify(
        hello,
        anchor: _anchorFor(victim),
        cache: cache,
      );
      expect(second.accepted, isFalse);
      expect(second.reason, P2PAuthRejectReason.replayedSession);
    });

    test('session_id ya activo ⇒ sessionReuse', () async {
      final hello = await _sign(_hello(peer: victim), victim);
      final decision = await _verify(
        hello,
        anchor: _anchorFor(victim),
        activeSessionIds: {hello.sessionId},
      );

      expect(decision.reason, P2PAuthRejectReason.sessionReuse);
    });

    test('caché anti-replay caduca por TTL y no crece sin límite', () {
      final cache = P2PSessionReplayCache(
        ttl: const Duration(seconds: 1),
        maxEntries: 2,
      );
      expect(cache.register('a', now: _fixedNow), isTrue);
      expect(cache.register('a', now: _fixedNow), isFalse);
      expect(cache.contains('a', now: _fixedNow), isTrue);
      expect(
        cache.contains('a', now: _fixedNow.add(const Duration(seconds: 2))),
        isFalse,
      );

      expect(cache.register('b', now: _fixedNow), isTrue);
      expect(cache.register('c', now: _fixedNow), isTrue);
      expect(cache.length, lessThanOrEqualTo(2));
    });
  });

  group('modified transcript', () {
    test(
      'alterar zone_id, nonce, timestamp o ephemeral ⇒ invalidSignature',
      () async {
        final signed = await _sign(_hello(peer: victim), victim);
        final tampered = <P2PAuthHello>[
          signed.copyWith(zoneId: 'ZONE-HACK1234'),
          signed.copyWith(nonceBase64: _b64(List<int>.filled(32, 1))),
          signed.copyWith(issuedAtMs: signed.issuedAtMs + 1),
          signed.copyWith(
            ephemeralPublicKeyBase64: _b64(List<int>.filled(32, 2)),
          ),
        ];

        for (final hello in tampered) {
          final decision = await _verify(hello, anchor: _anchorFor(victim));
          expect(decision.accepted, isFalse, reason: 'tampered hello accepted');
          expect(decision.reason, P2PAuthRejectReason.invalidSignature);
        }
      },
    );

    test('firma alterada byte a byte ⇒ invalidSignature', () async {
      final signed = await _sign(_hello(peer: victim), victim);
      final signature = base64Decode(signed.signatureBase64);
      signature[0] ^= 0xff;

      final decision = await _verify(
        signed.copyWith(signatureBase64: base64Encode(signature)),
        anchor: _anchorFor(victim),
      );
      expect(decision.reason, P2PAuthRejectReason.invalidSignature);
    });
  });

  group('revoked key', () {
    test('dispositivo no activo ⇒ revokedDevice', () async {
      for (final status in <DeviceStatus>[
        DeviceStatus.pending,
        DeviceStatus.revoked,
        DeviceStatus.compromised,
        DeviceStatus.locked,
        DeviceStatus.killed,
      ]) {
        final hello = await _sign(
          _hello(peer: victim, deviceStatus: status),
          victim,
        );
        final decision = await _verify(hello, anchor: _anchorFor(victim));
        expect(
          decision.reason,
          P2PAuthRejectReason.revokedDevice,
          reason: 'status ${status.statusId} accepted',
        );
      }
    });

    test(
      'revoked_at presente aunque status sea active ⇒ revokedDevice',
      () async {
        final hello = await _sign(
          _hello(peer: victim, revokedAt: _fixedNow),
          victim,
        );
        final decision = await _verify(hello, anchor: _anchorFor(victim));

        expect(decision.reason, P2PAuthRejectReason.revokedDevice);
      },
    );
  });

  group('incomplete negotiation', () {
    test('campos obligatorios ausentes ⇒ incompleteNegotiation', () async {
      final base = _hello(peer: victim);
      final variants = <P2PAuthHello>[
        base.copyWith(signatureBase64: ''),
        base.copyWith(nonceBase64: ''),
        base.copyWith(ephemeralPublicKeyBase64: ''),
        base.copyWith(version: ''),
        base.copyWith(encryptionKeyVersion: 0),
      ];

      for (final hello in variants) {
        final decision = await _verify(hello, anchor: _anchorFor(victim));
        expect(
          decision.reason,
          P2PAuthRejectReason.incompleteNegotiation,
          reason: 'variant accepted: $hello',
        );
      }
    });

    test('versión no soportada ⇒ unsupportedVersion', () async {
      final hello = await _sign(
        _hello(peer: victim, version: 'ZONE-P2P-AKE-0'),
        victim,
      );
      final decision = await _verify(hello, anchor: _anchorFor(victim));

      expect(decision.reason, P2PAuthRejectReason.unsupportedVersion);
    });

    test('algoritmo de clave intercambiado ⇒ keyPurposeMismatch', () async {
      final hello = await _sign(
        _hello(peer: victim, encryptionKeyAlgorithm: 'Ed25519'),
        victim,
      );
      final decision = await _verify(hello, anchor: _anchorFor(victim));

      expect(decision.reason, P2PAuthRejectReason.keyPurposeMismatch);
    });

    test(
      'longitudes de clave/nonce/firma inválidas ⇒ rechazo tipado',
      () async {
        final base = await _sign(_hello(peer: victim), victim);
        final cases = <P2PAuthHello, P2PAuthRejectReason>{
          base.copyWith(identityPublicKeyBase64: _b64(List<int>.filled(31, 1))):
              P2PAuthRejectReason.invalidIdentityKey,
          base.copyWith(
            encryptionPublicKeyBase64: _b64(List<int>.filled(31, 2)),
          ): P2PAuthRejectReason.invalidEncryptionKey,
          base.copyWith(
            ephemeralPublicKeyBase64: _b64(List<int>.filled(31, 3)),
          ): P2PAuthRejectReason.invalidEphemeralKey,
          base.copyWith(nonceBase64: _b64(List<int>.filled(31, 4))):
              P2PAuthRejectReason.invalidNonce,
          base.copyWith(signatureBase64: _b64(List<int>.filled(63, 5))):
              P2PAuthRejectReason.invalidSignature,
        };

        for (final entry in cases.entries) {
          final decision = await _verify(entry.key, anchor: _anchorFor(victim));
          expect(decision.reason, entry.value);
        }
      },
    );
  });

  group('stale handshake', () {
    test('timestamp antiguo o demasiado futuro ⇒ staleHandshake', () async {
      final old = await _sign(
        _hello(
          peer: victim,
          issuedAtMs: _fixedNowMs - const Duration(minutes: 10).inMilliseconds,
        ),
        victim,
      );
      expect(
        (await _verify(old, anchor: _anchorFor(victim))).reason,
        P2PAuthRejectReason.staleHandshake,
      );

      final future = await _sign(
        _hello(
          peer: victim,
          issuedAtMs: _fixedNowMs + const Duration(minutes: 10).inMilliseconds,
        ),
        victim,
      );
      expect(
        (await _verify(future, anchor: _anchorFor(victim))).reason,
        P2PAuthRejectReason.staleHandshake,
      );
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _Peer {
  _Peer({
    required this.identityKeyPair,
    required this.encryptionKeyPair,
    required this.ephemeralKeyPair,
    required this.identityPub,
    required this.encryptionPub,
    required this.ephemeralPub,
  });

  final SimpleKeyPair identityKeyPair;
  final SimpleKeyPair encryptionKeyPair;
  final SimpleKeyPair ephemeralKeyPair;
  final String identityPub;
  final String encryptionPub;
  final String ephemeralPub;

  static Future<_Peer> create({
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
      identityKeyPair: identity,
      encryptionKeyPair: encryption,
      ephemeralKeyPair: ephemeral,
      identityPub: await Ed25519IdentityService.publicKeyBase64(identity),
      encryptionPub: await X25519DeviceEncryptionService.publicKeyBase64(
        encryption,
      ),
      ephemeralPub: await X25519DeviceEncryptionService.publicKeyBase64(
        ephemeral,
      ),
    );
  }
}

P2PAuthHello _hello({
  required _Peer peer,
  String version = kP2PAuthVersion,
  String zoneId = _zoneId,
  String accountId = _accountId,
  String deviceId = _deviceId,
  String? identityKeyAlgorithm,
  String? identityPublicKeyBase64,
  String? encryptionKeyAlgorithm,
  String? encryptionPublicKeyBase64,
  int encryptionKeyVersion = 1,
  String? ephemeralPublicKeyBase64,
  String? nonceBase64,
  String sessionId = _sessionId,
  int? issuedAtMs,
  String signatureBase64 = '',
  DeviceStatus deviceStatus = DeviceStatus.active,
  DateTime? revokedAt,
}) => P2PAuthHello(
  version: version,
  zoneId: zoneId,
  accountId: accountId,
  deviceId: deviceId,
  identityKeyAlgorithm: identityKeyAlgorithm ?? 'Ed25519',
  identityPublicKeyBase64: identityPublicKeyBase64 ?? peer.identityPub,
  encryptionKeyAlgorithm: encryptionKeyAlgorithm ?? 'X25519',
  encryptionPublicKeyBase64: encryptionPublicKeyBase64 ?? peer.encryptionPub,
  encryptionKeyVersion: encryptionKeyVersion,
  ephemeralPublicKeyBase64: ephemeralPublicKeyBase64 ?? peer.ephemeralPub,
  nonceBase64: nonceBase64 ?? _b64(List<int>.generate(32, (i) => i)),
  sessionId: sessionId,
  issuedAtMs: issuedAtMs ?? _fixedNowMs,
  signatureBase64: signatureBase64,
  deviceStatus: deviceStatus,
  revokedAt: revokedAt,
);

Future<P2PAuthHello> _sign(
  P2PAuthHello hello,
  _Peer peer, {
  List<int>? prior,
}) async {
  final transcript = P2PAuthPolicy.canonicalTranscript(
    hello: hello,
    priorTranscriptHash: prior,
  );
  final signature = await Ed25519IdentityService.sign(
    peer.identityKeyPair,
    transcript,
  );
  return hello.copyWith(signatureBase64: base64Encode(signature));
}

P2PTrustAnchor _anchorFor(_Peer peer, {int version = 1}) => P2PTrustAnchor(
  identityPublicKeyBase64: peer.identityPub,
  encryptionPublicKeyBase64: peer.encryptionPub,
  encryptionKeyVersion: version,
);

Future<P2PAuthDecision> _verify(
  P2PAuthHello hello, {
  P2PTrustAnchor? anchor,
  P2PSessionReplayCache? cache,
  String? expectedZoneId,
  Set<String> activeSessionIds = const <String>{},
  List<int>? prior,
}) => P2PAuthPolicy.verifyHello(
  hello: hello,
  replayCache: cache ?? P2PSessionReplayCache(),
  trustAnchor: anchor,
  expectedZoneId: expectedZoneId,
  activeSessionIds: activeSessionIds,
  priorTranscriptHash: prior,
  now: _fixedNow,
);

String _b64(List<int> bytes) => base64Encode(bytes);
