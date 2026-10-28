/// FASE 2.1 — KAT oficial del fingerprint v1 (spec §6).
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Verifica los tres vectores oficiales (ACC, DEV-A, DEV-B/reinstall) cuya
/// reproducción independiente fue aprobada el 2026-09-25
/// (`PHASE_2.1_KAT_VERIFICATION_REPORT.md`):
///
///   1. input canónico (§3)  — hex exacto de los bytes
///   2. digest SHA-256 (§4.4)
///   3. bit-packing 5 bits/MSB-first (§4.4) — full Base32 de 52 + valores por
///      símbolo
///   4. mapeo al alfabeto propio (§4.3) — incl. índice 31 → `-`
///   5. truncado a 20 chars (§4.5) y display 4×5 (§4.6/§4.7)
///
/// El oráculo son los valores documentados calculados con implementaciones
/// independientes (Python/Node/.NET) — el test NO reimplementa el algoritmo
/// importando la implementación de producción de forma circular: compara la
/// salida del servicio contra constantes fijadas desde la verificación
/// independiente y además valida el alfabeto instrumento por instrumento.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/base32_unambiguous.dart';
import 'package:zone/identity/fingerprint_service.dart';
import 'package:zone/identity/identity_errors.dart';

/// Vector KAT oficial: parámetros + valores esperados (fuente: resolución §15
/// y `PHASE_2.1_KAT_VERIFICATION_REPORT.md` §4-§6).
class KatVector {
  const KatVector({
    required this.id,
    required this.kind,
    required this.accountId,
    required this.deviceId,
    required this.publicKeyBase64,
    required this.inputHex,
    required this.sha256Hex,
    required this.fullBase32,
    required this.text,
    required this.display,
  });

  final String id;
  final String kind;
  final String accountId;
  final String? deviceId;
  final String publicKeyBase64;
  final String inputHex;
  final String sha256Hex;
  final String fullBase32;
  final String text;
  final String display;

  List<int> get publicKeyBytes => base64Decode(publicKeyBase64);
}

const List<KatVector> kOfficialKatVectors = [
  KatVector(
    id: 'ACC',
    kind: 'ACC',
    accountId: '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d',
    deviceId: null,
    publicKeyBase64: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=',
    inputHex:
        '5a4f4e452d46502d310041434331613262336334642d356536662d376138622d396330642d31653266336134623563366441414543417751464267634943516f4c4441304f4478415245684d554652595847426b61477877644868383d',
    sha256Hex:
        '75d4923b5822e7a328c1f9843aba09a0377a4d4cf084daadcbcad6f6b239ac6c',
    fullBase32: 'GSCB6GVT6DNV8C83-845QGJBP2WSPNCEZ44FQDGDUDDHFEKUQKR2',
    text: 'GSCB6GVT6DNV8C83-845',
    display: 'GSCB6-GVT6D-NV8C8-3-845',
  ),
  KatVector(
    id: 'DEV-A',
    kind: 'DEV',
    accountId: '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d',
    deviceId: '2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7e',
    publicKeyBase64: '//79/Pv6+fj39vX08/Lx8O/u7ezr6uno5+bl5OPi4eA=',
    inputHex:
        '5a4f4e452d46502d310044455631613262336334642d356536662d376138622d396330642d31653266336134623563366432623363346435652d366637612d386239632d306431652d3266336134623563366437652f2f37392f5076362b666a3339765830382f4c78384f2f7537657a7236756e6f352b626c354f50693465413d',
    sha256Hex:
        '0ee57cce36b0be7de841085af92f8bf5db33421b61e28fc820037a77034ab0a9',
    fullBase32: '3WMSUNKRR4-9WV4333FHMDXDZSFN8JJWE9KA-M322FY9G2VCR4PJ',
    text: '3WMSUNKRR4-9WV4333FH',
    display: '3WMSU-NKRR4--9WV4-333FH',
  ),
  KatVector(
    id: 'DEV-B-reinstall',
    kind: 'DEV',
    accountId: '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d',
    deviceId: '3c4d5e6f-7a8b-9c0d-1e2f-3a4b5c6d7e8f',
    publicKeyBase64: 'gIGCg4SFhoeIiYqLjI2Oj5CRkpOUlZaXmJmam5ydnp8=',
    inputHex:
        '5a4f4e452d46502d310044455631613262336334642d356536662d376138622d396330642d31653266336134623563366433633464356536662d376138622d396330642d316532662d3361346235633664376538666749474367345346686f65496959714c6a49324f6a3543526b704f556c5a61586d4a6d616d3579646e70383d',
    sha256Hex:
        '9f51dd065a4c2804d55cf091b9b2bf2d772d61f374a8cadc59f77cc04121e4be',
    fullBase32: 'NYAYV3MVBJP2BQCXZ4AWNEQ-7QWMVTHNGMPEQS4UZYZE2JB3XM-2',
    text: 'NYAYV3MVBJP2BQCXZ4AW',
    display: 'NYAYV-3MVBJ-P2BQC-XZ4AW',
  ),
];

void main() {
  group('Alfabeto normativo (§4.2/§4.3)', () {
    const expectedMap = <int, String>{
      0: '2',
      1: '3',
      2: '4',
      3: '5',
      4: '6',
      5: '7',
      6: '8',
      7: '9',
      8: 'A',
      9: 'B',
      10: 'C',
      11: 'D',
      12: 'E',
      13: 'F',
      14: 'G',
      15: 'H',
      16: 'J',
      17: 'K',
      18: 'M',
      19: 'N',
      20: 'P',
      21: 'Q',
      22: 'R',
      23: 'S',
      24: 'T',
      25: 'U',
      26: 'V',
      27: 'W',
      28: 'X',
      29: 'Y',
      30: 'Z',
      31: '-',
    };

    test('32 símbolos únicos y biyección 0..31 exacta', () {
      final alphabet = kBase32UnambiguousAlphabet;
      expect(alphabet.length, 32);
      expect(alphabet.split('').toSet().length, 32);
      for (var i = 0; i < 32; i++) {
        expect(symbolForIndex(i), expectedMap[i], reason: 'index $i');
        expect(indexForSymbol(expectedMap[i]!), i, reason: 'symbol $i');
      }
    });

    test(
      '2^5 = 32 ⇒ todo valor de 5 bits 0..31 tiene exactamente un símbolo',
      () {
        expect(1 << 5, 32);
        for (var v = 0; v < 32; v++) {
          final s = symbolForIndex(v);
          expect(kBase32UnambiguousAlphabet.indexOf(s), v);
          expect(
            kBase32UnambiguousAlphabet.indexOf(s),
            kBase32UnambiguousAlphabet.lastIndexOf(s),
          );
        }
      },
    );

    test(
      'índice 31 = `-` (U+002D) y símbolos confundibles fuera del alfabeto',
      () {
        expect(symbolForIndex(31), '-');
        expect(indexForSymbol('-'), 31);
        expect('-'.codeUnitAt(0), 0x2d);
        for (final forbidden in ['0', '1', 'I', 'L', 'O']) {
          expect(
            () => indexForSymbol(forbidden),
            throwsA(isA<InvalidFingerprintInputError>()),
          );
        }
        expect(() => symbolForIndex(32), throwsArgumentError);
        expect(() => symbolForIndex(-1), throwsArgumentError);
      },
    );
  });

  group('KAT oficial (§6) — 3 vectores', () {
    for (final vector in kOfficialKatVectors) {
      test('${vector.id}: input, digest, bit-packing, mapeo, truncado y '
          'display coinciden con la verificación independiente', () async {
        final computation = vector.kind == 'ACC'
            ? await FingerprintService.accountFingerprint(
                accountId: vector.accountId,
                identityPublicKeyBytes: vector.publicKeyBytes,
              )
            : await FingerprintService.deviceFingerprint(
                accountId: vector.accountId,
                deviceId: vector.deviceId!,
                devicePublicKeyBytes: vector.publicKeyBytes,
              );

        // 1. Input canónico (§3): hex exacto de los bytes.
        expect(computation.kind, vector.kind);
        expect(
          computation.canonicalInputHex,
          vector.inputHex,
          reason: '${vector.id}: canonical input',
        );

        // 2. Digest SHA-256 (§4.4.1).
        expect(
          computation.sha256Hex,
          vector.sha256Hex,
          reason: '${vector.id}: sha256',
        );

        // 3. Bit-packing: 52 símbolos sin padding (§4.4.5).
        expect(
          computation.fullBase32,
          vector.fullBase32,
          reason: '${vector.id}: base32 full',
        );
        expect(computation.fullBase32.length, 52);
        expect(computation.fullBase32.contains('='), isFalse);

        // 4. Mapeo al alfabeto: cada símbolo se corresponde índice a índice.
        expect(computation.symbolIndices.length, 52);
        for (var i = 0; i < 52; i++) {
          expect(
            symbolForIndex(computation.symbolIndices[i]),
            computation.fullBase32[i],
            reason: '${vector.id}: symbol map at $i',
          );
          expect(
            indexForSymbol(computation.fullBase32[i]),
            computation.symbolIndices[i],
            reason: '${vector.id}: index map at $i',
          );
        }

        // 5. Truncado a 20 chars (§4.5) y display 4×5 (§4.6/§4.7).
        expect(computation.fullBase32.substring(0, 20), vector.text);
        expect(
          computation.text,
          vector.text,
          reason: '${vector.id}: fingerprint',
        );
        expect(
          computation.display,
          vector.display,
          reason: '${vector.id}: display',
        );
      });
    }

    test('cada vector ejerce el índice 31 → `-` en algún grupo', () {
      for (final vector in kOfficialKatVectors) {
        final full = vector.fullBase32;
        // fullBase32 es texto: los `-` que contiene son símbolos (índice 31).
        expect(
          _dashPositions(full).length,
          greaterThan(0),
          reason: '${vector.id} must contain at least one literal dash',
        );
        for (final pos in _dashPositions(full)) {
          expect(indexForSymbol(full[pos]), 31);
        }
      }
    });
  });

  group('Validación de entrada (§3/§4.9)', () {
    test('rechaza clave pública con longitud distinta de 32 bytes', () {
      expect(
        () => FingerprintService.accountFingerprint(
          accountId: kOfficialKatVectors.first.accountId,
          identityPublicKeyBytes: List<int>.filled(31, 0),
        ),
        throwsA(isA<InvalidFingerprintInputError>()),
      );
      expect(
        () => FingerprintService.accountFingerprint(
          accountId: kOfficialKatVectors.first.accountId,
          identityPublicKeyBytes: List<int>.filled(33, 0),
        ),
        throwsA(isA<InvalidFingerprintInputError>()),
      );
    });

    test('rechaza UUIDs no canónicos (no RFC 4122)', () {
      expect(
        () => FingerprintService.accountFingerprint(
          accountId: 'not-a-uuid',
          identityPublicKeyBytes: kOfficialKatVectors.first.publicKeyBytes,
        ),
        throwsA(isA<InvalidIdentityMetadataError>()),
      );
      expect(
        () => FingerprintService.deviceFingerprint(
          accountId: kOfficialKatVectors.first.accountId,
          deviceId: 'BAD',
          devicePublicKeyBytes: kOfficialKatVectors.first.publicKeyBytes,
        ),
        throwsA(isA<InvalidIdentityMetadataError>()),
      );
    });

    test(
      'acepta UUID canónico en minúsculas y lo canonicaliza igual',
      () async {
        final upper = await FingerprintService.accountFingerprint(
          accountId: '1A2B3C4D-5E6F-7A8B-9C0D-1E2F3A4B5C6D',
          identityPublicKeyBytes: kOfficialKatVectors.first.publicKeyBytes,
        );
        final lower = await FingerprintService.accountFingerprint(
          accountId: kOfficialKatVectors.first.accountId,
          identityPublicKeyBytes: kOfficialKatVectors.first.publicKeyBytes,
        );
        expect(
          upper.canonicalInputHex,
          lower.canonicalInputHex,
          reason: 'uuidCanonical lowercases (RFC 4122 text)',
        );
      },
    );
  });
}

List<int> _dashPositions(String text) {
  return [
    for (var i = 0; i < text.length; i++)
      if (text[i] == '-') i,
  ];
}
