/// PHASE G — `device_certificate_v2` (fundación migración dispositivo).
///
/// Cobertura:
/// 1. Roundtrip issue→verify (payload fiel, deterministic seeds).
/// 2. Forma: payload NO canónico → rechazo ANTES de la firma.
/// 3. Ventana: exp pasado → 'expired'; exp <= iat → 'validity' en emisión.
/// 4. Firma manipulada → 'signature'.
/// 5. Binding de fingerprint por DOS rutas: fp fabricado en issue, y cert
///    auto-consistente RE-FIRMADO con fp fabricado (verify recomputa —
///    no depende de la honestidad del emisor).
/// 6. Ancla caller-side: pk de cuenta expuesta para comparar contra la
///    ancla conocida (límite documentado del cert autónomo).
/// 7. Clasificación isV2Certificate + erorres tipados UI-safe.
///
/// Fixture: seeds determinísticos propios (los KAT RFC viven en
/// test/e2ee/e2ee_kat_test.dart). PROBADO LOCALMENTE (unidades).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zone/crypto/e2ee_message_crypto.dart' show canonicalJsonString;
import 'package:zone/identity/canonical.dart';
import 'package:zone/identity/device_certificate_v2.dart';
import 'package:zone/identity/ed25519_identity_service.dart';
import 'package:zone/identity/fingerprint_service.dart';

const String _accountId = '11111111-1111-4111-8111-111111111111';
const String _deviceId = '22222222-2222-4222-8222-222222222222';

List<int> _seed(int fill) => List<int>.filled(32, fill);

/// Bytes de la clave pública X25519 del dispositivo (fixture determinístico
/// de 32 bytes — el certificado solo exige 32 bytes ligados al fingerprint).
Future<List<int>> _deviceX25519PublicKey() async {
  final pair = await X25519().newKeyPairFromSeed(
    List<int>.generate(32, (i) => (i * 7 + 3) & 0xFF),
  );
  return Uint8List.fromList((await pair.extractPublicKey()).bytes);
}

/// Serializa el payload EXACTAMENTE como DeviceCertificateV2 (misma forma
/// canónica compartida vía [canonicalJsonString] — única verdad del formato).
String _canonicalPayloadJson({
  required String accountId,
  required String deviceId,
  required String fp,
  required String x25519B64,
  required String acctEdB64,
  required String iat,
  required String exp,
}) {
  return '{'
      '"v":2,'
      '"account_id":${canonicalJsonString(accountId)},'
      '"device_id":${canonicalJsonString(deviceId)},'
      '"fp":${canonicalJsonString(fp)},'
      '"x25519":${canonicalJsonString(x25519B64)},'
      '"acct_ed25519":${canonicalJsonString(acctEdB64)},'
      '"iat":${canonicalJsonString(iat)},'
      '"exp":${canonicalJsonString(exp)}'
      '}';
}

String _envelopeJson({
  required String p,
  required String s,
}) =>
    jsonEncode(<String, dynamic>{'p': p, 's': s});

/// Re-emite un cert a mano: firma [payloadJson] como JSON canónico con
/// [signerKeyPair] y declara su propia pk (cert AUTO-consistente — necesario
/// para probar la ruta fp-binding de verify, no solo canonicalidad).
Future<String> _selfConsistentCert({
  required Map<String, dynamic> payloadOverrides,
  required SimpleKeyPair signerKeyPair,
  String? canonicalPayloadInstead,
  String? signatureInstead,
}) async {
  final payloadString = canonicalPayloadInstead ??
      _canonicalPayloadJson(
        accountId: _accountId,
        deviceId: _deviceId,
        fp: (await FingerprintService.deviceFingerprint(
          accountId: _accountId,
          deviceId: _deviceId,
          devicePublicKeyBytes: await _deviceX25519PublicKey(),
        ))
            .sha256Hex,
        x25519B64: CanonicalCodec.base64StdPadded(
          await _deviceX25519PublicKey(),
        ),
        acctEdB64: CanonicalCodec.base64StdPadded(
          (await signerKeyPair.extractPublicKey()).bytes,
        ),
        iat: payloadOverrides['iat'] as String? ??
            DateTime.now().toUtc().toIso8601String(),
        exp: payloadOverrides['exp'] as String? ??
            DateTime.now().toUtc().add(const Duration(days: 1))
                .toIso8601String(),
      );
  final signature = signatureInstead ??
      CanonicalCodec.base64StdPadded(
        await Ed25519IdentityService.sign(
          signerKeyPair,
          CanonicalCodec.utf8Bytes(payloadString),
        ),
      );
  final envelope = _envelopeJson(p: payloadString, s: signature);
  return '$kDeviceCertV2Prefix${base64Encode(utf8.encode(envelope))}';
}

void main() {
  group('device_certificate_v2 — roundtrip issue/verify', () {
    late SimpleKeyPair accountKeyPair;
    late List<int> devicePk;
    late String fingerprintHex;
    late String certificate;

    setUp(() async {
      accountKeyPair = await Ed25519IdentityService.keyPairFromSeed(
        _seed(0x11),
      );
      devicePk = await _deviceX25519PublicKey();
      fingerprintHex = (await FingerprintService.deviceFingerprint(
        accountId: _accountId,
        deviceId: _deviceId,
        devicePublicKeyBytes: devicePk,
      ))
          .sha256Hex;
      final now = DateTime.now().toUtc();
      certificate = await DeviceCertificateV2.issue(
        accountIdentityKeyPair: accountKeyPair,
        accountId: _accountId,
        deviceId: _deviceId,
        deviceX25519PublicKeyBytes: devicePk,
        fingerprintSha256Hex: fingerprintHex,
        issuedAt: now,
        expiresAt: now.add(kDeviceCertV2DefaultValidity),
      );
    });

    test('verify OK y payload fiel (32B keys, uuid, fp, ventana)', () async {
      expect(DeviceCertificateV2.isV2Certificate(certificate), isTrue);
      expect(certificate.startsWith(kDeviceCertV2Prefix), isTrue);
      final payload = await DeviceCertificateV2.verify(certificate);
      expect(payload.accountId, _accountId);
      expect(payload.deviceId, _deviceId);
      expect(payload.fingerprintSha256Hex, fingerprintHex);
      expect(
        payload.x25519PublicKeyBase64,
        CanonicalCodec.base64StdPadded(devicePk),
      );
      expect(
        payload.accountIdentityEd25519Base64,
        await Ed25519IdentityService.publicKeyBase64(accountKeyPair),
      );
      expect(payload.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
      expect(
        payload.expiresAt
            .difference(payload.issuedAt)
            .inDays,
        365,
      );
    });
  });

  group('device_certificate_v2 — fail-closed matrix', () {
    late SimpleKeyPair accountKeyPair;
    late List<int> devicePk;
    late String fingerprintHex;
    late String validCertificate;

    setUp(() async {
      accountKeyPair = await Ed25519IdentityService.keyPairFromSeed(
        _seed(0x22),
      );
      devicePk = await _deviceX25519PublicKey();
      fingerprintHex = (await FingerprintService.deviceFingerprint(
        accountId: _accountId,
        deviceId: _deviceId,
        devicePublicKeyBytes: devicePk,
      ))
          .sha256Hex;
      final now = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      validCertificate = await DeviceCertificateV2.issue(
        accountIdentityKeyPair: accountKeyPair,
        accountId: _accountId,
        deviceId: _deviceId,
        deviceX25519PublicKeyBytes: devicePk,
        fingerprintSha256Hex: fingerprintHex,
        issuedAt: now,
        expiresAt: now.add(const Duration(days: 1)),
      );
    });

    Map<String, dynamic> parseEnvelope(String cert) {
      final envelopeRaw = utf8.decode(
        base64Decode(cert.substring(kDeviceCertV2Prefix.length)),
      );
      return jsonDecode(envelopeRaw) as Map<String, dynamic>;
    }

    test('malformed envelope → typed rejection (prefix / base64 / json)', () {
      expect(
        () => DeviceCertificateV2.verify('jsonwebtoken:otro'),
        throwsA(
          isA<DeviceCertificateV2Error>()
              .having((e) => e.reason, 'reason', 'prefix'),
        ),
      );
      expect(
        () => DeviceCertificateV2.verify('$kDeviceCertV2Prefix!!!base64!'),
        throwsA(isA<DeviceCertificateV2Error>()),
      );
      expect(
        () => DeviceCertificateV2.verify(
          '$kDeviceCertV2Prefix${base64Encode('no-json'.codeUnits)}',
        ),
        throwsA(
          isA<DeviceCertificateV2Error>()
              .having((e) => e.reason, 'reason', 'json'),
        ),
      );
    });

    test('isV2Certificate classifies fail-closed', () {
      expect(DeviceCertificateV2.isV2Certificate(validCertificate), isTrue);
      expect(DeviceCertificateV2.isV2Certificate('ZDC2:x'), isTrue);
      expect(DeviceCertificateV2.isV2Certificate('jwt:otro'), isFalse);
      expect(DeviceCertificateV2.isV2Certificate(null), isFalse);
    });

    test('expired → rejected (verify, zero tolerance)', () async {
      final expired = await DeviceCertificateV2.issue(
        accountIdentityKeyPair: accountKeyPair,
        accountId: _accountId,
        deviceId: _deviceId,
        deviceX25519PublicKeyBytes: devicePk,
        fingerprintSha256Hex: fingerprintHex,
        issuedAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
        expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      );
      expect(
        () => DeviceCertificateV2.verify(expired),
        throwsA(
          isA<DeviceCertificateV2Error>()
              .having((e) => e.reason, 'reason', 'expired'),
        ),
      );
    });

    test('exp <= iat → rejected AT ISSUE', () {
      final now = DateTime.now().toUtc();
      expect(
        DeviceCertificateV2.issue(
          accountIdentityKeyPair: accountKeyPair,
          accountId: _accountId,
          deviceId: _deviceId,
          deviceX25519PublicKeyBytes: devicePk,
          fingerprintSha256Hex: fingerprintHex,
          issuedAt: now,
          expiresAt: now, // exp == iat
        ),
        throwsA(
          isA<DeviceCertificateV2Error>()
              .having((e) => e.reason, 'reason', 'validity'),
        ),
      );
    });

    test('fabricated fp → rejected AT ISSUE', () {
      final now = DateTime.now().toUtc();
      expect(
        DeviceCertificateV2.issue(
          accountIdentityKeyPair: accountKeyPair,
          accountId: _accountId,
          deviceId: _deviceId,
          deviceX25519PublicKeyBytes: devicePk,
          fingerprintSha256Hex: 'a' * 64,
          issuedAt: now,
          expiresAt: now.add(const Duration(days: 1)),
        ),
        throwsA(
          isA<DeviceCertificateV2Error>()
              .having((e) => e.reason, 'reason', 'fingerprint'),
        ),
      );
    });

    test('self-consistent cert con fp fabricado → verify RECOMPUTA y rechaza',
        () async {
      final forged = await _selfConsistentCert(
        payloadOverrides: const <String, dynamic>{},
        signerKeyPair: accountKeyPair,
        canonicalPayloadInstead: _canonicalPayloadJson(
          accountId: _accountId,
          deviceId: _deviceId,
          fp: 'b' * 64, // fp fabricado — cert SELF-consistent
          x25519B64: CanonicalCodec.base64StdPadded(devicePk),
          acctEdB64: await Ed25519IdentityService.publicKeyBase64(
            accountKeyPair,
          ),
          iat: DateTime.now().toUtc().toIso8601String(),
          exp: DateTime.now()
              .toUtc()
              .add(const Duration(days: 1))
              .toIso8601String(),
        ),
      );
      expect(
        () => DeviceCertificateV2.verify(forged),
        throwsA(
          isA<DeviceCertificateV2Error>()
              .having((e) => e.reason, 'reason', 'fingerprint'),
        ),
      );
    });

    test(
        'tampered payload VALUE (sin re-firmar) → firma NO matchea → signature',
        () {
      final parsed = parseEnvelope(validCertificate);
      final payload = jsonDecode(parsed['p'] as String) as Map<String, dynamic>;
      payload['fp'] = 'c' * 64;
      // The modified p STILL IS form-canonical (canonicalidad checks FORM AND
      // ORDER, no values): the manipulation of VALUES is caught by the
      // signature (it covers the exact bytes of the old payload).
      final envelope = jsonEncode(<String, dynamic>{
        'p': jsonEncode(payload),
        's': parsed['s'],
      });
      expect(
        () => DeviceCertificateV2.verify(
          '$kDeviceCertV2Prefix${base64Encode(utf8.encode(envelope))}',
        ),
        throwsA(
          isA<DeviceCertificateV2Error>()
              .having((e) => e.reason, 'reason', 'signature'),
        ),
      );
    });

    test('payload re-ordenado → rechazo canónico (no silencioso)', () {
      final parsed = parseEnvelope(validCertificate);
      final payload = jsonDecode(parsed['p'] as String) as Map<String, dynamic>;
      final reordered = <String, dynamic>{};
      for (final entry in payload.entries.toList().reversed) {
        reordered[entry.key] = entry.value;
      }
      final envelope = jsonEncode(<String, dynamic>{
        'p': jsonEncode(reordered),
        's': parsed['s'],
      });
      expect(
        () => DeviceCertificateV2.verify(
          '$kDeviceCertV2Prefix${base64Encode(utf8.encode(envelope))}',
        ),
        throwsA(
          isA<DeviceCertificateV2Error>()
              .having((e) => e.reason, 'reason', 'canonical'),
        ),
      );
    });

    test('signature bit-flip → rejected typed (signature)', () {
      final parsed = parseEnvelope(validCertificate);
      final sigBytes = base64Decode(parsed['s'] as String);
      sigBytes[0] = sigBytes[0] ^ 0x01;
      final envelope = _envelopeJson(
        p: parsed['p'] as String,
        s: base64Encode(sigBytes),
      );
      expect(
        () => DeviceCertificateV2.verify(
          '$kDeviceCertV2Prefix${base64Encode(utf8.encode(envelope))}',
        ),
        throwsA(
          isA<DeviceCertificateV2Error>()
              .having((e) => e.reason, 'reason', 'signature'),
        ),
      );
    });

    test('signature void → rejected typed (no exception bypass)', () {
      final parsed = parseEnvelope(validCertificate);
      final envelope = _envelopeJson(
        p: parsed['p'] as String,
        s: base64Encode(List<int>.filled(64, 0x00)),
      );
      expect(
        () => DeviceCertificateV2.verify(
          '$kDeviceCertV2Prefix${base64Encode(utf8.encode(envelope))}',
        ),
        throwsA(
          isA<DeviceCertificateV2Error>()
              .having((e) => e.reason, 'reason', 'signature'),
        ),
      );
    });
  });

  group('device_certificate_v2 — caller-side anchor contract', () {
    test('payload exposes account pk to compare against the KNOWN anchor',
        () async {
      final accountA = await Ed25519IdentityService.keyPairFromSeed(
        _seed(0x33),
      );
      final accountB = await Ed25519IdentityService.keyPairFromSeed(
        _seed(0x44),
      );
      final devicePk = await _deviceX25519PublicKey();
      final fp = (await FingerprintService.deviceFingerprint(
        accountId: _accountId,
        deviceId: _deviceId,
        devicePublicKeyBytes: devicePk,
      ))
          .sha256Hex;
      final now = DateTime.now().toUtc();
      final cert = await DeviceCertificateV2.issue(
        accountIdentityKeyPair: accountA,
        accountId: _accountId,
        deviceId: _deviceId,
        deviceX25519PublicKeyBytes: devicePk,
        fingerprintSha256Hex: fp,
        issuedAt: now,
        expiresAt: now.add(const Duration(days: 1)),
      );
      final payload = await DeviceCertificateV2.verify(cert);

      // Caller compares against ITS known anchor (not blind trust).
      final anchorA = await Ed25519IdentityService.publicKeyBase64(accountA);
      final anchorB = await Ed25519IdentityService.publicKeyBase64(accountB);
      expect(payload.accountIdentityEd25519Base64, anchorA);
      expect(payload.accountIdentityEd25519Base64, isNot(anchorB));
    });
  });

  group('device_certificate_v2 — typed error (UI-safe)', () {
    test('never leaks key material', () {
      const err = DeviceCertificateV2Error('signature', 'x');
      final text = err.toString();
      expect(text, contains('signature'));
      expect(text.contains('BEGIN'), isFalse);
      expect(text.contains('base64'), isFalse);
    });
  });
}
