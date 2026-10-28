/// FASE 2.1 — Normalización y validación de fingerprints (spec §4.7/§4.8/§4.9).
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Cubre la desagrupación posicional (solo separadores fijos 5/11/17; los `-`
/// literales se conservan), la ingesta case-insensitive, la validación estricta
/// (longitudes ≠ 20/23, separadores mal situados o símbolos fuera del alfabeto ⇒
/// rechazo — §4.9) y la comparación byte a byte de formas canónicas.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/base32_unambiguous.dart';
import 'package:zone/identity/identity_errors.dart';

void main() {
  group('Desagrupación posicional (§4.7) y normalización (§4.8)', () {
    test('canónico con `-` literal se conserva intacto', () {
      expect(
        normalizeFingerprint('GSCB6GVT6DNV8C83-845'),
        'GSCB6GVT6DNV8C83-845',
      );
    });

    test('display ACC → canónico (los separadores fijos se eliminan)', () {
      expect(
        normalizeFingerprint('GSCB6-GVT6D-NV8C8-3-845'),
        'GSCB6GVT6DNV8C83-845',
      );
    });

    test('ejemplo del spec §4.7: `-` literal adyacente a separador', () {
      // `3WMSU-NKRR4--9WV4-333FH` (el `-` literal del grupo 3 precede al
      // separador tras el 10º carácter) → `3WMSUNKRR4-9WV4333FH`.
      expect(
        normalizeFingerprint('3WMSU-NKRR4--9WV4-333FH'),
        '3WMSUNKRR4-9WV4333FH',
      );
    });

    test('ingesta case-insensitive', () {
      expect(
        normalizeFingerprint('gscb6gvt6dnv8c83-845'),
        'GSCB6GVT6DNV8C83-845',
      );
    });

    test('canónico (20) sin separadores y display (23) coinciden', () {
      final canonical = 'GSCB6GVT6DNV8C83-845';
      final display = 'GSCB6-GVT6D-NV8C8-3-845';
      expect(sameFingerprint(canonical, display), isTrue);
      expect(sameFingerprint(display, canonical), isTrue);
    });

    test('round-trip grupo → canónico para los tres vectores KAT', () {
      expect(
        normalizeFingerprint(groupFingerprint('GSCB6GVT6DNV8C83-845')),
        'GSCB6GVT6DNV8C83-845',
      );
      expect(
        normalizeFingerprint(groupFingerprint('3WMSUNKRR4-9WV4333FH')),
        '3WMSUNKRR4-9WV4333FH',
      );
      expect(
        normalizeFingerprint(groupFingerprint('NYAYV3MVBJP2BQCXZ4AW')),
        'NYAYV3MVBJP2BQCXZ4AW',
      );
    });

    test('firmas distintas no coinciden', () {
      expect(
        sameFingerprint('GSCB6GVT6DNV8C83-845', '3WMSUNKRR4-9WV4333FH'),
        isFalse,
      );
    });
  });

  group('Validación estricta (§4.9) — rechazo sin corrección', () {
    test('longitudes distintas de 20/23 con separadores son inválidas', () {
      for (final bad in [
        'GSCB6GVT6DNV8C83-845X', // 21
        'GSCB6GVT6DNV8C83-84', // 19
        'GSCB6-GVT6D-NV8C8-3-845-', // 24
        'GSCB6-GVT6D-NV8C8', // 18
        'GSCB6-GVT6D-NV8C8XX-3-845', // separador mal situado + longitud rara
        '',
      ]) {
        expect(isValidFingerprint(bad), isFalse, reason: bad);
        expect(tryNormalizeFingerprint(bad), isNull, reason: bad);
      }
    });

    test(
      'display sin separadores en las posiciones fijas 5/11/17 es inválido',
      () {
        // 23 chars, pero sin `-` en las posiciones fijas (5/11/17).
        const bad = 'GSCB6GVT6DNV8C83-845Xab';
        final upper = bad.toUpperCase();
        expect(upper.length, 23);
        expect(upper.codeUnitAt(5), isNot(0x2d));
        expect(upper.codeUnitAt(11), isNot(0x2d));
        expect(upper.codeUnitAt(17), isNot(0x2d));
        expect(isValidFingerprint(bad), isFalse);
      },
    );

    test('símbolos fuera del alfabeto son inválidos (rechazo, no-match)', () {
      for (final forbidden in ['0', '1', 'I', 'L', 'O', '!', '@', '=']) {
        final bad = 'GSCB6GVT6DNV8C83-84$forbidden';
        expect(bad.length, 20);
        expect(isValidFingerprint(bad), isFalse, reason: forbidden);
        expect(tryNormalizeFingerprint(bad), isNull, reason: forbidden);
      }
    });

    test('`-` literal en canónico es válido (es símbolo, no separador)', () {
      expect(isValidFingerprint('GSCB6GVT6DNV8C83-845'), isTrue);
      expect(isValidFingerprint('GSCB6GVT6DNV8C83-845'), isTrue);
      expect(normalizeFingerprint('GSCB6GVT6DNV8C83-845').length, 20);
    });

    test('normalizeFingerprint lanza error tipado ante entradas inválidas', () {
      expect(
        () => normalizeFingerprint('GSCB6GVT6DNV8C83-84'),
        throwsA(isA<InvalidFingerprintInputError>()),
      );
      expect(
        () => normalizeFingerprint('0SCB6GVT6DNV8C83-845'),
        throwsA(isA<InvalidFingerprintInputError>()),
      );
    });

    test('sameFingerprint nunca lanza y devuelve no-match ante inválidas', () {
      expect(
        sameFingerprint('GSCB6GVT6DNV8C83-84', 'GSCB6GVT6DNV8C83-84'),
        isFalse,
      );
      expect(
        sameFingerprint('GSCB6GVT6DNV8C83-84', 'GSCB6GVT6DNV8C83-845'),
        isFalse,
      );
      expect(sameFingerprint('', ''), isFalse);
      expect(sameFingerprint('GSCB6GVT6DNV8C83-845', ''), isFalse);
    });
  });

  group('groupFingerprint (display §4.6/§4.7)', () {
    test('inserta separadores tras el 5º/10º/15º carácter', () {
      expect(
        groupFingerprint('GSCB6GVT6DNV8C83-845'),
        'GSCB6-GVT6D-NV8C8-3-845',
      );
      expect(
        groupFingerprint('NYAYV3MVBJP2BQCXZ4AW'),
        'NYAYV-3MVBJ-P2BQC-XZ4AW',
      );
    });

    test('`-` literal al comienzo de grupo produce `--` en el límite', () {
      expect(
        groupFingerprint('3WMSUNKRR4-9WV4333FH'),
        '3WMSU-NKRR4--9WV4-333FH',
      );
    });

    test('longitud incorrecta lanza', () {
      expect(() => groupFingerprint('12345'), throwsArgumentError);
      expect(() => groupFingerprint('x' * 21), throwsArgumentError);
    });
  });

  group('Encode Base32 de referencia (§4.4)', () {
    test('bloque final de 1 bit se completa con ceros a la derecha', () {
      // digest de 1 byte 0xFF → 8 bits → 1 símbolo completo (11111=31 → `-`) +
      // 1 símbolo parcial (111 + 00 → 11100 = 28 → `X`), MSB-first.
      final encoded = encodeBase32Unambiguous([0xff]);
      expect(encoded, '-X');
      final withIndices = encodeBase32UnambiguousWithIndices([0xff]);
      expect(withIndices.indices, [31, 28]);
    });

    test('32 bytes (digest) → 52 símbolos', () {
      final digest = List<int>.generate(32, (i) => i);
      final encoded = encodeBase32Unambiguous(digest);
      expect(encoded.length, 52);
      expect(encodeBase32UnambiguousWithIndices(digest).indices.length, 52);
    });
  });
}
