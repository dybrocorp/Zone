/// PHASE G — `device_certificate_v2` (fundación de migración de dispositivo).
///
/// Estado: DISEÑADO + IMPLEMENTADO + PROBADO LOCALMENTE (unidades KAT-ed25519).
/// NO integrado en el backend (Z-212 §0 unmet: staging/exec NO autorizado).
///
/// Qué es: certificado de dispositivo firmado por la **identidad Ed25519 de
/// cuenta** (ancla auto-emitida PENDIENTE de verificación OOB del
/// fingerprint — explícito, NO TOFU silencioso).
///
/// Envelope:
///
/// ```text
/// ZDC2: + base64(JSON {"p": <payloadJson>, "s": <signatureB64>})
/// payloadJson (orden canónico FIJO, sin espacios):
/// {"v":2,"account_id":uuid,"device_id":uuid,"fp":sha256hex64,
///  "x25519":b64Padded,"acct_ed25519":b64Padded,"iat":iso8601Z,"exp":iso8601Z}
/// ```
///
/// Verificación (fail-closed):
/// 1. Forma/base64/JSON larga estricta y orden canónico exacto.
/// 2. `exp` > `iat` y `exp` NO expirado (reloj local; tolerancia 0).
/// 3. Firma Ed25519 sobre los bytes canónicos del payload con la clave
///    `acct_ed25519` contenida (KAT-validada en test/e2ee).
/// 4. `fp` == sha256Hex del DEVICE_FINGERPRINT canónico de (account_id,
///    device_id, x25519) vía [FingerprintService] — el certificado queda
///    atado MATERIALMENTE a las claves.
///
/// El device_id de esta fase es un UUID v4 estable persistido por el puente
/// (`device_identity_bridge.dart`) — IDs estables entre intentos.
///
/// Postura de limitación (no afirmar de más): este certificado NO prueba la
/// posesión del dispositivo ante el backend (eso exige el flujo OOB de
/// `z213_account_device_identity.sql` + funciones SECURITY DEFINER); SU papel
/// aquí es la integridad del material y el anclaje de firma de cuenta.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/e2ee_message_crypto.dart' show canonicalJsonString;
import 'canonical.dart';
import 'ed25519_identity_service.dart';
import 'fingerprint_service.dart';

/// Prefijo de envelope del certificado (ASCII-safe).
const String kDeviceCertV2Prefix = 'ZDC2:';

/// Duración de validez por defecto del certificado.
const Duration kDeviceCertV2DefaultValidity = Duration(days: 365);

/// Error tipado de certificado (fail-closed, sin material sensible).
class DeviceCertificateV2Error implements Exception {
  const DeviceCertificateV2Error(this.reason, this.detail);

  final String reason;
  final String detail;

  @override
  String toString() => 'DeviceCertificateV2Error(reason=$reason, $detail)';
}

/// Datos firmados del certificado.
class DeviceCertificateV2Payload {
  const DeviceCertificateV2Payload({
    required this.accountId,
    required this.deviceId,
    required this.fingerprintSha256Hex,
    required this.x25519PublicKeyBase64,
    required this.accountIdentityEd25519Base64,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String accountId;
  final String deviceId;
  /// sha256 hex (64) del DEVICE_FINGERPRINT canónico (la norma de z213).
  final String fingerprintSha256Hex;
  final String x25519PublicKeyBase64;
  /// Clave pública Ed25519 DE CUENTA (verificadora de la firma).
  final String accountIdentityEd25519Base64;
  final DateTime issuedAt;
  final DateTime expiresAt;

  /// JSON canónico (orden de claves FIJO y documentado).
  String canonicalJson() {
    return '{'
        '"v":2,'
        '"account_id":${canonicalJsonString(accountId)},'
        '"device_id":${canonicalJsonString(deviceId)},'
        '"fp":${canonicalJsonString(fingerprintSha256Hex)},'
        '"x25519":${canonicalJsonString(x25519PublicKeyBase64)},'
        '"acct_ed25519":${canonicalJsonString(accountIdentityEd25519Base64)},'
        '"iat":${canonicalJsonString(issuedAt.toUtc().toIso8601String())},'
        '"exp":${canonicalJsonString(expiresAt.toUtc().toIso8601String())}'
        '}';
  }
}

/// Certificado v2: emisión y verificación, sin estado global.
class DeviceCertificateV2 {
  DeviceCertificateV2._();

  /// Emite el certificado firmando el payload canónico con la identidad de
  /// cuenta. Recalcula el fingerprint y lo valida contra el dado (fail-closed)
  /// para que el ancla no pueda divergir del material.
  static Future<String> issue({
    required SimpleKeyPair accountIdentityKeyPair,
    required String accountId,
    required String deviceId,
    required List<int> deviceX25519PublicKeyBytes,
    required String fingerprintSha256Hex,
    required DateTime issuedAt,
    required DateTime expiresAt,
  }) {
    return _issue(
      accountIdentityKeyPair: accountIdentityKeyPair,
      accountId: accountId,
      deviceId: deviceId,
      deviceX25519PublicKeyBytes: deviceX25519PublicKeyBytes,
      fingerprintSha256Hex: fingerprintSha256Hex,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }

  static Future<String> _issue({
    required SimpleKeyPair accountIdentityKeyPair,
    required String accountId,
    required String deviceId,
    required List<int> deviceX25519PublicKeyBytes,
    required String fingerprintSha256Hex,
    required DateTime issuedAt,
    required DateTime expiresAt,
  }) async {
    // Fingerprint DEBE ser la sha256Hex canónica (64 hex). Se recomputa y
    // se compara (defensa profunda; el emisor nunca "declara" sin validar).
    final recomputed = await FingerprintService.deviceFingerprint(
      accountId: accountId,
      deviceId: deviceId,
      devicePublicKeyBytes: deviceX25519PublicKeyBytes,
    );
    if (fingerprintSha256Hex.toLowerCase() != recomputed.sha256Hex) {
      throw DeviceCertificateV2Error(
        'fingerprint',
        'declared fingerprint does not bind to material',
      );
    }
    if (!expiresAt.isAfter(issuedAt)) {
      throw const DeviceCertificateV2Error('validity', 'exp must be > iat');
    }

    final payload = DeviceCertificateV2Payload(
      accountId: accountId.trim().toLowerCase(),
      deviceId: deviceId.trim().toLowerCase(),
      fingerprintSha256Hex: fingerprintSha256Hex.toLowerCase(),
      x25519PublicKeyBase64:
          CanonicalCodec.base64StdPadded(deviceX25519PublicKeyBytes),
      accountIdentityEd25519Base64: await Ed25519IdentityService.publicKeyBase64(
        accountIdentityKeyPair,
      ),
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );

    final message = CanonicalCodec.utf8Bytes(payload.canonicalJson());
    final signature = await Ed25519IdentityService.sign(
      accountIdentityKeyPair,
      message,
    );

    final envelopeJson = <String, dynamic>{
      'p': payload.canonicalJson(),
      's': CanonicalCodec.base64StdPadded(signature),
    };
    return '$kDeviceCertV2Prefix${base64Encode(utf8.encode(jsonEncode(envelopeJson)))}';
  }

  /// `true` si el texto empieza con el prefijo (clasificación explícita).
  static bool isV2Certificate(String? text) =>
      (text ?? '').trimLeft().startsWith(kDeviceCertV2Prefix);

  /// Verifica el envelope completo (forma → ventanas → firma → binding fp).
  /// Devuelve el payload validado o lanza [DeviceCertificateV2Error].
  static Future<DeviceCertificateV2Payload> verify(String certificate) async {
    final trimmed = certificate.trim();
    if (!trimmed.startsWith(kDeviceCertV2Prefix)) {
      throw const DeviceCertificateV2Error('prefix', 'not a ZDC2 certificate');
    }
    final payloadB64 = trimmed.substring(kDeviceCertV2Prefix.length);
    if (payloadB64.trim().isEmpty) {
      throw const DeviceCertificateV2Error('empty', 'certificate empty');
    }
    Uint8List envelopeBytes;
    try {
      envelopeBytes = base64Decode(payloadB64.trim());
    } on FormatException {
      throw const DeviceCertificateV2Error('base64', 'envelope not base64');
    }
    final text = utf8.decode(envelopeBytes, allowMalformed: false);
    Object? parsed;
    try {
      parsed = jsonDecode(text);
    } on FormatException {
      throw const DeviceCertificateV2Error('json', 'envelope not json');
    }
    if (parsed is! Map) {
      throw const DeviceCertificateV2Error('shape', 'envelope not object');
    }
    final p = parsed['p'];
    final s = parsed['s'];
    if (p is! String || s is! String) {
      throw const DeviceCertificateV2Error('shape', 'p/s missing');
    }
    final Object? payloadJson;
    try {
      payloadJson = jsonDecode(p);
    } on FormatException {
      throw const DeviceCertificateV2Error('json', 'payload not json');
    }
    if (payloadJson is! Map) {
      throw const DeviceCertificateV2Error('shape', 'payload not object');
    }

    // Forma canónica: el payload DEBE reproducir EXACTAMENTE el JSON canónico
    // (orden de campos fijo, sin espacios) — evita firmas sobre inputs mutados.
    final payload = _payloadFromShape(payloadJson);
    final canonicalBytes = CanonicalCodec.utf8Bytes(payload.canonicalJson());
    if (!_bytesEqual(canonicalBytes, utf8.encode(p))) {
      throw const DeviceCertificateV2Error(
        'canonical',
        'payload is not in canonical form',
      );
    }

    // Ventana de validez (reloj local; sin tolerancia en esta fase).
    final now = DateTime.now().toUtc();
    if (payload.expiresAt.isBefore(now)) {
      throw const DeviceCertificateV2Error('expired', 'certificate expired');
    }

    // Firma con la clave de CUENTA contenida en el payload.
    final acctKeyBytes = base64Decode(
      payload.accountIdentityEd25519Base64.trim(),
    );
    final signatureBytes = base64Decode(s.trim());
    final signatureOk = await Ed25519IdentityService.verify(
      publicKeyBytes: acctKeyBytes,
      message: canonicalBytes,
      signatureBytes: signatureBytes,
    );
    if (!signatureOk) {
      throw const DeviceCertificateV2Error('signature', 'invalid signature');
    }

    // Binding material del fingerprint (recomputo local).
    final recomputed = await FingerprintService.deviceFingerprint(
      accountId: payload.accountId,
      deviceId: payload.deviceId,
      devicePublicKeyBytes: base64Decode(
        payload.x25519PublicKeyBase64.trim(),
      ),
    );
    if (payload.fingerprintSha256Hex != recomputed.sha256Hex) {
      throw const DeviceCertificateV2Error(
        'fingerprint',
        'fp does not bind to keys',
      );
    }
    return payload;
  }

  /// Reconstruye el payload validando TIPOS; sin reparseo silencioso.
  static DeviceCertificateV2Payload _payloadFromShape(Map payloadJson) {
    Map<String, String> requireStrings(Set<String> keys) {
      final out = <String, String>{};
      for (final k in keys) {
        final v = payloadJson[k];
        if (v is! String || v.trim().isEmpty) {
          throw DeviceCertificateV2Error('shape', 'field $k ausente o vacío');
        }
        out[k] = v;
      }
      return out;
    }

    final strings = requireStrings({
      'account_id',
      'device_id',
      'fp',
      'x25519',
      'acct_ed25519',
      'iat',
      'exp',
    });
    if (payloadJson['v'] != 2) {
      throw const DeviceCertificateV2Error('version', 'unsupported version');
    }
    return DeviceCertificateV2Payload(
      accountId: CanonicalCodec.uuidCanonical(strings['account_id']!),
      deviceId: CanonicalCodec.uuidCanonical(strings['device_id']!),
      fingerprintSha256Hex: strings['fp']!,
      x25519PublicKeyBase64: strings['x25519']!,
      accountIdentityEd25519Base64: strings['acct_ed25519']!,
      issuedAt: DateTime.parse(strings['iat']!).toUtc(),
      expiresAt: DateTime.parse(strings['exp']!).toUtc(),
    );
  }
}

/// Comparación CONTENT-equality de bytes (`List<int>` en Dart no compara por
/// contenido con `!=`; usar siempre este helper para material canónico).
bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
