/// KATs (known-answer tests) of the KAT PRFs — PHASE G §7.1.
///
/// Primary sources (official rfc-editor.org text, fetched 2026-10-27):
/// - RFC 5869 §A.1–§A.3 (HKDF-SHA256)
/// - RFC 8439 §2.8.2 (AEAD_CHACHA20_POLY1305)
/// - RFC 7748 §6.1 (X25519 Diffie-Hellman)
/// - RFC 8032 §7.1 (Ed25519 TEST 1/2/3)
///
/// Rule of the house: the stack is NOT deemed safe without KAT. These tests
/// exercise the exact algorithms used by v2 (package:cryptography): `Hkdf`,
/// `Chacha20.poly1305Aead`, `X25519`, `Ed25519`.
///
/// Label: PROBADO LOCALLY (unit, no backend).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zone/crypto/e2ee_message_crypto.dart';

Uint8List _hex(String hex) {
  final clean = hex.replaceAll(RegExp('[^0-9a-fA-F]'), '');
  if (clean.length.isOdd) throw ArgumentError('odd hex: $hex');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _expectHex(String hex) => _hex(hex);

void main() {
  group('KAT RFC 5869 — HKDF-SHA256 (via package Hkdf, v2 parameters)', () {
    Future<Uint8List> okm(Uint8List ikm, Uint8List salt, Uint8List info, int l) async {
      final kdf = Hkdf(hmac: Hmac.sha256(), outputLength: l);
      final key = await kdf.deriveKey(
        secretKey: SecretKey(ikm),
        nonce: salt,
        info: info,
      );
      final bytes = await key.extractBytes();
      return Uint8List.fromList(bytes);
    }

    test('Case 1 (basic)', () async {
      final ikm = _hex('0b' * 22);
      final salt = _hex('000102030405060708090a0b0c');
      final info = _hex('f0f1f2f3f4f5f6f7f8f9');

      // Extract step (PRK), RFC 5869 §A.1.
      final prk = await Hmac.sha256().calculateMac(
        ikm,
        secretKey: SecretKey(salt),
      );
      expect(
        _hexOf(prk.bytes),
        '077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5',
        reason: 'PRK (Case 1)',
      );

      // Expand step (OKM), RFC 5869 §A.1.
      final result = await okm(ikm, salt, info, 42);
      expect(
        result,
        _expectHex(
          '3cb25f25faacd57a90434f64d0362f2a'
          '2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
          '34007208d5b887185865',
        ),
        reason: 'OKM (Case 1, 42 octets)',
      );
    });

    test('Case 2 (long inputs/outputs, 82 octets)', () async {
      final result = await okm(
        _hex(
          '000102030405060708090a0b0c0d0e0f'
          '101112131415161718191a1b1c1d1e1f'
          '202122232425262728292a2b2c2d2e2f'
          '303132333435363738393a3b3c3d3e3f'
          '404142434445464748494a4b4c4d4e4f',
        ),
        _hex(
          '606162636465666768696a6b6c6d6e6f'
          '707172737475767778797a7b7c7d7e7f'
          '808182838485868788898a8b8c8d8e8f'
          '909192939495969798999a9b9c9d9e9f'
          'a0a1a2a3a4a5a6a7a8a9aaabacadaeaf',
        ),
        _hex(
          'b0b1b2b3b4b5b6b7b8b9babbbcbdbebf'
          'c0c1c2c3c4c5c6c7c8c9cacbcccdcecf'
          'd0d1d2d3d4d5d6d7d8d9dadbdcdddedf'
          'e0e1e2e3e4e5e6e7e8e9eaebecedeeef'
          'f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff',
        ),
        82,
      );
      expect(
        result,
        _expectHex(
          'b11e398dc80327a1c8e7f78c596a4934'
          '4f012eda2d4efad8a050cc4c19afa97c'
          '59045a99cac7827271cb41c65e590e09'
          'da3275600c2f09b8367793a9aca3db71'
          'cc30c58179ec3e87c14c01d5c1f3434f'
          '1d87',
        ),
        reason: 'OKM (Case 2, 82 octets)',
      );
    });

    test('Case 3 (salt/info zero length)', () async {
      final result = await okm(
        _hex('0b' * 22),
        Uint8List(0),
        Uint8List(0),
        42,
      );
      expect(
        result,
        _expectHex(
          '8da4e775a563c18f715f802a063c5a31'
          'b8a11f5c5ee1879ec3454e5f3c738d2d'
          '9d201395faa4b61a96c8',
        ),
        reason: 'OKM (Case 3, 42 octets)',
      );
    });
  });

  group('KAT RFC 8439 §2.8.2 — AEAD_CHACHA20_POLY1305', () {
    test('exact ciphertext + tag, and reverse direction', () async {
      final key = SecretKey(_hex(
        '808182838485868788898a8b8c8d8e8f'
        '909192939495969798999a9b9c9d9e9f',
      ));
      final nonce = _hex('070000004041424344454647');
      final aad = _hex('50515253c0c1c2c3c4c5c6c7');
      const plaintext =
          "Ladies and Gentlemen of the class of '99: If I could offer you "
          'only one tip for the future, sunscreen would be it.';

      final chacha = Chacha20.poly1305Aead();
      final box = await chacha.encrypt(
        utf8.encode(plaintext),
        secretKey: key,
        nonce: nonce,
        aad: aad,
      );

      expect(
        _hexOf(box.cipherText),
        'd31a8d34648e60db7b86afbc53ef7ec2'
        'a4aded51296e08fea9e2b5a736ee62d6'
        '3dbea45e8ca9671282fafb69da92728b'
        '1a71de0a9e060b2905d6a5b67ecd3b36'
        '92ddbd7f2d778b8c9803aee328091b58'
        'fab324e4fad675945585808b4831d7bc'
        '3ff4def08e4b7a9de576d26586cec64b'
        '6116',
        reason: 'ciphertext RFC 8439 §2.8.2',
      );
      expect(
        _hexOf(box.mac.bytes),
        '1ae10b594f09e26a7e902ecbd0600691',
        reason: 'Poly1305 tag RFC 8439 §2.8.2',
      );

      final open = await chacha.decrypt(
        SecretBox(box.cipherText, nonce: nonce, mac: box.mac),
        secretKey: key,
        aad: aad,
      );
      expect(utf8.decode(open), plaintext);
    });
  });

  group('KAT RFC 7748 §6.1 — X25519 Diffie-Hellman', () {
    test('seed→pk and DH in both directions', () async {
      final aliceSeed = _hex(
        '77076d0a7318a57d3c16c17251b26645'
        'df4c2f87ebc0992ab177fba51db92c2a',
      );
      final bobSeed = _hex(
        '5dab087e624a8a4b79e17f8b83800ee6'
        '6f3bb1292618b6fd1c2f8b27ff88e0eb',
      );
      final alicePkExpected = _hex(
        '8520f0098930a754748b7ddcb43ef75a'
        '0dbf3a0d26381af4eba4a98eaa9b4e6a',
      );
      final bobPkExpected = _hex(
        'de9edb7d7b7dc1b4d35b61c2ece43537'
        '3f8343c85b78674dadfc7e146f882b4f',
      );
      final sharedExpected = _hex(
        '4a5d9d5ba4ce2de1728e3bf480350f25'
        'e07e21c947d19e3376f09b3c1e161742',
      );

      final x25519 = X25519();
      final alice = await x25519.newKeyPairFromSeed(aliceSeed);
      final bob = await x25519.newKeyPairFromSeed(bobSeed);

      final alicePk = (await alice.extractPublicKey()).bytes;
      final bobPk = (await bob.extractPublicKey()).bytes;
      expect(Uint8List.fromList(alicePk), alicePkExpected);
      expect(Uint8List.fromList(bobPk), bobPkExpected);

      final k1 = await x25519.sharedSecretKey(
        keyPair: alice,
        remotePublicKey:
            SimplePublicKey(bobPk, type: KeyPairType.x25519),
      );
      final k2 = await x25519.sharedSecretKey(
        keyPair: bob,
        remotePublicKey:
            SimplePublicKey(alicePk, type: KeyPairType.x25519),
      );
      final k1Bytes = Uint8List.fromList(await k1.extractBytes());
      final k2Bytes = Uint8List.fromList(await k2.extractBytes());
      expect(k1Bytes, sharedExpected, reason: 'K (A←B)');
      expect(k2Bytes, sharedExpected, reason: 'K (B←A) symmetric');
    });
  });

  group('KAT RFC 8032 §7.1 — Ed25519 (TEST 1/2/3)', () {
    test('TEST 1 (empty message): seed→pk, sign, verify', () async {
      final ed = Ed25519();
      final pair = await ed.newKeyPairFromSeed(_hex(
        '9d61b19deffd5a60ba844af492ec2cc4'
        '4449c5697b326919703bac031cae7f60',
      ));
      final pk = Uint8List.fromList((await pair.extractPublicKey()).bytes);
      expect(
        pk,
        _expectHex(
          'd75a980182b10ab7d54bfed3c964073a'
          '0ee172f3daa62325af021a68f707511a',
        ),
      );
      final sig = await ed.sign(const <int>[], keyPair: pair);
      expect(
        _hexOf(sig.bytes),
        'e5564300c360ac729086e2cc806e828a'
        '84877f1eb8e5d974d873e06522490155'
        '5fb8821590a33bacc61e39701cf9b46b'
        'd25bf5f0595bbe24655141438e7a100b',
      );
      // Independent verification: RAW vector signature bytes + pk
      // (not the produced object), per KAT principles.
      final vectorSig = _hex(
        'e5564300c360ac729086e2cc806e828a'
        '84877f1eb8e5d974d873e06522490155'
        '5fb8821590a33bacc61e39701cf9b46b'
        'd25bf5f0595bbe24655141438e7a100b',
      );
      final ok = await ed.verify(
        const <int>[],
        signature: Signature(
          vectorSig,
          publicKey: SimplePublicKey(pk, type: KeyPairType.ed25519),
        ),
      );
      expect(ok, isTrue);
    });

    test('TEST 2 (message 0x72): sign and verify', () async {
      final ed = Ed25519();
      final pair = await ed.newKeyPairFromSeed(_hex(
        '4ccd089b28ff96da9db6c346ec114e0f'
        '5b8a319f35aba624da8cf6ed4fb8a6fb',
      ));
      final pk = Uint8List.fromList((await pair.extractPublicKey()).bytes);
      expect(
        pk,
        _expectHex(
          '3d4017c3e843895a92b70aa74d1b7ebc'
          '9c982ccf2ec4968cc0cd55f12af4660c',
        ),
      );
      final sig = await ed.sign(_hex('72'), keyPair: pair);
      expect(
        _hexOf(sig.bytes),
        '92a009a9f0d4cab8720e820b5f642540'
        'a2b27b5416503f8fb3762223ebdb69da'
        '085ac1e43e15996e458f3613d0f11d8c'
        '387b2eaeb4302aeeb00d291612bb0c00',
      );
      final vectorSig = _hex(
        '92a009a9f0d4cab8720e820b5f642540'
        'a2b27b5416503f8fb3762223ebdb69da'
        '085ac1e43e15996e458f3613d0f11d8c'
        '387b2eaeb4302aeeb00d291612bb0c00',
      );
      final ok = await ed.verify(
        _hex('72'),
        signature: Signature(
          vectorSig,
          publicKey: SimplePublicKey(pk, type: KeyPairType.ed25519),
        ),
      );
      expect(ok, isTrue);
    });

    test('TEST 3 (message af82): sign and verify', () async {
      final ed = Ed25519();
      final pair = await ed.newKeyPairFromSeed(_hex(
        'c5aa8df43f9f837bedb7442f31dcb7b1'
        '66d38535076f094b85ce3a2e0b4458f7',
      ));
      final pk = Uint8List.fromList((await pair.extractPublicKey()).bytes);
      expect(
        pk,
        _expectHex(
          'fc51cd8e6218a1a38da47ed00230f058'
          '0816ed13ba3303ac5deb911548908025',
        ),
      );
      final sig = await ed.sign(_hex('af82'), keyPair: pair);
      expect(
        _hexOf(sig.bytes),
        '6291d657deec24024827e69c3abe01a3'
        '0ce548a284743a445e3680d7db5ac3ac'
        '18ff9b538d16f290ae67f760984dc659'
        '4a7c15e9716ed28dc027beceea1ec40a',
      );
      final vectorSig = _hex(
        '6291d657deec24024827e69c3abe01a3'
        '0ce548a284743a445e3680d7db5ac3ac'
        '18ff9b538d16f290ae67f760984dc659'
        '4a7c15e9716ed28dc027beceea1ec40a',
      );
      final ok = await ed.verify(
        _hex('af82'),
        signature: Signature(
          vectorSig,
          publicKey: SimplePublicKey(pk, type: KeyPairType.ed25519),
        ),
      );
      expect(ok, isTrue);
    });
  });

  group('Format of ZONE-E2EE-V2', () {
    test('canonical AAD — exact literal form', () {
      final aad = E2eeMessageCryptoV2.canonicalAadJsonFor(
        senderId: 'ZONE-AAAAAAAA',
        receiverId: 'ZONE-BBBBBBBB',
        messageId: 'm-1',
        matchId: 'match-1',
      );
      expect(
        aad,
        '{"v":2,"s":"ZONE-AAAAAAAA","r":"ZONE-BBBBBBBB",'
        '"m":"m-1","i":"match-1"}',
        reason: 'fixed order of keys documented in the header',
      );
    });

    test('AAD has no concatenation ambiguity (quotes/commas/braces survive)', () {
      const sender = 'a"x';
      const receiver = 'b,';
      const messageId = 'm}1';
      const matchId = 'i,"';
      final aad = E2eeMessageCryptoV2.canonicalAadJsonFor(
        senderId: sender,
        receiverId: receiver,
        messageId: messageId,
        matchId: matchId,
      );
      // Semantic (roundtrip) and structural assertion (one prefix field).
      final map = jsonDecode(aad) as Map<String, dynamic>;
      expect(map, {
        'v': 2,
        's': sender,
        'r': receiver,
        'm': messageId,
        'i': matchId,
      });
      expect(aad.startsWith('{"v":2,"s":"'), isTrue);
    });

    test('canonical direction: lexically smaller id is A', () {
      expect(
        E2eeMessageCryptoV2.directionSuffix('ZONE-AAAAAAAA', 'ZONE-BBBBBBBB'),
        'A2B',
      );
      expect(
        E2eeMessageCryptoV2.directionSuffix('ZONE-BBBBBBBB', 'ZONE-AAAAAAAA'),
        'B2A',
      );
    });

    test('isV2Envelope classifies fail-closed', () {
      expect(E2eeMessageCryptoV2.isV2Envelope('zt2:eyJ2Ij'), isTrue);
      expect(E2eeMessageCryptoV2.isV2Envelope(null), isFalse);
      expect(E2eeMessageCryptoV2.isV2Envelope('abc'), isFalse);
      expect(E2eeMessageCryptoV2.isV2Envelope('ZT2:eyJ2Ij'), isFalse,
          reason: 'prefix is case-sensitive by contract');
    });

    String zenvelope(Map<String, dynamic> json) =>
        'zt2:${base64Encode(utf8.encode(jsonEncode(json)))}';

    test('parseEnvelope fail-closed: version / aad_profile / lengths / fields',
        () async {
      final n12 = base64Encode(List.filled(12, 1));
      final t = base64Encode(List.filled(16, 2));

      expect(
        () => E2eeMessageCryptoV2.parseEnvelope('not-zt2'),
        throwsA(isA<E2eeV2ParseError>()),
      );

      for (final bad in <Map<String, dynamic>>[
        // unsupported version
        {'v': 3, 's': 'a', 'r': 'b', 'm': '1', 'i': '2',
          'n': n12, 't': t, 'h': 'AA', 'ap': 2},
        // unsupported AAD profile
        {'v': 2, 's': 'a', 'r': 'b', 'm': '1', 'i': '2',
          'n': n12, 't': t, 'h': 'AA', 'ap': 1},
        // nonce shorter than 12 bytes
        {'v': 2, 's': 'a', 'r': 'b', 'm': '1', 'i': '2',
          'n': 'AAAA', 't': t, 'h': 'AA', 'ap': 2},
        // missing ciphertext field
        {'v': 2, 's': 'a', 'r': 'b', 'm': '1', 'i': '2',
          'n': n12, 'h': 'AA', 'ap': 2},
        // missing mac
        {'v': 2, 's': 'a', 'r': 'b', 'm': '1', 'i': '2',
          'n': n12, 't': t, 'ap': 2},
        // missing sender
        {'v': 2, 'r': 'b', 'm': '1', 'i': '2',
          'n': n12, 't': t, 'h': 'AA', 'ap': 2},
        // not an object
        <String, dynamic>{},
      ]) {
        expect(
          () => E2eeMessageCryptoV2.parseEnvelope(zenvelope(bad)),
          throwsA(isA<E2eeV2ParseError>()),
          reason: 'must fail-closed: $bad',
        );
      }

      // JSON malicious not base64
      expect(
        () => E2eeMessageCryptoV2.parseEnvelope('zt2:not-base64!!'),
        throwsA(isA<E2eeV2ParseError>()),
      );
    });
  });
}
