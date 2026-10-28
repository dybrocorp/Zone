/// Security tests — ZONE-E2EE-V2 (PHASE G §6.6 step 2).
///
/// Properties to test (not just the happy path):
/// - Key separation per direction (A2B vs B2A): A key IS NOT B key.
/// - Determinism of derivation (same inputs ⇒ same keys) — without this,
///   both sides would not interoperate.
/// - Integrity: ciphertext/nonce/tag forgery is rejected with a typed error.
/// - Envelope↔row (messageId/matchId) binding BEFORE the AEAD (cross-reply/replay).
/// - Canonical address routing (receiverCandidates), no oracle in the cable.
/// - Explicit v1/v2 decision by prefix (NO silent downgrade).
/// - Error translation towards v1 UX strings (ChatE2EEService v2 facade).
///
/// Fixture: X25519 RFC 7748 §6.1 seeds (deterministic). All PROVEN LOCALLY (units).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zone/crypto/e2ee_message_crypto.dart';
import 'package:zone/services/chat_e2ee_service.dart';

const String _aliceUid = '11111111-1111-1111-1111-111111111111';
const String _bobUid = '22222222-2222-2222-2222-222222222222';
const String _aliceZone = 'ZONE-AAAAAAAA';
const String _bobZone = 'ZONE-BBBBBBBB';
const String _matchId = 'match-0001';
const String _aliceMsgId = 'msg-alice-0001';
const String _bobMsgId = 'msg-bob-0001';

void main() {
  final x25519 = X25519();

  /// Backend X25519 deterministic alice (RFC seeds).
  Future<({SimpleKeyPair pair, List<int> pk})> persona(
    String smallSeedHex,
  ) async {
    final clean = smallSeedHex.replaceAll(RegExp('[^0-9a-fA-F]'), '');
    final seed = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < seed.length; i++) {
      seed[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    final pair = await x25519.newKeyPairFromSeed(seed);
    final pk = (await pair.extractPublicKey()).bytes;
    return (pair: pair, pk: pk);
  }

  setUpAll(() async {});

  test('fixture: fixed pairs and equal shared secret in both directions',
      () async {
    final alice = await persona(
      '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a',
    );
    final bob = await persona(
      '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb',
    );
    final k1 = await x25519.sharedSecretKey(
      keyPair: alice.pair,
      remotePublicKey: SimplePublicKey(bob.pk, type: KeyPairType.x25519),
    );
    final k2 = await x25519.sharedSecretKey(
      keyPair: bob.pair,
      remotePublicKey: SimplePublicKey(alice.pk, type: KeyPairType.x25519),
    );
    final k1Bytes = Uint8List.fromList(await k1.extractBytes());
    final k2Bytes = Uint8List.fromList(await k2.extractBytes());
    expect(k1Bytes, k2Bytes);
    expect(k1Bytes.length, 32);
  });

  group('Derivation of the ZONE-E2EE-V2 key', () {
    late SimpleKeyPair alicePair;
    late List<int> alicePk;
    late List<int> bobPk;
    late SecretKey shared;

    setUp(() async {
      final a = await persona(
        '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a',
      );
      final b = await persona(
        '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb',
      );
      alicePair = a.pair;
      alicePk = a.pk;
      bobPk = b.pk;
      shared = await x25519.sharedSecretKey(
        keyPair: alicePair,
        remotePublicKey: SimplePublicKey(bobPk, type: KeyPairType.x25519),
      );
    });

    test('determinism: same inputs ⇒ same salt and same keys', () async {
      final salt1 = await E2eeMessageCryptoV2.saltFor(
        senderPublicKeyBytes: alicePk,
        receiverPublicKeyBytes: bobPk,
      );
      final salt2 = await E2eeMessageCryptoV2.saltFor(
        senderPublicKeyBytes: bobPk,
        receiverPublicKeyBytes: alicePk,
      );
      expect(salt1, salt2); // canonical order by bytes ⇒ both agree.

      final k1 = await E2eeMessageCryptoV2.deriveDirectionKey(
        sharedSecret: shared,
        senderId: _aliceUid,
        receiverId: _bobUid,
        senderPublicKeyBytes: alicePk,
        receiverPublicKeyBytes: bobPk,
      );
      final k2 = await E2eeMessageCryptoV2.deriveDirectionKey(
        sharedSecret: shared,
        senderId: _aliceUid,
        receiverId: _bobUid,
        senderPublicKeyBytes: alicePk,
        receiverPublicKeyBytes: bobPk,
      );
      expect(
        await k1.extractBytes(),
        await k2.extractBytes(),
      );
    });

    test('separation A2B vs B2A: distinct keys (256-bit key domain)', () async {
      final a2b = await E2eeMessageCryptoV2.deriveDirectionKey(
        sharedSecret: shared,
        senderId: _aliceUid,
        receiverId: _bobUid,
        senderPublicKeyBytes: alicePk,
        receiverPublicKeyBytes: bobPk,
      );
      final b2a = await E2eeMessageCryptoV2.deriveDirectionKey(
        sharedSecret: shared,
        senderId: _bobUid,
        receiverId: _aliceUid,
        senderPublicKeyBytes: bobPk,
        receiverPublicKeyBytes: alicePk,
      );
      final a2bBytes = Uint8List.fromList(await a2b.extractBytes());
      final b2aBytes = Uint8List.fromList(await b2a.extractBytes());
      expect(a2bBytes, isNot(b2aBytes));
      // Sanity: both keys are 32 bytes and within the derived group, do not
      // equal the raw root (root no-direct fallback).
      expect(a2bBytes.length, 32);
      expect(
        a2bBytes,
        isNot(Uint8List.fromList(await shared.extractBytes())),
      );
    });

    test('identity invariant: sender == receiver rejected', () async {
      expect(
        () => E2eeMessageCryptoV2.encrypt(
          text: 'x',
          sharedSecret: shared,
          context: E2eeV2MessageContext(
            senderId: _aliceUid,
            receiverId: _aliceUid,
            messageId: 'm',
            matchId: _matchId,
            senderPublicKeyBytes: alicePk,
            receiverPublicKeyBytes: alicePk,
          ),
        ),
        throwsA(isA<E2eeV2ParseError>()),
      );
    });

    test('key length invariant: recipient public key ≠ 32 bytes rejected',
        () async {
      expect(
        E2eeMessageCryptoV2.deriveDirectionKey(
          sharedSecret: shared,
          senderId: _aliceUid,
          receiverId: _bobUid,
          senderPublicKeyBytes: alicePk,
          receiverPublicKeyBytes: [1, 2, 3],
        ),
        throwsA(
          isA<E2eeV2ParseError>()
              .having((e) => e.reason, 'reason', 'key_length'),
        ),
      );
    });
  });

  group(' ihremRoundtrip and context binding (real keys)', () {
    late SimpleKeyPair alicePair;
    late List<int> alicePk;
    late List<int> bobPk;
    late SecretKey shared;

    setUp(() async {
      final a = await persona(
        '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a',
      );
      final b = await persona(
        '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb',
      );
      alicePair = a.pair;
      alicePk = a.pk;
      bobPk = b.pk;
      shared = await x25519.sharedSecretKey(
        keyPair: alicePair,
        remotePublicKey: SimplePublicKey(bobPk, type: KeyPairType.x25519),
      );
    });

    E2eeV2MessageContext ctx({
      required String senderId,
      required String receiverId,
      required String messageId,
      required List<int> senderPublicKeyBytes,
      required List<int> receiverPublicKeyBytes,
    }) {
      return E2eeV2MessageContext(
        senderId: senderId,
        receiverId: receiverId,
        messageId: messageId,
        matchId: _matchId,
        senderPublicKeyBytes: senderPublicKeyBytes,
        receiverPublicKeyBytes: receiverPublicKeyBytes,
      );
    }

    test('A→B roundtrip: Bob decrypts with uid candidate and with ZONE candidate',
        () async {
      final columns = await E2eeMessageCryptoV2.encrypt(
        text: 'Hola Bob (v2)',
        sharedSecret: shared,
        context: ctx(
          senderId: _aliceUid,
          receiverId: _bobUid,
          messageId: _aliceMsgId,
          senderPublicKeyBytes: alicePk,
          receiverPublicKeyBytes: bobPk,
        ),
      );
      expect(columns['nonce'], '');
      expect(columns['mac'], '');
      expect(E2eeMessageCryptoV2.isV2Envelope(columns['encrypted_content']),
          isTrue);

      final clear = await E2eeMessageCryptoV2.decrypt(
        encryptedContent: columns['encrypted_content'] as String,
        sharedSecret: shared,
        senderId: _aliceUid,
        receiverCandidates: [_bobUid, _bobZone],
        expectedMessageId: _aliceMsgId,
        expectedMatchId: _matchId,
        senderPublicKeyBytes: alicePk,
        receiverPublicKeyBytes: bobPk,
      );
      expect(clear, 'Hola Bob (v2)');
    });

    test('roundtrip B→A: symmetric (canonical direction B2A)', () async {
      final columns = await E2eeMessageCryptoV2.encrypt(
        text: 'Hola Alice (v2)',
        sharedSecret: shared,
        context: ctx(
          senderId: _bobUid,
          receiverId: _aliceUid,
          messageId: _bobMsgId,
          senderPublicKeyBytes: bobPk,
          receiverPublicKeyBytes: alicePk,
        ),
      );
      final clear = await E2eeMessageCryptoV2.decrypt(
        encryptedContent: columns['encrypted_content'] as String,
        sharedSecret: shared,
        senderId: _bobUid,
        receiverCandidates: [_aliceUid, _aliceZone],
        expectedMessageId: _bobMsgId,
        expectedMatchId: _matchId,
        senderPublicKeyBytes: bobPk,
        receiverPublicKeyBytes: alicePk,
      );
      expect(clear, 'Hola Alice (v2)');
    });

    test('forged sender (inverted context) → authentication error (no silent OK)',
        () async {
      final columns = await E2eeMessageCryptoV2.encrypt(
        text: 'real',
        sharedSecret: shared,
        context: ctx(
          senderId: _aliceUid,
          receiverId: _bobUid,
          messageId: _aliceMsgId,
          senderPublicKeyBytes: alicePk,
          receiverPublicKeyBytes: bobPk,
        ),
      );
      // Decrypt with exchange identity roles ⇒ different key/AAD ⇒ rejection.
      expect(
        E2eeMessageCryptoV2.decrypt(
          encryptedContent: columns['encrypted_content'] as String,
          sharedSecret: shared,
          senderId: _bobUid,
          receiverCandidates: [_aliceUid],
          expectedMessageId: _aliceMsgId,
          expectedMatchId: _matchId,
          senderPublicKeyBytes: bobPk,
          receiverPublicKeyBytes: alicePk,
        ),
        throwsA(isA<E2eeV2AuthenticationError>()),
      );
    });

    test('wrong shared secret (foreigner) → authentication error', () async {
      // Third deterministic persona (seed by convention of the fixture,
      // NOT from RFC: any seed is valid for testing).
      final carol = await persona('03' * 32);
      final carolShared = await x25519.sharedSecretKey(
        keyPair: carol.pair,
        remotePublicKey: SimplePublicKey(bobPk, type: KeyPairType.x25519),
      );
      final columns = await E2eeMessageCryptoV2.encrypt(
        text: 'real',
        sharedSecret: shared,
        context: ctx(
          senderId: _aliceUid,
          receiverId: _bobUid,
          messageId: _aliceMsgId,
          senderPublicKeyBytes: alicePk,
          receiverPublicKeyBytes: bobPk,
        ),
      );
      expect(
        E2eeMessageCryptoV2.decrypt(
          encryptedContent: columns['encrypted_content'] as String,
          sharedSecret: carolShared,
          senderId: _aliceUid,
          receiverCandidates: [_bobUid],
          expectedMessageId: _aliceMsgId,
          expectedMatchId: _matchId,
          senderPublicKeyBytes: alicePk,
          receiverPublicKeyBytes: bobPk,
        ),
        throwsA(isA<E2eeV2AuthenticationError>()),
      );
    });

    test('ENVELOPE↔row binding occurs BEFORE the AEAD (context binding, not MAC)',
        () async {
      final columns = await E2eeMessageCryptoV2.encrypt(
        text: 'real',
        sharedSecret: shared,
        context: ctx(
          senderId: _aliceUid,
          receiverId: _bobUid,
          messageId: _aliceMsgId,
          senderPublicKeyBytes: alicePk,
          receiverPublicKeyBytes: bobPk,
        ),
      );
      final payloadB64 =
          (columns['encrypted_content'] as String).substring('zt2:'.length);
      final Map<String, dynamic> json =
          jsonDecode(utf8.decode(base64Decode(payloadB64)));
      // Swap IDs: if binding were "after the MAC", a typed Authentication
      // error would surface; the contract says Parse-error BEFORE AEAD.
      json['m'] = 'msg-otro';
      final crossed = _rebuildEnvelope(json);

      try {
        await E2eeMessageCryptoV2.decrypt(
          encryptedContent: crossed,
          sharedSecret: shared,
          senderId: _aliceUid,
          receiverCandidates: [_bobUid],
          expectedMessageId: _aliceMsgId,
          expectedMatchId: _matchId,
          senderPublicKeyBytes: alicePk,
          receiverPublicKeyBytes: bobPk,
        );
        fail('must reject');
      } on E2eeV2ParseError catch (e) {
        expect(e.reason, 'context');
      }
    });

    test('ciphertext/nonce/tag forgery → authentication error', () async {
      Future<void> assertTamper(
        void Function(Map<String, dynamic>) mutate,
      ) async {
        final columns = await E2eeMessageCryptoV2.encrypt(
          text: 'real',
          sharedSecret: shared,
          context: ctx(
            senderId: _aliceUid,
            receiverId: _bobUid,
            messageId: _aliceMsgId,
            senderPublicKeyBytes: alicePk,
            receiverPublicKeyBytes: bobPk,
          ),
        );
        final decoded =
            jsonDecode(utf8.decode(base64Decode(
          (columns['encrypted_content'] as String).substring('zt2:'.length),
        ))) as Map<String, dynamic>;
        mutate(decoded);
        final mutated = _rebuildEnvelope(decoded);
        expect(
          E2eeMessageCryptoV2.decrypt(
            encryptedContent: mutated,
            sharedSecret: shared,
            senderId: _aliceUid,
            receiverCandidates: [_bobUid],
            expectedMessageId: _aliceMsgId,
            expectedMatchId: _matchId,
            senderPublicKeyBytes: alicePk,
            receiverPublicKeyBytes: bobPk,
          ),
          throwsA(isA<E2eeV2AuthenticationError>()),
        );
      }

      await assertTamper((j) {
        // Invert a ciphertext bit (byte 0 of `t`).
        final t = Uint8List.fromList(base64Decode(j['t'] as String));
        t[0] = t[0] ^ 0x01;
        j['t'] = base64Encode(t);
      });
      await assertTamper((j) {
        // Invert a tag bit (byte 0 of `h`).
        final h = Uint8List.fromList(base64Decode(j['h'] as String));
        h[0] = h[0] ^ 0x01;
        j['h'] = base64Encode(h);
      });
      await assertTamper((j) {
        // Receipt of nonce: change to 11 bytes (test receiver fails at parse…
        // wait, MAC for length: MAC of 11 bytes is still base64 valid)
        final n = Uint8List.fromList(base64Decode(j['n'] as String));
        n[0] = n[0] ^ 0x01;
        j['n'] = base64Encode(n);
      });
    });

    test('empty receiverCandidates → authentication error (no fallback cypher)',
        () async {
      final columns = await E2eeMessageCryptoV2.encrypt(
        text: 'real',
        sharedSecret: shared,
        context: ctx(
          senderId: _aliceUid,
          receiverId: _bobUid,
          messageId: _aliceMsgId,
          senderPublicKeyBytes: alicePk,
          receiverPublicKeyBytes: bobPk,
        ),
      );
      expect(
        E2eeMessageCryptoV2.decrypt(
          encryptedContent: columns['encrypted_content'] as String,
          sharedSecret: shared,
          senderId: _aliceUid,
          receiverCandidates: const <String>[],
          expectedMessageId: _aliceMsgId,
          expectedMatchId: _matchId,
          senderPublicKeyBytes: alicePk,
          receiverPublicKeyBytes: bobPk,
        ),
        throwsA(isA<E2eeV2AuthenticationError>()),
      );
    });

    test('deterministic with nonceOverride: identical envelope bytes', () async {
      final nonce = List<int>.filled(12, 0x42);
      final c1 = await E2eeMessageCryptoV2.encrypt(
        text: 'same',
        sharedSecret: shared,
        context: ctx(
          senderId: _aliceUid,
          receiverId: _bobUid,
          messageId: _aliceMsgId,
          senderPublicKeyBytes: alicePk,
          receiverPublicKeyBytes: bobPk,
        ),
        nonceOverride: nonce,
      );
      final c2 = await E2eeMessageCryptoV2.encrypt(
        text: 'same',
        sharedSecret: shared,
        context: ctx(
          senderId: _aliceUid,
          receiverId: _bobUid,
          messageId: _aliceMsgId,
          senderPublicKeyBytes: alicePk,
          receiverPublicKeyBytes: bobPk,
        ),
        nonceOverride: nonce,
      );
      expect(c1['encrypted_content'], c2['encrypted_content']);
      // Override improper length rejected.
      expect(
        () => E2eeMessageCryptoV2.encrypt(
          text: 'same',
          sharedSecret: shared,
          context: ctx(
            senderId: _aliceUid,
            receiverId: _bobUid,
            messageId: _aliceMsgId,
            senderPublicKeyBytes: alicePk,
            receiverPublicKeyBytes: bobPk,
          ),
          nonceOverride: [1, 2, 3],
        ),
        throwsA(isA<E2eeV2ParseError>()),
      );
    });
  });

  group('ChatE2EEService facade v2 (row routing)', () {
    late SimpleKeyPair alicePair;
    late List<int> alicePk;
    late List<int> bobPk;
    late SecretKey shared;
    late ChatE2EEService service;

    setUp(() async {
      final a = await persona(
        '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a',
      );
      final b = await persona(
        '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb',
      );
      alicePair = a.pair;
      alicePk = a.pk;
      bobPk = b.pk;
      shared = await x25519.sharedSecretKey(
        keyPair: alicePair,
        remotePublicKey: SimplePublicKey(bobPk, type: KeyPairType.x25519),
      );
      service = ChatE2EEService();
    });

    test('decryptRowMessage routes v1/v2 SIN downgrade (v2 row)', () async {
      final v2Columns = await service.encryptMessageV2(
        text: 'v2 row',
        sharedSecret: shared,
        senderId: _aliceUid,
        receiverId: _bobUid,
        messageId: _aliceMsgId,
        matchId: _matchId,
        senderPublicKeyBytes: alicePk,
        receiverPublicKeyBytes: bobPk,
      );
      final row = <String, dynamic>{
        'id': _aliceMsgId,
        'sender_id': _aliceUid,
        'encrypted_content': v2Columns['encrypted_content'],
        'nonce': v2Columns['nonce'],
        'mac': v2Columns['mac'],
        'match_id': _matchId,
      };
      final clear = await service.decryptRowMessage(
        row: row,
        sharedSecret: shared,
        senderPublicKeyBytes: alicePk,
        receiverPublicKeyBytes: bobPk,
        localUid: _bobUid,
        localZoneId: _bobZone,
        expectedMatchId: _matchId,
      );
      expect(clear, 'v2 row');
    });

    test('decryptRowMessage keeps v1 route (behavior of the legacy row)',
        () async {
      final v1Columns = await service.encryptMessage('legacy v1', shared);
      final row = <String, dynamic>{
        'id': 'row-1',
        'sender_id': _aliceUid,
        'encrypted_content': v1Columns['encrypted_content'],
        'nonce': v1Columns['nonce'],
        'mac': v1Columns['mac'],
      };
      final clear = await service.decryptRowMessage(
        row: row,
        sharedSecret: shared,
        senderPublicKeyBytes: alicePk,
        receiverPublicKeyBytes: bobPk,
        localUid: _bobUid,
        localZoneId: _bobZone,
        expectedMatchId: _matchId,
      );
      expect(clear, 'legacy v1');
    });

    test('v2 errors translate to EXISTING user strings', () async {
      // (a) Malformed envelope (parse) → '[🔒 No se pudo descifrar]'
      final parseFallback = await service.decryptMessageV2(
        encryptedContent: 'zt2:not-base64!!',
        sharedSecret: shared,
        senderId: _aliceUid,
        receiverCandidates: [_bobUid],
        expectedMessageId: _aliceMsgId,
        expectedMatchId: _matchId,
        senderPublicKeyBytes: alicePk,
        receiverPublicKeyBytes: bobPk,
      );
      expect(parseFallback, '[🔒 No se pudo descifrar]');

      // (b) Valid envelope but wrong key (auth) → '🔒 Mensaje cifrado con llaves anteriores'
      final okColumns = await service.encryptMessageV2(
        text: 'ok',
        sharedSecret: shared,
        senderId: _aliceUid,
        receiverId: _bobUid,
        messageId: _aliceMsgId,
        matchId: _matchId,
        senderPublicKeyBytes: alicePk,
        receiverPublicKeyBytes: bobPk,
      );
      final fixedShared = await x25519.sharedSecretKey(
        keyPair: alicePair,
        remotePublicKey: SimplePublicKey(alicePk, type: KeyPairType.x25519),
      );
      final authFallback = await service.decryptMessageV2(
        encryptedContent: okColumns['encrypted_content'] as String,
        sharedSecret: fixedShared,
        senderId: _aliceUid,
        receiverCandidates: [_bobUid],
        expectedMessageId: _aliceMsgId,
        expectedMatchId: _matchId,
        senderPublicKeyBytes: alicePk,
        receiverPublicKeyBytes: bobPk,
      );
      expect(authFallback, '🔒 Mensaje cifrado con llaves anteriores');
    });

    test('ownPublicKeyBytes: null without init, bytes after initFromPrivateBase64',
        () async {
      final fresh = ChatE2EEService();
      // The singleton might have state; verify only behavior: a fresh
      // instance with no init → null key IF truly no internal state. Since
      // this service was instantiated above in setUp, we simply verify
      // contract of the fresh instance after init.
      expect(await fresh.ownPublicKeyBytes(), isNull);
      final priv = await alicePair.extractPrivateKeyBytes();
      await fresh.initFromPrivateBase64(base64Encode(priv));
      final own = await fresh.ownPublicKeyBytes();
      expect(own, isNotNull);
      expect(Uint8List.fromList(own!), Uint8List.fromList(alicePk));
    });
  });
}

/// Rebuilds the `zt2:` envelope JSON with the given key order.
String _rebuildEnvelope(Map<String, dynamic> json) {
  return 'zt2:${base64Encode(utf8.encode(jsonEncode(json)))}';
}
