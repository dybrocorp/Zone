/// FASE 2.1 — Base32 unambiguous del fingerprint v1.
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Alfabeto y reglas EXACTOS de `PHASE_2_FINGERPRINT_SPEC.md` §4 (normativa
/// desde la decisión CTO 2026-09-25, OPTION A):
///
/// - Alfabeto unambiguo de **32 símbolos** (sin 0/O/1/I/L):
///   `23456789ABCDEFGHJKMNPQRSTUVWXYZ-` (índice 31 = `-`, ASCII U+002D).
/// - 5 bits por símbolo, **MSB-first** (bit-packing RFC 4648, alfabeto propio).
/// - **Sin padding**; el fingerprint usa los **primeros 20 caracteres** de la
///   codificación completa del digest SHA-256 (52 chars).
/// - Normalización §4.8: MAYÚSCULAS + desagrupación posicional estricta (solo
///   los separadores fijos en las posiciones 5/11/17 del display de 23 chars se
///   eliminan; los `-` literales de un texto canónico se conservan). Longitudes
///   ≠ 20/23, separadores mal situados o símbolos fuera del alfabeto ⇒
///   **inválido** (rechazo, §4.9).
///
/// KAT oficial (spec §6): **VERIFICADO 2026-09-25** por tres implementaciones
/// independientes (Python stdlib, Node.js `node:crypto`, PowerShell/.NET) más
/// traza grupo a grupo del bit-packing — ver
/// `PHASE_2.1_KAT_VERIFICATION_REPORT.md`.
library;

import 'identity_errors.dart';

/// Alfabeto unambiguo canónico del spec §4 (32 símbolos, orden literal).
/// Índice 0..31; `-` (U+002D) es el símbolo del índice 31.
const String kBase32UnambiguousAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ-';

/// Longitud del fingerprint por defecto (100 bits de entropía).
const int kFingerprintTextLength = 20;

/// Longitud del display agrupado: 4×5 + 3 separadores (23 caracteres).
const int kFingerprintDisplayLength = 23;

/// Posiciones fijas (0-based) de los separadores `-` en el display de 23 chars
/// (spec §4.7). Solo estos `-` se eliminan al desagrupar; cualquier otro `-` es
/// un símbolo literal (índice 31) y se conserva.
const List<int> kFingerprintDisplaySeparatorPositions = [5, 11, 17];

/// Símbolo del alfabeto para un valor de 5 bits (0..31). Fail-closed.
String symbolForIndex(int index) {
  if (index < 0 || index >= kBase32UnambiguousAlphabet.length) {
    throw ArgumentError.value(index, 'index', 'must be in 0..31');
  }
  return kBase32UnambiguousAlphabet[index];
}

/// Valor (0..31) de un símbolo del alfabeto. Fail-closed ante símbolos ajenos.
int indexForSymbol(String symbol) {
  if (symbol.length != 1) {
    throw InvalidFingerprintInputError('symbol must be a single character');
  }
  final index = kBase32UnambiguousAlphabet.indexOf(symbol);
  if (index < 0) {
    throw InvalidFingerprintInputError(
      'symbol `$symbol` is not in the fingerprint alphabet',
    );
  }
  return index;
}

/// Codifica bytes a Base32 unambiguous, SIN padding (RFC 4648 bit-packing,
/// alfabeto del spec). El resultado conserva todos los bits de entrada.
String encodeBase32Unambiguous(List<int> bytes) =>
    encodeBase32UnambiguousWithIndices(bytes).text;

/// Idem [encodeBase32Unambiguous] pero devuelve además el valor (0..31) de cada
/// símbolo — evidencia del bit-packing de 5 bits/MSB-first (KAT §4.4) y del
/// mapeo al alfabeto propio (§4.3).
({String text, List<int> indices}) encodeBase32UnambiguousWithIndices(
  List<int> bytes,
) {
  final buffer = StringBuffer();
  final indices = <int>[];
  var carry = 0;
  var bits = 0;
  for (final byte in bytes) {
    carry = (carry << 8) | (byte & 0xff);
    bits += 8;
    while (bits >= 5) {
      final value = (carry >> (bits - 5)) & 0x1f;
      buffer.write(symbolForIndex(value));
      indices.add(value);
      bits -= 5;
    }
  }
  if (bits > 0) {
    // Bloque final incompleto de 5 bits: bit restante completado con ceros a la
    // derecha (spec §4.4.5). La codificación completa de 256 bits = 52 símbolos.
    final value = (carry << (5 - bits)) & 0x1f;
    buffer.write(symbolForIndex(value));
    indices.add(value);
  }
  return (text: buffer.toString(), indices: List.unmodifiable(indices));
}

/// Primeros [kFingerprintTextLength] caracteres de la codificación completa
/// (sin padding), tal como exige el spec §4 para el texto del fingerprint.
String fingerprintTextFromDigest(List<int> digestBytes) {
  final full = encodeBase32Unambiguous(digestBytes);
  return full.substring(0, kFingerprintTextLength);
}

/// Presentación visual: `XXXXX-XXXXX-XXXXX-XXXXX` (4 grupos × 5, separador en
/// posiciones fijas tras el 5º/10º/15º carácter — spec §4.6/§4.7). Un `-`
/// literal de un grupo produce `--` en el límite (se conserva al desagrupar).
String groupFingerprint(String text) {
  if (text.length != kFingerprintTextLength) {
    throw ArgumentError.value(
      text.length,
      'text length',
      'Expected $kFingerprintTextLength characters',
    );
  }
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && i % 5 == 0) {
      buffer.write('-');
    }
    buffer.write(text[i]);
  }
  return buffer.toString();
}

/// Normaliza una presentación (canónica o display) a la forma canónica de 20
/// chars (spec §4.8): MAYÚSCULAS + desagrupación posicional estricta.
///
/// Fail-closed (spec §4.9): longitud ≠ 20/23, separadores mal situados o
/// símbolos fuera del alfabeto ⇒ [InvalidFingerprintInputError]; no corrige
/// entradas corruptas.
String normalizeFingerprint(String fingerprint) {
  final normalized = tryNormalizeFingerprint(fingerprint);
  if (normalized == null) {
    throw InvalidFingerprintInputError(
      'fingerprint text is not a valid canonical (20) or display (23) form; '
      'no silent correction is applied',
    );
  }
  return normalized;
}

/// Igual que [normalizeFingerprint] pero devuelve null ante cualquier entrada
/// inválida (sin excepción). Base de las comparaciones tolerantes (§4.9
/// no-match).
String? tryNormalizeFingerprint(String fingerprint) {
  // 1. Invarianza de caja (ingesta case-insensitive).
  final upper = fingerprint.toUpperCase();
  final length = upper.length;
  String ungrouped;
  if (length == kFingerprintDisplayLength) {
    // 2. Display: separadores fijos en las posiciones 5/11/17 (0-based).
    for (final pos in kFingerprintDisplaySeparatorPositions) {
      if (upper.codeUnitAt(pos) != 0x2d) return null;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      if (kFingerprintDisplaySeparatorPositions.contains(i)) continue;
      buffer.write(upper[i]);
    }
    ungrouped = buffer.toString();
  } else if (length == kFingerprintTextLength) {
    // 3. Canónico: continuar (los `-` son símbolos literales).
    ungrouped = upper;
  } else {
    // Longitud distinta de 20/23 ⇒ invalidar (rechazar, no corregir).
    return null;
  }
  // 4. Todo carácter ∈ alfabeto §4.2.
  if (containsNonAlphabetSymbol(ungrouped)) return null;
  return ungrouped;
}

/// True si [fingerprint] es una forma canónica (20) o display (23) válida
/// según las reglas §4.8/§4.9.
bool isValidFingerprint(String fingerprint) =>
    tryNormalizeFingerprint(fingerprint) != null;

/// Comparación normalizada (spec §4.8 §5: igualdad byte a byte de las formas
/// canónicas). Cualquier entrada inválida ⇒ no match (spec §4.9); nunca lanza.
bool sameFingerprint(String a, String b) {
  final na = tryNormalizeFingerprint(a);
  final nb = tryNormalizeFingerprint(b);
  return na != null && nb != null && na == nb;
}

/// Alguno de los símbolos de [text] no pertenece al alfabeto unambiguo.
bool containsNonAlphabetSymbol(String text) {
  for (var i = 0; i < text.length; i++) {
    if (!kBase32UnambiguousAlphabet.contains(text[i])) {
      return true;
    }
  }
  return false;
}
