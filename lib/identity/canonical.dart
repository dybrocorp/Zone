/// FASE 2.1 — Serialización canónica (mandato §11).
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Único mecanismo de serialización canónica de esta fundación para material
/// de identidad/fingerprints. Reglas (autoridad: `PHASE_2_FINGERPRINT_SPEC.md`
/// §3 + precisiones canónicas OPEN-015):
///
/// - Nada de `Map.toString()`, strings de depuración ni JSON de estructuras
///   desordenadas para material canónico.
/// - UTF-8 estricto, sin BOM, sin normalización Unicode (todo ASCII).
/// - UUIDs: lowercase con guiones (RFC 4122 text).
/// - Clave pública Ed25519: 32 bytes raw → **Standard Base64 con padding**
///   (44 chars).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'identity_errors.dart';

/// Codec canónico para inputs de identidad y fingerprint.
class CanonicalCodec {
  const CanonicalCodec._();

  /// Expresión de forma de UUID canónico (RFC 4122 hex groups).
  static final RegExp _uuidShape = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Canonicaliza un UUID: lowercase con guiones, ASCII. Rechaza formas que
  /// no sean RFC 4122 (fail-closed, sin silenciar inputs corruptos).
  static String uuidCanonical(String input) {
    final trimmed = input.trim();
    if (!_uuidShape.hasMatch(trimmed)) {
      throw InvalidIdentityMetadataError('malformed UUID: not RFC 4122 shape');
    }
    return trimmed.toLowerCase();
  }

  /// Base64 estándar CON padding (44 chars para 32 bytes) — fijado por la
  /// especificación canónica (OPEN-015). Depende de la implementación estándar
  /// de Dart que incluye padding con '='.
  static String base64StdPadded(List<int> bytes) => base64Encode(bytes);

  /// Codifica explícitamente a UTF-8 (sin BOM).
  static Uint8List utf8Bytes(String text) =>
      Uint8List.fromList(utf8.encode(text));

  /// Concatena segmentos binarios en un único buffer (para digest canónico).
  static Uint8List concat(List<List<int>> parts) {
    final builder = BytesBuilder(copy: false);
    for (final part in parts) {
      builder.add(part);
    }
    return builder.toBytes();
  }
}
