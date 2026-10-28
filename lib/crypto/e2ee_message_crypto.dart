/// PHASE G §6.6 paso 2 — Motor de mensajes E2EE v2 (`ZONE-E2EE-V2`).
///
/// Alcance EXACTO de esta fase (decisión 2026-10-27, ver
/// `docs/audit/PHASE_J_DECISION_REVIEW.md`, paquete DEC-G1..DEC-G4):
///
/// - Sobre el secreto X25519 estático-estático existente (el MISMO que v1
///   usa hoy), se aplica HKDF-SHA256 con separación de dominios:
///
/// ```text
/// salt   = SHA-256( "ZONE-E2EE-SALT-2" ‖ 0x00 ‖ pkLow ‖ pkHigh )
///          (pkLow/pkHigh = claves públicas ordenadas lexicográficamente
///           por BYTES, para que ambos lados calculen el mismo salt)
/// A      = parte con id lexicográficamente MENOR (sender vs receiver)
/// keyA2B = HKDF-SHA256(ikm=sharedSecret, salt, info="ZONE-E2EE-V2 key"‖"A2B")
/// keyB2A = HKDF-SHA256(ikm=sharedSecret, salt, info="ZONE-E2EE-V2 key"‖"B2A")
/// ```
///
/// - ChaCha20-Poly1305 con nonce aleatorio de 12 bytes y AAD:
///
/// ```text
/// aad = utf8 (orden de claves fijo, sin espacios):
///   {"v":2,"s":<senderId>,"r":<receiverId>,"m":<messageId>,"i":<matchId>}
/// ```
///
/// - Self-describing envelope: `zt2:` + base64(JSON):
/// ```text
/// {"v":2,"s":senderId,"m":messageId,"i":matchId,"n":nonceB64,
///  "t":ciphertextB64,"h":tagB64,"ap":2}
/// ```
///   `ap` = "AAD profile" (2 = la forma canónica descrita arriba). El
///   envelope es ASCII-safe para Postgres/relay y auto-versionado.
///
/// Sin primitivas caseras: solo HKDF/HMAC-SHA256, SHA-256 y AEAD de
/// `package:cryptography` (Apache-2.0, ya usada por v1 y por la fundación
/// de identidad).
///
/// Lo que NO garantiza este paso (no afirmar de más, ver PHASE G anexo):
/// - Sin forward secrecy: la raíz sigue siendo estático-estático (FS/PCS =
///   ratchet v3/v4, BLOQUEADO: DEC-G1 + revisión externa).
/// - Interoperabilidad de envío unidireccional: builds antiguos NO descifran
///   mensajes nuevos `zt2:`; los mensajes v1 almacenados siguen leyéndose
///   (fallback de lectura preservado — `isV2Envelope` decide la ruta).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Versión del protocolo capa mensaje.
const int kE2eeV2Version = 2;

/// Prefijo del envelope auto-descriptivo.
const String kZt2EnvelopePrefix = 'zt2:';

/// Serializa una cadena como el ÚNICO string JSON canónico permitido en
/// material de ZONE (AAD v2, certificados v2): comillas sensatas, escapes
/// mínimos RFC 8259, símbolos < 0x20 como \u00XX, sin espacios añadidos.
///
/// Función pública compartida: el motor v2 (`E2eeMessageCryptoV2._jsonString`)
/// y otros módulos de fundación (p. ej. `device_certificate_v2.dart`) deben
/// usar ESTA única verdad — dos formateadores de JSON canónico distintos
/// romperían la reproducibilidad de bytes entre emisor y verificador.
String canonicalJsonString(String value) {
  final out = StringBuffer()..write('"');
  for (final rune in value.runes) {
    final ch = String.fromCharCode(rune);
    switch (ch) {
      case '"':
        out.write('\\"');
      case '\\':
        out.write('\\\\');
      case '\b':
        out.write('\\b');
      case '\f':
        out.write('\\f');
      case '\n':
        out.write('\\n');
      case '\r':
        out.write('\\r');
      case '\t':
        out.write('\\t');
      default:
        if (rune < 0x20) {
          out.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.write(ch);
        }
    }
  }
  out.write('"');
  return out.toString();
}

/// Dominio del salt v2 (con byte NUL de separación).
const String kV2SaltDomain = 'ZONE-E2EE-SALT-2';

/// Prefijo de `info` de la clave v2 (separación de dominio explícita).
const String kV2KeyInfo = 'ZONE-E2EE-V2 key';

/// "AAD profile" del envelope (2 = forma canónica descrita arriba).
const int kV2AadProfile = 2;

/// Longitud del nonce ChaCha20 (12 bytes, RFC 8439).
const int kV2NonceLength = 12;

/// Error tipado de parseo/sintaxis del envelope v2 (fail-closed).
class E2eeV2ParseError implements Exception {
  const E2eeV2ParseError(this.reason, {this.detail});

  final String reason;
  final String? detail;

  @override
  String toString() =>
      'E2eeV2ParseError(reason=$reason'
      '${detail == null ? '' : ', detail=$detail'})';
}

/// Error de autenticación AEAD: clave/AAD erróneos, datos alterados o
/// contexto invertido. Nunca expone material secreto.
class E2eeV2AuthenticationError implements Exception {
  const E2eeV2AuthenticationError(this.detail);

  final String? detail;

  @override
  String toString() => 'E2eeV2AuthenticationError${detail == null ? '' : '($detail)'}';
}

/// Contexto criptográfico del mensaje (identidades + claves públicas).
///
/// `senderId`/`receiverId` pueden ser UUID de cuenta o handle ZONE-; lo que
/// importa es que AMBOS lados usen los mismos valores canónicos.
class E2eeV2MessageContext {
  const E2eeV2MessageContext({
    required this.senderId,
    required this.receiverId,
    required this.messageId,
    required this.matchId,
    required this.senderPublicKeyBytes,
    required this.receiverPublicKeyBytes,
  });

  final String senderId;
  final String receiverId;
  final String messageId;
  final String matchId;

  /// Clave pública X25519 del emisor (32 bytes crudos).
  final List<int> senderPublicKeyBytes;

  /// Clave pública X25519 del receptor (32 bytes crudos).
  final List<int> receiverPublicKeyBytes;
}

/// Envelope v2 decodificado (metadatos sin secreto).
class E2eeV2Envelope {
  const E2eeV2Envelope({
    required this.senderId,
    required this.messageId,
    required this.matchId,
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final String senderId;
  final String messageId;
  final String matchId;
  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List mac;
}

/// Motor puro del esquema v2. Sin estado global: todos los parámetros se
/// pasan por argumento (el shared secret vive en `ChatE2EEService`, igual
/// que v1).
class E2eeMessageCryptoV2 {
  E2eeMessageCryptoV2._();

  static final Chacha20 _aead = Chacha20.poly1305Aead();

  // ── Clasificación ─────────────────────────────────────────────────────

  /// `true` si `encryptedContent` es un envelope v2 (`zt2:`).
  static bool isV2Envelope(String? encryptedContent) {
    return (encryptedContent ?? '').trimLeft().startsWith(kZt2EnvelopePrefix);
  }

  // ── Derivación de clave ───────────────────────────────────────────────

  /// Sufijo canónico de dirección: lexicográfico por id (menor es "A").
  static String directionSuffix(String senderId, String receiverId) {
    return senderId.compareTo(receiverId) < 0 ? 'A2B' : 'B2A';
  }

  /// Salt neutral entre partes: SHA-256(dominio ‖ 0x00 ‖ pkLow ‖ pkHigh).
  static Future<Uint8List> saltFor({
    required List<int> senderPublicKeyBytes,
    required List<int> receiverPublicKeyBytes,
  }) {
    _validateKeyBytes(senderPublicKeyBytes, 'sender public key');
    _validateKeyBytes(receiverPublicKeyBytes, 'receiver public key');
    final (low, high) = _orderedByBytes(
      senderPublicKeyBytes,
      receiverPublicKeyBytes,
    );
    if (_constantEquals(low, high)) {
      throw const E2eeV2ParseError(
        'keys',
        detail: 'sender and receiver public keys are identical',
      );
    }
    final builder = BytesBuilder()
      ..add(utf8.encode(kV2SaltDomain))
      ..addByte(0x00)
      ..add(low)
      ..add(high);
    return Sha256()
        .hash(builder.takeBytes())
        .then((d) => Uint8List.fromList(d.bytes));
  }

  /// Clave de sesión de la dirección (sender → receiver).
  static Future<SecretKey> deriveDirectionKey({
    required SecretKey sharedSecret,
    required String senderId,
    required String receiverId,
    required List<int> senderPublicKeyBytes,
    required List<int> receiverPublicKeyBytes,
  }) async {
    if (senderId.isEmpty || receiverId.isEmpty) {
      throw const E2eeV2ParseError(
        'identity',
        detail: 'sender/receiver ids must be non-empty',
      );
    }
    if (senderId == receiverId) {
      throw const E2eeV2ParseError(
        'identity',
        detail: 'sender and receiver ids must be distinct',
      );
    }
    final salt = await saltFor(
      senderPublicKeyBytes: senderPublicKeyBytes,
      receiverPublicKeyBytes: receiverPublicKeyBytes,
    );
    final suffix = directionSuffix(senderId, receiverId);
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: sharedSecret,
      // Salt SIEMPRE explícito (32 bytes); no dependemos del default del
      // paquete (coherente con p2p_handshake_session.dart).
      nonce: Uint8List.fromList(salt),
      info: utf8.encode('$kV2KeyInfo$suffix'),
    );
  }

  // ── Cifrado ───────────────────────────────────────────────────────────

  /// Cifra `text` y devuelve el mapa de columnas del esquema actual:
  /// `encrypted_content` = envelope `zt2:` completo; `nonce`/`mac` cadenas
  /// vacías (compatibilidad con las columnas v1).
  ///
  /// `nonceOverride` SOLO para tests deterministas; en producción el nonce
  /// se genera con Random.secure() (12 bytes).
  static Future<Map<String, dynamic>> encrypt({
    required String text,
    required SecretKey sharedSecret,
    required E2eeV2MessageContext context,
    List<int>? nonceOverride,
  }) async {
    final key = await deriveDirectionKey(
      sharedSecret: sharedSecret,
      senderId: context.senderId,
      receiverId: context.receiverId,
      senderPublicKeyBytes: context.senderPublicKeyBytes,
      receiverPublicKeyBytes: context.receiverPublicKeyBytes,
    );

    final Uint8List nonce;
    if (nonceOverride == null) {
      nonce = _secureNonce();
    } else {
      if (nonceOverride.length != kV2NonceLength) {
        throw E2eeV2ParseError(
          'nonce_override',
          detail: 'nonce override must be $kV2NonceLength bytes',
        );
      }
      nonce = Uint8List.fromList(nonceOverride);
    }

    final box = await _aead.encrypt(
      utf8.encode(text),
      secretKey: key,
      nonce: nonce,
      aad: canonicalAadBytes(
        senderId: context.senderId,
        receiverId: context.receiverId,
        messageId: context.messageId,
        matchId: context.matchId,
      ),
    );

    final envelopeJson = <String, dynamic>{
      'v': kE2eeV2Version,
      's': context.senderId,
      'm': context.messageId,
      'i': context.matchId,
      'n': base64Encode(nonce),
      't': base64Encode(Uint8List.fromList(box.cipherText)),
      'h': base64Encode(Uint8List.fromList(box.mac.bytes)),
      'ap': kV2AadProfile,
    };
    final envelope =
        '$kZt2EnvelopePrefix${base64Encode(utf8.encode(jsonEncode(envelopeJson)))}';

    return <String, dynamic>{
      'encrypted_content': envelope,
      // Columnas v1 vacías: el esquema actual las exige; el runtime v1 las
      // descarta porque el prefijo `zt2:` gobierna la ruta de descifrado.
      'nonce': '',
      'mac': '',
    };
  }

  // ── Descifrado ────────────────────────────────────────────────────────

  /// Descifra un envelope v2 en el contexto REAL del receptor.
  ///
  /// - `receiverCandidates`: identidades locales propias (uid y/o handle
  ///   ZONE-) en orden fijo — el receptor no declara al emisor cuál usó;
  ///   probarlas son intentos de MAC locales, no oráculo de red.
  /// - `expectedMessageId`/`expectedMatchId`: vienen de la fila local; si el
  ///   envelope declara otros IDs, se rechaza ANTES de ejecutar el AEAD
  ///   (anti-replay transversal).
  /// - Lanza [E2eeV2ParseError] (malformado/versión) o
  ///   [E2eeV2AuthenticationError] (MAC no válido en ninguna identidad
  ///   candidata).
  static Future<String> decrypt({
    required String encryptedContent,
    required SecretKey sharedSecret,
    required String senderId,
    required List<String> receiverCandidates,
    required String expectedMessageId,
    required String expectedMatchId,
    required List<int> senderPublicKeyBytes,
    required List<int> receiverPublicKeyBytes,
  }) async {
    final parsed = _parseEnvelope(encryptedContent);

    // Binding envelope↔fila local (anti-replay transversal) ANTES de AEAD.
    if (parsed.messageId != expectedMessageId ||
        parsed.matchId != expectedMatchId) {
      throw const E2eeV2ParseError(
        'context',
        detail: 'envelope messageId/matchId no coincide con la fila local',
      );
    }

    for (final receiverId in receiverCandidates) {
      try {
        final key = await deriveDirectionKey(
          sharedSecret: sharedSecret,
          senderId: senderId,
          receiverId: receiverId,
          senderPublicKeyBytes: senderPublicKeyBytes,
          receiverPublicKeyBytes: receiverPublicKeyBytes,
        );
        final clearText = await _aead.decrypt(
          SecretBox(
            Uint8List.fromList(parsed.cipherText),
            nonce: Uint8List.fromList(parsed.nonce),
            mac: Mac(Uint8List.fromList(parsed.mac)),
          ),
          secretKey: key,
          aad: canonicalAadBytes(
            senderId: senderId,
            receiverId: receiverId,
            messageId: parsed.messageId,
            matchId: parsed.matchId,
          ),
        );
        return utf8.decode(clearText);
      } on SecretBoxAuthenticationError {
        // Candidata incorrecta (o AAD/clave alternados): probar la siguiente
        // identidad local. Un atacante que altera el envelope fracasa en
        // TODAS las candidatas.
        continue;
      } on FormatException {
        // utf8.decode sobre texto legítimo no lanza; si ocurre, es corrupción.
        throw const E2eeV2ParseError(
          'utf8_plaintext',
          detail: 'plaintext is not valid utf-8',
        );
      }
    }
    throw const E2eeV2AuthenticationError(
      'ninguna identidad candidata autenticó el envelope',
    );
  }

  // ── Formato canónico ──────────────────────────────────────────────────

  /// JSON canónico del AAD (orden de claves fijo y documentado).
  static String canonicalAadJsonFor({
    required String senderId,
    required String receiverId,
    required String messageId,
    required String matchId,
  }) {
    return '{'
        '"v":$kE2eeV2Version,'
        '"s":${_jsonString(senderId)},'
        '"r":${_jsonString(receiverId)},'
        '"m":${_jsonString(messageId)},'
        '"i":${_jsonString(matchId)}'
        '}';
  }

  /// Bytes del AAD para el AEAD.
  static List<int> canonicalAadBytes({
    required String senderId,
    required String receiverId,
    required String messageId,
    required String matchId,
  }) {
    return utf8.encode(
      canonicalAadJsonFor(
        senderId: senderId,
        receiverId: receiverId,
        messageId: messageId,
        matchId: matchId,
      ),
    );
  }

  /// Parse del envelope (fail-closed con E2eeV2ParseError).
  static E2eeV2Envelope parseEnvelope(String encryptedContent) =>
      _parseEnvelope(encryptedContent);

  static E2eeV2Envelope _parseEnvelope(String encryptedContent) {
    if (!isV2Envelope(encryptedContent)) {
      throw const E2eeV2ParseError(
        'prefix',
        detail: 'no es un envelope v2 (falta prefijo zt2:)',
      );
    }
    final trimmed = encryptedContent.trim();
    final payloadBase64 = trimmed.substring(kZt2EnvelopePrefix.length);
    if (payloadBase64.isEmpty) {
      throw const E2eeV2ParseError('empty', detail: 'envelope vacío');
    }

    final Uint8List decoded;
    try {
      decoded = base64Decode(payloadBase64);
    } on FormatException {
      throw const E2eeV2ParseError('base64', detail: 'envelope no es base64');
    }
    if (decoded.isEmpty) {
      throw const E2eeV2ParseError('empty', detail: 'envelope vacío');
    }

    final String text;
    try {
      text = utf8.decode(decoded);
    } on FormatException {
      throw const E2eeV2ParseError('utf8', detail: 'envelope no es utf-8');
    }

    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const E2eeV2ParseError('json', detail: 'envelope no es json');
    }
    if (json is! Map) {
      throw const E2eeV2ParseError(
        'shape',
        detail: 'el json del envelope no es objeto',
      );
    }

    final version = json['v'];
    if (version is! int || version != kE2eeV2Version) {
      throw E2eeV2ParseError(
        'version',
        detail: 'versión de envelope no soportada: $version',
      );
    }
    final ap = json['ap'];
    if (ap is! int || ap != kV2AadProfile) {
      throw E2eeV2ParseError(
        'aad_profile',
        detail: 'aad profile no soportado: $ap',
      );
    }
    final fields = <String>{'s', 'm', 'i', 'n', 't', 'h'};
    for (final key in fields) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw E2eeV2ParseError('field', detail: 'campo $key ausente o vacío');
      }
    }

    return E2eeV2Envelope(
      senderId: json['s'] as String,
      messageId: json['m'] as String,
      matchId: json['i'] as String,
      nonce: _decodeField(json, 'n', exactLength: kV2NonceLength),
      cipherText: _decodeField(json, 't'),
      mac: _decodeField(json, 'h'),
    );
  }

  // ── Utilidades ────────────────────────────────────────────────────────

  static Uint8List _decodeField(Map<Object?, Object?> json, String key,
      {int? exactLength}) {
    final Uint8List bytes;
    try {
      final decoded = base64Decode((json[key] as String).trim());
      bytes = Uint8List.fromList(decoded);
    } on FormatException {
      throw E2eeV2ParseError('base64', detail: 'campo $key no es base64');
    }
    if (exactLength != null && bytes.length != exactLength) {
      throw E2eeV2ParseError(
        'length',
        detail: 'campo $key debe ser $exactLength bytes (es ${bytes.length})',
      );
    }
    return bytes;
  }

  static Uint8List _secureNonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(kV2NonceLength, (_) => random.nextInt(256)),
    );
  }

  static (Uint8List, Uint8List) _orderedByBytes(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) {
        return a[i] < b[i]
            ? (Uint8List.fromList(a), Uint8List.fromList(b))
            : (Uint8List.fromList(b), Uint8List.fromList(a));
      }
    }
    return (Uint8List.fromList(a), Uint8List.fromList(b));
  }

  static bool _constantEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static void _validateKeyBytes(List<int> bytes, String name) {
    if (bytes.length != 32) {
      throw E2eeV2ParseError(
        'key_length',
        detail: '$name debe ser 32 bytes crudos (llegó ${bytes.length})',
      );
    }
  }

  static String _jsonString(String value) => canonicalJsonString(value);
}
