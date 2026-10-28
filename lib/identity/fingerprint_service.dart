/// FASE 2.1 — Fingerprints v1 (ACCOUNT + DEVICE).
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Autoridad ÚNICA: `PHASE_2_FINGERPRINT_SPEC.md` (spec §1-§4). Este servicio
/// implementa EXACTAMENTE el input canónico, el digest y el texto:
///
/// ```
/// fp_input(kind, account_id, actor_id, pk_ed25519):
///   utf8("ZONE-FP-1\0")                 # el byte NUL es PARTE del input
///   ∥ utf8(kind)                        # "ACC" o "DEV"
///   ∥ utf8(uuid_canonical(account_id))
///   ∥ [si DEV:] utf8(uuid_canonical(device_id))
///   ∥ base64_std_padded(pk_ed25519)     # 32 bytes raw → 44 chars con padding
/// digest  = SHA-256(fp_input)
/// fp_text = primeros 20 chars de base32_unambiguous(digest)
/// ```
///
/// La X25519 NUNCA entra en el input (spec §1.3, D2): solo aceptan claves
/// públicas Ed25519 (32 bytes raw). El fingerprint no es secreto ni credencial
/// (I-026); las evidencias intermedias expuestas en [FingerprintComputation]
/// son datos públicos derivados de claves públicas e identificadores.
library;

import 'package:cryptography/cryptography.dart';

import 'base32_unambiguous.dart';
import 'canonical.dart';
import 'identity_errors.dart';
import 'keys.dart';

/// Resultado completo de un cálculo de fingerprint: evidencia intermedia del
/// KAT (input canónico, digest, bit-packing, mapeo, truncado) además del texto
/// y su display. No contiene material secreto.
class FingerprintComputation {
  const FingerprintComputation({
    required this.kind,
    required this.canonicalInputHex,
    required this.sha256Hex,
    required this.fullBase32,
    required this.symbolIndices,
    required this.text,
    required this.display,
  });

  /// `"ACC"` o `"DEV"`.
  final String kind;

  /// Hex del input canónico exacto (§3) — bytes que entran a SHA-256.
  final String canonicalInputHex;

  /// Digest SHA-256 (hex, minúsculas).
  final String sha256Hex;

  /// Codificación Base32 completa del digest: 52 símbolos sin padding (§4.4).
  final String fullBase32;

  /// Valor (0..31) de cada uno de los 52 símbolos de [fullBase32] — evidencia
  /// del bit-packing de 5 bits MSB-first y del mapeo al alfabeto (§4.3/§4.4).
  final List<int> symbolIndices;

  /// Fingerprint canónico: primeros 20 símbolos (§4.5/§4.6).
  final String text;

  /// Display 4×5 (§4.6/§4.7).
  final String display;

  /// Resumen público para evidencia documental (sin secretos).
  Map<String, Object?> toEvidence() => {
    'kind': kind,
    'input_hex': canonicalInputHex,
    'sha256_hex': sha256Hex,
    'base32_full_52': fullBase32,
    'symbol_indices': List<int>.unmodifiable(symbolIndices),
    'fingerprint_20': text,
    'display_4x5': display,
  };
}

/// Servicio de fingerprints v1.
class FingerprintService {
  const FingerprintService._();

  static const String _kindAccount = 'ACC';
  static const String _kindDevice = 'DEV';

  static final Sha256 _sha256 = Sha256();

  static void _checkPublicKey(List<int> publicKeyBytes) {
    if (publicKeyBytes.length != kIdentityPublicKeyLength) {
      throw InvalidFingerprintInputError(
        'public key must be $kIdentityPublicKeyLength raw bytes (Ed25519); '
        'found ${publicKeyBytes.length}',
      );
    }
  }

  /// ACCOUNT_FINGERPRINT: identifica a la cuenta (identity Ed25519).
  ///
  /// Input canónico: `"ZONE-FP-1\0" ‖ "ACC" ‖ account_id ‖ identity_public_key`.
  /// Cambia solo si rota la Ed25519 de cuenta (OPEN-013).
  static Future<FingerprintComputation> accountFingerprint({
    required String accountId,
    required List<int> identityPublicKeyBytes,
  }) {
    return _compute(
      kind: _kindAccount,
      accountId: accountId,
      deviceId: null,
      publicKeyBytes: identityPublicKeyBytes,
    );
  }

  /// DEVICE_FINGERPRINT: identifica a un dispositivo concreto (device Ed25519).
  ///
  /// Input canónico:
  /// `"ZONE-FP-1\0" ‖ "DEV" ‖ account_id ‖ device_id ‖ device_public_key`.
  /// Cambia si cambia el device o su Ed25519 (reinstalación con device nuevo).
  static Future<FingerprintComputation> deviceFingerprint({
    required String accountId,
    required String deviceId,
    required List<int> devicePublicKeyBytes,
  }) {
    return _compute(
      kind: _kindDevice,
      accountId: accountId,
      deviceId: deviceId,
      publicKeyBytes: devicePublicKeyBytes,
    );
  }

  /// Texto canónico (20 chars) del ACCOUNT_FINGERPRINT.
  static Future<String> accountFingerprintText({
    required String accountId,
    required List<int> identityPublicKeyBytes,
  }) async {
    final computation = await accountFingerprint(
      accountId: accountId,
      identityPublicKeyBytes: identityPublicKeyBytes,
    );
    return computation.text;
  }

  /// Texto canónico (20 chars) del DEVICE_FINGERPRINT.
  static Future<String> deviceFingerprintText({
    required String accountId,
    required String deviceId,
    required List<int> devicePublicKeyBytes,
  }) async {
    final computation = await deviceFingerprint(
      accountId: accountId,
      deviceId: deviceId,
      devicePublicKeyBytes: devicePublicKeyBytes,
    );
    return computation.text;
  }

  /// Display 4×5 del ACCOUNT_FINGERPRINT (spec §2/§4.6).
  static Future<String> groupAccountFingerprint({
    required String accountId,
    required List<int> identityPublicKeyBytes,
  }) async {
    final computation = await accountFingerprint(
      accountId: accountId,
      identityPublicKeyBytes: identityPublicKeyBytes,
    );
    return computation.display;
  }

  /// Display 4×5 del DEVICE_FINGERPRINT (spec §2/§4.6).
  static Future<String> groupDeviceFingerprint({
    required String accountId,
    required String deviceId,
    required List<int> devicePublicKeyBytes,
  }) async {
    final computation = await deviceFingerprint(
      accountId: accountId,
      deviceId: deviceId,
      devicePublicKeyBytes: devicePublicKeyBytes,
    );
    return computation.display;
  }

  /// Comparación normalizada (spec §4.8): formas canónicas byte a byte; entrada
  /// inválida ⇒ no-match, nunca lanza.
  ///
  /// Implementación local sobre [tryNormalizeFingerprint] (la función
  /// top-level `sameFingerprint` del módulo Base32 no puede importarse con el
  /// mismo nombre que este método estático).
  static bool sameFingerprint(String a, String b) {
    final na = tryNormalizeFingerprint(a);
    final nb = tryNormalizeFingerprint(b);
    return na != null && nb != null && na == nb;
  }

  static Future<FingerprintComputation> _compute({
    required String kind,
    required String accountId,
    required String? deviceId,
    required List<int> publicKeyBytes,
  }) async {
    _checkPublicKey(publicKeyBytes);
    final uuidAccount = CanonicalCodec.uuidCanonical(accountId);
    String? uuidDevice;
    if (deviceId != null) {
      uuidDevice = CanonicalCodec.uuidCanonical(deviceId);
    }

    final input = CanonicalCodec.concat([
      CanonicalCodec.utf8Bytes('ZONE-FP-1\u0000'),
      CanonicalCodec.utf8Bytes(kind),
      CanonicalCodec.utf8Bytes(uuidAccount),
      if (uuidDevice != null) CanonicalCodec.utf8Bytes(uuidDevice),
      CanonicalCodec.utf8Bytes(CanonicalCodec.base64StdPadded(publicKeyBytes)),
    ]);

    final hash = await _sha256.hash(input);
    final encoded = encodeBase32UnambiguousWithIndices(hash.bytes);
    final text = fingerprintTextFromDigest(hash.bytes);
    return FingerprintComputation(
      kind: kind,
      canonicalInputHex: _toHex(input),
      sha256Hex: _toHex(hash.bytes),
      fullBase32: encoded.text,
      symbolIndices: encoded.indices,
      text: text,
      display: groupFingerprint(text),
    );
  }

  static String _toHex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toLowerCase();
}
