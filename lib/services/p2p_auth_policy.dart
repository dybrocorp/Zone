/// FASE E — Política de verificación del handshake P2P `ZONE-P2P-AKE-1`.
///
/// **Estado:** contrato de verificación puro; **NO integrado** en
/// `NearbyService` y **NO deriva claves**. La implementación del handshake y del
/// key schedule pertenece a la Fase G, con migración/recovery aprobados.
///
/// Este módulo existe para que los criterios de aceptación de Z-004 sean
/// ejecutables y para que la futura integración tenga una única autoridad de
/// decisión. No inventa primitivas: usa Ed25519 (firma, ya aprobada en D1) y
/// SHA-256 (hash estándar) sobre un transcript canónico versionado. X25519 se
/// transporta como clave pública, pero aquí **no** se ejecuta ECDH.
///
/// Reglas:
/// - Fail-closed: cualquier campo ausente, malformado, no canónico, revocado,
///   replayed o con clave distinta a la anclada se rechaza con razón tipada.
/// - Ningún rechazo deriva ni guarda una llave de sesión.
/// - El primer contacto (sin ancla) se acepta solo como `firstContact=true`:
///   el llamador DEBE exigir verificación fuera de banda del fingerprint antes
///   de persistir la confianza.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../identity/canonical.dart';
import '../identity/ed25519_identity_service.dart';
import '../identity/identity_errors.dart';
import '../identity/keys.dart';

/// Versión del transcript/handshake. Cambiarla invalida firmas antiguas.
const String kP2PAuthVersion = 'ZONE-P2P-AKE-1';

/// Dominio de separación del transcript (incluye el byte NUL).
const String _kTranscriptDomain = 'ZONE-P2P-AKE-1\u0000';

/// Algoritmos esperados por propósito (D1/D2). Nunca se intercambian.
const String kP2PIdentityKeyAlgorithm = 'Ed25519';
const String kP2PEncryptionKeyAlgorithm = 'X25519';

/// TTL por defecto de un `hello` (anti-replay / anti-handshake viejo).
const Duration kP2PHandshakeTtl = Duration(minutes: 2);

/// Tolerancia por defecto para relojes adelantados.
const Duration kP2PHandshakeFutureSkew = Duration(seconds: 30);

/// Handle canónico `ZONE-XXXXXXXX`.
final RegExp _zoneIdPattern = RegExp(r'^ZONE-[A-Z0-9]{8}$');

/// UUID v4 canónico (minúsculas) para `sessionId`.
final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Motivo tipado de rechazo. `none` solo aparece en una decisión aceptada.
enum P2PAuthRejectReason {
  none,
  unsupportedVersion,
  incompleteNegotiation,
  invalidZoneId,
  invalidAccountId,
  invalidDeviceId,
  invalidIdentityKey,
  invalidEncryptionKey,
  invalidEphemeralKey,
  invalidNonce,
  invalidSessionId,
  invalidSignature,
  keyPurposeMismatch,
  identityMismatch,
  identityKeySubstitution,
  encryptionKeySubstitution,
  keyVersionRollback,
  keyRotationRequired,
  staleHandshake,
  replayedSession,
  sessionReuse,
  revokedDevice,
  invalidTrustAnchor,
}

/// Decisión de verificación con evidencia pública (sin material secreto).
class P2PAuthDecision {
  const P2PAuthDecision._({
    required this.accepted,
    required this.reason,
    this.detail,
    this.firstContact = false,
    this.transcriptHashHex,
  });

  final bool accepted;
  final P2PAuthRejectReason reason;
  final String? detail;

  /// `true` si no había ancla previa. No significa "confiable": exige
  /// verificación fuera de banda antes de persistir la confianza.
  final bool firstContact;

  /// SHA-256 del transcript canónico (hex) cuando se pudo construir.
  final String? transcriptHashHex;

  factory P2PAuthDecision.accept({
    required bool firstContact,
    required String transcriptHashHex,
  }) => P2PAuthDecision._(
    accepted: true,
    reason: P2PAuthRejectReason.none,
    firstContact: firstContact,
    transcriptHashHex: transcriptHashHex,
  );

  factory P2PAuthDecision.reject(
    P2PAuthRejectReason reason, {
    String? detail,
    String? transcriptHashHex,
  }) => P2PAuthDecision._(
    accepted: false,
    reason: reason,
    detail: detail,
    transcriptHashHex: transcriptHashHex,
  );

  @override
  String toString() =>
      'P2PAuthDecision(accepted: $accepted, reason: ${reason.name}'
      '${detail == null ? '' : ', detail: $detail'})';
}

/// `hello` de un peer. Los campos son exactamente los que firma el emisor.
///
/// `deviceStatus`/`revokedAt` son entradas de confianza locales (estado
/// archivado), no viajan en el transcript firmado.
class P2PAuthHello {
  const P2PAuthHello({
    required this.version,
    required this.zoneId,
    required this.accountId,
    required this.deviceId,
    required this.identityKeyAlgorithm,
    required this.identityPublicKeyBase64,
    required this.encryptionKeyAlgorithm,
    required this.encryptionPublicKeyBase64,
    required this.encryptionKeyVersion,
    required this.ephemeralPublicKeyBase64,
    required this.nonceBase64,
    required this.sessionId,
    required this.issuedAtMs,
    required this.signatureBase64,
    required this.deviceStatus,
    this.revokedAt,
  });

  final String version;
  final String zoneId;
  final String accountId;
  final String deviceId;
  final String identityKeyAlgorithm;
  final String identityPublicKeyBase64;
  final String encryptionKeyAlgorithm;
  final String encryptionPublicKeyBase64;
  final int encryptionKeyVersion;
  final String ephemeralPublicKeyBase64;
  final String nonceBase64;
  final String sessionId;
  final int issuedAtMs;
  final String signatureBase64;
  final DeviceStatus deviceStatus;
  final DateTime? revokedAt;

  static const Object _unset = Object();

  /// Copia con reemplazos explícitos. `revokedAt` usa un centinela para poder
  /// limpiarlo a `null`; el resto conserva el valor actual si se omite.
  P2PAuthHello copyWith({
    String? version,
    String? zoneId,
    String? accountId,
    String? deviceId,
    String? identityKeyAlgorithm,
    String? identityPublicKeyBase64,
    String? encryptionKeyAlgorithm,
    String? encryptionPublicKeyBase64,
    int? encryptionKeyVersion,
    String? ephemeralPublicKeyBase64,
    String? nonceBase64,
    String? sessionId,
    int? issuedAtMs,
    String? signatureBase64,
    DeviceStatus? deviceStatus,
    Object? revokedAt = _unset,
  }) => P2PAuthHello(
    version: version ?? this.version,
    zoneId: zoneId ?? this.zoneId,
    accountId: accountId ?? this.accountId,
    deviceId: deviceId ?? this.deviceId,
    identityKeyAlgorithm: identityKeyAlgorithm ?? this.identityKeyAlgorithm,
    identityPublicKeyBase64:
        identityPublicKeyBase64 ?? this.identityPublicKeyBase64,
    encryptionKeyAlgorithm:
        encryptionKeyAlgorithm ?? this.encryptionKeyAlgorithm,
    encryptionPublicKeyBase64:
        encryptionPublicKeyBase64 ?? this.encryptionPublicKeyBase64,
    encryptionKeyVersion: encryptionKeyVersion ?? this.encryptionKeyVersion,
    ephemeralPublicKeyBase64:
        ephemeralPublicKeyBase64 ?? this.ephemeralPublicKeyBase64,
    nonceBase64: nonceBase64 ?? this.nonceBase64,
    sessionId: sessionId ?? this.sessionId,
    issuedAtMs: issuedAtMs ?? this.issuedAtMs,
    signatureBase64: signatureBase64 ?? this.signatureBase64,
    deviceStatus: deviceStatus ?? this.deviceStatus,
    revokedAt: identical(revokedAt, _unset)
        ? this.revokedAt
        : revokedAt as DateTime?,
  );
}

/// Ancla de confianza local para un peer ya verificado.
///
/// En el primer contacto se crea tras comparar el DEVICE_FINGERPRINT por un
/// canal fuera de banda. Una rotación legítima exige un registro firmado por la
/// identidad de cuenta (Fase G); este contrato rechaza cambios silenciosos.
class P2PTrustAnchor {
  const P2PTrustAnchor({
    required this.identityPublicKeyBase64,
    required this.encryptionPublicKeyBase64,
    required this.encryptionKeyVersion,
  });

  final String identityPublicKeyBase64;
  final String encryptionPublicKeyBase64;
  final int encryptionKeyVersion;
}

/// Caché de `sessionId` ya aceptados (anti-replay), con TTL y LRU acotada.
///
/// No sustituye a la deduplicación de mensajes: evita reutilizar un handshake
/// completo. La ventana debe cubrir al menos el TTL del handshake.
class P2PSessionReplayCache {
  P2PSessionReplayCache({
    this.ttl = const Duration(minutes: 10),
    this.maxEntries = 512,
  });

  final Duration ttl;
  final int maxEntries;
  final Map<String, DateTime> _seen = {};

  bool contains(String sessionId, {DateTime? now}) {
    _prune((now ?? DateTime.now()).toUtc());
    return _seen.containsKey(sessionId);
  }

  /// Registra el `sessionId`. `false` si ya existía dentro de la ventana.
  bool register(String sessionId, {DateTime? now}) {
    final at = (now ?? DateTime.now()).toUtc();
    _prune(at);
    if (_seen.containsKey(sessionId)) return false;
    _seen[sessionId] = at;
    if (_seen.length > maxEntries) {
      String? oldestKey;
      DateTime? oldestAt;
      _seen.forEach((key, ts) {
        if (oldestAt == null || ts.isBefore(oldestAt!)) {
          oldestKey = key;
          oldestAt = ts;
        }
      });
      if (oldestKey != null) _seen.remove(oldestKey);
    }
    return true;
  }

  void clear() => _seen.clear();

  int get length => _seen.length;

  void _prune(DateTime now) {
    _seen.removeWhere((_, ts) => now.difference(ts) > ttl);
  }
}

/// Autoridad única de verificación del `hello` P2P.
class P2PAuthPolicy {
  P2PAuthPolicy._();

  static final Sha256 _sha256 = Sha256();

  /// Transcript canónico versionado. Codificación:
  ///
  /// ```
  /// utf8("ZONE-P2P-AKE-1\0")
  /// ‖ lp("hello")
  /// ‖ lp(version)
  /// ‖ lp(zone_id en mayúsculas)
  /// ‖ lp(account_id canónico)
  /// ‖ lp(device_id canónico)
  /// ‖ lp(identity_key_algorithm)
  /// ‖ lp(identity_public_key base64)
  /// ‖ lp(encryption_key_algorithm)
  /// ‖ lp(encryption_public_key base64)
  /// ‖ lp(encryption_key_version decimal)
  /// ‖ lp(ephemeral_public_key base64)
  /// ‖ lp(nonce base64)
  /// ‖ lp(session_id canónico)
  /// ‖ lp(issued_at_ms decimal)
  /// [‖ lp("prior") ‖ lp(prior_transcript_hash base64)]
  /// ```
  ///
  /// `lp(x) = uint32_be(utf8(x).length) ‖ utf8(x)`. La firma Ed25519 NO entra
  /// en el transcript (es la firma de este). El orden y los prefijos eliminan
  /// ambigüedades de concatenación.
  static Uint8List canonicalTranscript({
    required P2PAuthHello hello,
    List<int>? priorTranscriptHash,
  }) {
    final parts = <List<int>>[
      CanonicalCodec.utf8Bytes(_kTranscriptDomain),
      _lp('hello'),
      _lp(hello.version),
      _lp(hello.zoneId.toUpperCase()),
      _lp(hello.accountId.toLowerCase()),
      _lp(hello.deviceId.toLowerCase()),
      _lp(hello.identityKeyAlgorithm),
      _lp(hello.identityPublicKeyBase64),
      _lp(hello.encryptionKeyAlgorithm),
      _lp(hello.encryptionPublicKeyBase64),
      _lp(hello.encryptionKeyVersion.toString()),
      _lp(hello.ephemeralPublicKeyBase64),
      _lp(hello.nonceBase64),
      _lp(hello.sessionId.toLowerCase()),
      _lp(hello.issuedAtMs.toString()),
    ];
    if (priorTranscriptHash != null) {
      parts
        ..add(_lp('prior'))
        ..add(_lp(base64Encode(priorTranscriptHash)));
    }
    return CanonicalCodec.concat(parts);
  }

  /// SHA-256 del transcript. Se expone para encadenar `hello_A` → `hello_B` y
  /// para evidencia; no es una clave.
  static Future<Uint8List> transcriptHash({
    required P2PAuthHello hello,
    List<int>? priorTranscriptHash,
  }) async {
    final digest = await _sha256.hash(
      canonicalTranscript(
        hello: hello,
        priorTranscriptHash: priorTranscriptHash,
      ),
    );
    return Uint8List.fromList(digest.bytes);
  }

  /// Verifica un `hello` antes de aceptar identidad, derivar sesión o tocar
  /// estado. Devuelve una decisión tipada; nunca lanza por input del peer.
  ///
  /// Orden deliberado: primero forma/canonicalidad, luego estado local
  /// (revocación/ancla/replay), y por último la firma. Así los tests distinguen
  /// sustitución de clave de transcript adulterado, sin relajar ninguna
  /// comprobación.
  static Future<P2PAuthDecision> verifyHello({
    required P2PAuthHello hello,
    required P2PSessionReplayCache replayCache,
    P2PTrustAnchor? trustAnchor,
    String? expectedZoneId,
    Set<String> activeSessionIds = const <String>{},
    List<int>? priorTranscriptHash,
    DateTime? now,
    Duration handshakeTtl = kP2PHandshakeTtl,
    Duration maxFutureSkew = kP2PHandshakeFutureSkew,
  }) async {
    final missing = _firstMissingField(hello);
    if (missing != null) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.incompleteNegotiation,
        detail: 'missing $missing',
      );
    }

    if (hello.version != kP2PAuthVersion) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.unsupportedVersion,
        detail: 'version ${hello.version}',
      );
    }

    if (hello.zoneId != hello.zoneId.trim().toUpperCase() ||
        !_zoneIdPattern.hasMatch(hello.zoneId)) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.invalidZoneId,
        detail: 'zone_id must be canonical ZONE-XXXXXXXX',
      );
    }

    final accountId = _canonicalUuid(hello.accountId);
    if (accountId == null || accountId != hello.accountId) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.invalidAccountId,
        detail: 'account_id must be canonical lowercase UUID',
      );
    }
    final deviceId = _canonicalUuid(hello.deviceId);
    if (deviceId == null || deviceId != hello.deviceId) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.invalidDeviceId,
        detail: 'device_id must be canonical lowercase UUID',
      );
    }
    if (!_uuidV4Pattern.hasMatch(hello.sessionId)) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.invalidSessionId,
        detail: 'session_id must be canonical lowercase UUID v4',
      );
    }

    if (hello.identityKeyAlgorithm != kP2PIdentityKeyAlgorithm ||
        hello.encryptionKeyAlgorithm != kP2PEncryptionKeyAlgorithm) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.keyPurposeMismatch,
        detail: 'expected Ed25519 signing + X25519 encryption',
      );
    }

    final identityKey = _decodeExact(hello.identityPublicKeyBase64, 32);
    if (identityKey == null) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.invalidIdentityKey,
        detail: 'identity public key must be 32 raw bytes (base64)',
      );
    }
    final encryptionKey = _decodeExact(hello.encryptionPublicKeyBase64, 32);
    if (encryptionKey == null) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.invalidEncryptionKey,
        detail: 'encryption public key must be 32 raw bytes (base64)',
      );
    }
    if (_decodeExact(hello.ephemeralPublicKeyBase64, 32) == null) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.invalidEphemeralKey,
        detail: 'ephemeral public key must be 32 raw bytes (base64)',
      );
    }
    if (_decodeExact(hello.nonceBase64, 32) == null) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.invalidNonce,
        detail: 'nonce must be 32 raw bytes (base64)',
      );
    }
    final signature = _decodeExact(hello.signatureBase64, 64);
    if (signature == null) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.invalidSignature,
        detail: 'signature must be 64 raw bytes (base64)',
      );
    }

    if (hello.deviceStatus != DeviceStatus.active || hello.revokedAt != null) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.revokedDevice,
        detail:
            'device status ${hello.deviceStatus.statusId}'
            '${hello.revokedAt == null ? '' : ' (revoked_at set)'}',
      );
    }

    final nowUtc = (now ?? DateTime.now()).toUtc();
    final issuedAt = DateTime.fromMillisecondsSinceEpoch(
      hello.issuedAtMs,
      isUtc: true,
    );
    final age = nowUtc.difference(issuedAt);
    if (age > handshakeTtl || age < -maxFutureSkew) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.staleHandshake,
        detail: 'issued_at outside TTL window',
      );
    }

    if (activeSessionIds.contains(hello.sessionId)) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.sessionReuse,
        detail: 'session_id already active',
      );
    }
    if (replayCache.contains(hello.sessionId, now: nowUtc)) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.replayedSession,
        detail: 'session_id already consumed',
      );
    }

    if (trustAnchor != null) {
      final anchoredIdentity = _decodeExact(
        trustAnchor.identityPublicKeyBase64,
        32,
      );
      final anchoredEncryption = _decodeExact(
        trustAnchor.encryptionPublicKeyBase64,
        32,
      );
      if (anchoredIdentity == null || anchoredEncryption == null) {
        return P2PAuthDecision.reject(
          P2PAuthRejectReason.invalidTrustAnchor,
          detail: 'trust anchor keys are malformed',
        );
      }
      if (!_bytesEqual(identityKey, anchoredIdentity)) {
        return P2PAuthDecision.reject(
          P2PAuthRejectReason.identityKeySubstitution,
          detail: 'identity key differs from pinned key',
        );
      }
      if (!_bytesEqual(encryptionKey, anchoredEncryption)) {
        return P2PAuthDecision.reject(
          P2PAuthRejectReason.encryptionKeySubstitution,
          detail: 'encryption key differs from pinned key',
        );
      }
      if (hello.encryptionKeyVersion < trustAnchor.encryptionKeyVersion) {
        return P2PAuthDecision.reject(
          P2PAuthRejectReason.keyVersionRollback,
          detail: 'encryption key version rolled back',
        );
      }
      if (hello.encryptionKeyVersion > trustAnchor.encryptionKeyVersion) {
        return P2PAuthDecision.reject(
          P2PAuthRejectReason.keyRotationRequired,
          detail: 'new encryption key version needs a signed rotation record',
        );
      }
    }

    if (expectedZoneId != null &&
        hello.zoneId != expectedZoneId.trim().toUpperCase()) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.identityMismatch,
        detail: 'hello zone_id differs from bound identity',
      );
    }

    final transcript = canonicalTranscript(
      hello: hello,
      priorTranscriptHash: priorTranscriptHash,
    );
    final digest = await _sha256.hash(transcript);
    final transcriptHex = _toHex(digest.bytes);

    final signatureValid = await Ed25519IdentityService.verify(
      publicKeyBytes: identityKey,
      message: transcript,
      signatureBytes: signature,
    );
    if (!signatureValid) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.invalidSignature,
        detail: 'Ed25519 signature does not match canonical transcript',
        transcriptHashHex: transcriptHex,
      );
    }

    // El registro ocurre SOLO tras aceptar; un rechazo no consume el ID.
    if (!replayCache.register(hello.sessionId, now: nowUtc)) {
      return P2PAuthDecision.reject(
        P2PAuthRejectReason.replayedSession,
        detail: 'session_id registered concurrently',
        transcriptHashHex: transcriptHex,
      );
    }

    return P2PAuthDecision.accept(
      firstContact: trustAnchor == null,
      transcriptHashHex: transcriptHex,
    );
  }

  static String? _firstMissingField(P2PAuthHello hello) {
    final fields = <String, bool>{
      'version': hello.version.trim().isEmpty,
      'zone_id': hello.zoneId.trim().isEmpty,
      'account_id': hello.accountId.trim().isEmpty,
      'device_id': hello.deviceId.trim().isEmpty,
      'identity_key_algorithm': hello.identityKeyAlgorithm.trim().isEmpty,
      'identity_public_key': hello.identityPublicKeyBase64.trim().isEmpty,
      'encryption_key_algorithm': hello.encryptionKeyAlgorithm.trim().isEmpty,
      'encryption_public_key': hello.encryptionPublicKeyBase64.trim().isEmpty,
      'encryption_key_version': hello.encryptionKeyVersion <= 0,
      'ephemeral_public_key': hello.ephemeralPublicKeyBase64.trim().isEmpty,
      'nonce': hello.nonceBase64.trim().isEmpty,
      'session_id': hello.sessionId.trim().isEmpty,
      'issued_at_ms': hello.issuedAtMs <= 0,
      'signature': hello.signatureBase64.trim().isEmpty,
    };
    for (final entry in fields.entries) {
      if (entry.value) return entry.key;
    }
    return null;
  }

  static String? _canonicalUuid(String value) {
    try {
      return CanonicalCodec.uuidCanonical(value);
    } on IdentityFoundationError {
      return null;
    } on FormatException {
      return null;
    }
  }

  static List<int>? _decodeExact(String value, int length) {
    try {
      final bytes = base64Decode(value.trim());
      return bytes.length == length ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static Uint8List _lp(String value) {
    final bytes = CanonicalCodec.utf8Bytes(value);
    final length = bytes.length;
    return Uint8List.fromList([
      (length >> 24) & 0xff,
      (length >> 16) & 0xff,
      (length >> 8) & 0xff,
      length & 0xff,
      ...bytes,
    ]);
  }

  static String _toHex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toLowerCase();
}
