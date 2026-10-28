/// FASE E/G — Orquestador del handshake `ZONE-P2P-AKE-1`.
///
/// **INTEGRATION-READY — NOT WIRED INTO `NearbyService`.**
///
/// Esta capa une el contrato puro [P2PAuthPolicy] con el key schedule aprobado
/// en `CRYPTO_CTO_REVIEW.md` §5.2:
///
/// ```text
/// dh1 = X25519(eph_I, static_R)   dh2 = X25519(static_I, eph_R)
/// dh3 = X25519(eph_I, eph_R)      dh4 = X25519(static_I, static_R)
/// salt = identity_pk_I ‖ identity_pk_R
/// master = HKDF-SHA256(dh1‖dh2‖dh3‖dh4, salt, info="zone-xtdhs-v1")
/// session = HKDF-SHA256(master, salt=0^32,
///                       info="zone-session" ‖ 0x00 ‖ transcript_hash_final)
/// ```
///
/// Decisiones de integración que **requieren revisión CTO** (documentadas en
/// `docs/audit/PHASE_E_P2P_AUTH_DESIGN.md` §7):
///
/// - `identity_public_key` del `hello` es la clave Ed25519 **del dispositivo**,
///   no la de cuenta. El `hello` v1 no transporta un certificado de dispositivo
///   firmado por la cuenta; por tanto `account_id` es declarativo hasta que
///   exista `device_certificate` (v2). No se cambia el transcript v1.
/// - El hash del transcript final se añade al `info` del HKDF como contexto
///   jerárquico (la autoridad ya exige `info` jerárquico). Sin él, la clave de
///   sesión no queda ligada a los nonces/efímeros del handshake.
/// - `deviceStatus`/`revokedAt` los aporta el llamador desde el registro local
///   de confianza; **nunca** se aceptan del cable.
///
/// Esta clase **no** se instancia desde producción todavía. Mientras no se
/// cablee y no exista verificación OOB del primer contacto, **Z-004 sigue
/// abierto**.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../identity/ed25519_identity_service.dart';
import '../identity/keys.dart';
import '../identity/x25519_device_service.dart';
import 'p2p_auth_policy.dart';

/// Rol local en el handshake de dos mensajes.
enum P2PHandshakeRole {
  /// Envía `hello_A` sin `prior` y recibe `hello_B` encadenado.
  initiator,

  /// Recibe `hello_A`, lo verifica y responde `hello_B` con `prior`.
  responder,
}

/// Fallo de orquestación (distinto de un rechazo criptográfico del peer).
enum P2PHandshakeFailure {
  endpointNotBound,
  endpointMismatch,
  localHelloMissing,
  remoteHelloMissing,
  remoteHelloRejected,
  transcriptBindingRequired,
  unexpectedPriorTranscript,
  alreadyCompleted,
  destroyed,
}

/// Error tipado del orquestador. No contiene material secreto.
class P2PHandshakeException implements Exception {
  const P2PHandshakeException(this.failure, {this.detail, this.decision});

  final P2PHandshakeFailure failure;
  final String? detail;

  /// Decisión del contrato cuando el fallo deriva de un rechazo del peer.
  final P2PAuthDecision? decision;

  @override
  String toString() {
    final reason = decision?.reason.name;
    return 'P2PHandshakeException(${failure.name}'
        '${reason == null ? '' : ', reason=$reason'}'
        '${detail == null ? '' : ', detail=$detail'})';
  }
}

/// Material de sesión derivado. `toString` está redactado a propósito.
class P2PSessionKeyMaterial {
  P2PSessionKeyMaterial({
    required Uint8List keyBytes,
    required Uint8List transcriptHash,
    required this.initiatorSessionId,
    required this.responderSessionId,
    required this.firstContact,
  }) : keyBytes = Uint8List.fromList(keyBytes),
       transcriptHash = Uint8List.fromList(transcriptHash);

  /// Clave de 32 bytes para ChaCha20-Poly1305. Nunca se registra en logs.
  final Uint8List keyBytes;

  /// SHA-256 del transcript final (`hello_B` con `prior`).
  final Uint8List transcriptHash;

  final String initiatorSessionId;
  final String responderSessionId;
  final bool firstContact;

  @override
  String toString() =>
      'P2PSessionKeyMaterial(key=<redacted>, '
      'transcript=${transcriptHash.length}B, firstContact=$firstContact)';
}

/// Sesión de handshake de un solo uso.
///
/// El ciclo válido es:
///
/// ```text
/// iniciador:  createHello() ─────────────────────────────┐
/// responder:  acceptPeerHello(A) → createHello(prior=A) ─┤
/// iniciador:  acceptPeerHello(B, prior=A) ───────────────┤
/// ambos:      complete()                                 ┘
/// ```
///
/// Cualquier intento de `complete()` fuera de ese orden falla cerrado.
class P2PHandshakeSession {
  P2PHandshakeSession({
    required this.role,
    required this.zoneId,
    required this.accountId,
    required this.deviceId,
    required this.identityKeyPair,
    required this.encryptionKeyPair,
    required this.encryptionKeyVersion,
    required this.endpointId,
    P2PSessionReplayCache? replayCache,
    SimpleKeyPair? ephemeralKeyPair,
    String? sessionId,
    List<int>? nonce,
    Uuid? uuid,
  }) : _replayCache = replayCache ?? P2PSessionReplayCache(),
       _ephemeralKeyPair = ephemeralKeyPair,
       _sessionId = sessionId,
       _nonce = nonce == null ? null : Uint8List.fromList(nonce),
       _uuid = uuid ?? const Uuid();

  final P2PHandshakeRole role;
  final String zoneId;
  final String accountId;
  final String deviceId;
  final SimpleKeyPair identityKeyPair;
  final SimpleKeyPair encryptionKeyPair;
  final int encryptionKeyVersion;

  /// `endpointId` de Nearby Connections asociado a este handshake. Es la única
  /// asociación transporte↔identidad aceptada.
  final String endpointId;

  final P2PSessionReplayCache _replayCache;
  final Uuid _uuid;

  SimpleKeyPair? _ephemeralKeyPair;
  String? _sessionId;
  Uint8List? _nonce;

  P2PAuthHello? _localHello;
  P2PAuthHello? _remoteHello;
  P2PAuthDecision? _remoteDecision;
  Uint8List? _localTranscriptHash;
  Uint8List? _remoteTranscriptHash;
  Uint8List? _finalTranscriptHash;
  Uint8List? _localPriorTranscriptHash;
  Uint8List? _remotePriorTranscriptHash;
  P2PSessionKeyMaterial? _sessionKey;
  bool _destroyed = false;

  P2PAuthHello? get localHello => _localHello;
  P2PAuthHello? get remoteHello => _remoteHello;
  P2PAuthDecision? get remoteDecision => _remoteDecision;
  P2PSessionKeyMaterial? get sessionKey => _sessionKey;
  Uint8List? get localTranscriptHash => _localTranscriptHash;
  Uint8List? get remoteTranscriptHash => _remoteTranscriptHash;
  Uint8List? get finalTranscriptHash => _finalTranscriptHash;
  bool get isCompleted => _sessionKey != null;

  /// Construye y firma el `hello` local.
  ///
  /// - El iniciador lo llama sin `priorTranscriptHash`.
  /// - El responder lo llama con el hash del `hello` del iniciador.
  ///
  /// Es idempotente: devuelve el mismo `hello` si ya se construyó.
  Future<P2PAuthHello> createHello({
    List<int>? priorTranscriptHash,
    DateTime? now,
  }) async {
    _ensureUsable();
    final existing = _localHello;
    if (existing != null) return existing;

    if (role == P2PHandshakeRole.initiator &&
        priorTranscriptHash != null) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.unexpectedPriorTranscript,
        detail: 'the initiator hello must not carry a prior transcript',
      );
    }
    if (role == P2PHandshakeRole.responder &&
        priorTranscriptHash == null) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.transcriptBindingRequired,
        detail: 'the responder hello must bind the initiator transcript',
      );
    }

    final ephemeral = _ephemeralKeyPair ??= await X25519().newKeyPair();
    final issuedAt = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    final sessionId = _sessionId ??= _uuid.v4();
    final nonce = _nonce ??= _secureRandomBytes(32);

    final unsigned = P2PAuthHello(
      version: kP2PAuthVersion,
      zoneId: zoneId,
      accountId: accountId,
      deviceId: deviceId,
      identityKeyAlgorithm: kP2PIdentityKeyAlgorithm,
      identityPublicKeyBase64:
          await Ed25519IdentityService.publicKeyBase64(identityKeyPair),
      encryptionKeyAlgorithm: kP2PEncryptionKeyAlgorithm,
      encryptionPublicKeyBase64:
          await X25519DeviceEncryptionService.publicKeyBase64(
            encryptionKeyPair,
          ),
      encryptionKeyVersion: encryptionKeyVersion,
      ephemeralPublicKeyBase64:
          await X25519DeviceEncryptionService.publicKeyBase64(ephemeral),
      nonceBase64: base64Encode(nonce),
      sessionId: sessionId,
      issuedAtMs: issuedAt,
      signatureBase64: '',
      // Estado local del propio dispositivo. No viaja en el transcript.
      deviceStatus: DeviceStatus.active,
      revokedAt: null,
    );

    final transcript = P2PAuthPolicy.canonicalTranscript(
      hello: unsigned,
      priorTranscriptHash: priorTranscriptHash,
    );
    final signature = await Ed25519IdentityService.sign(
      identityKeyPair,
      transcript,
    );

    final signed = unsigned.copyWith(signatureBase64: base64Encode(signature));
    _localHello = signed;
    _localPriorTranscriptHash = priorTranscriptHash == null
        ? null
        : Uint8List.fromList(priorTranscriptHash);
    _localTranscriptHash = await P2PAuthPolicy.transcriptHash(
      hello: signed,
      priorTranscriptHash: priorTranscriptHash,
    );
    return signed;
  }

  /// Verifica el `hello` del peer con [P2PAuthPolicy].
  ///
  /// Devuelve la decisión (aceptada o rechazada) para que el llamador pueda
  /// registrar evidencia. Un rechazo **no** deriva claves; [complete] fallará.
  Future<P2PAuthDecision> acceptPeerHello(
    P2PAuthHello hello, {
    P2PTrustAnchor? trustAnchor,
    String? expectedZoneId,
    Set<String> activeSessionIds = const <String>{},
    List<int>? priorTranscriptHash,
    DateTime? now,
    Duration handshakeTtl = kP2PHandshakeTtl,
    Duration maxFutureSkew = kP2PHandshakeFutureSkew,
  }) async {
    _ensureUsable();

    if (role == P2PHandshakeRole.initiator && priorTranscriptHash == null) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.transcriptBindingRequired,
        detail: 'the initiator must verify the responder hello with prior',
      );
    }
    if (role == P2PHandshakeRole.responder && priorTranscriptHash != null) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.unexpectedPriorTranscript,
        detail: 'the responder must verify the initiator hello without prior',
      );
    }

    final decision = await P2PAuthPolicy.verifyHello(
      hello: hello,
      replayCache: _replayCache,
      trustAnchor: trustAnchor,
      expectedZoneId: expectedZoneId,
      activeSessionIds: activeSessionIds,
      priorTranscriptHash: priorTranscriptHash,
      now: now,
      handshakeTtl: handshakeTtl,
      maxFutureSkew: maxFutureSkew,
    );

    _remoteHello = hello;
    _remoteDecision = decision;
    _remotePriorTranscriptHash = priorTranscriptHash == null
        ? null
        : Uint8List.fromList(priorTranscriptHash);
    if (decision.accepted) {
      _remoteTranscriptHash = await P2PAuthPolicy.transcriptHash(
        hello: hello,
        priorTranscriptHash: priorTranscriptHash,
      );
    }
    return decision;
  }

  /// Comprueba que un paquete llega por el `endpointId` ligado al handshake.
  ///
  /// Debe invocarse antes de procesar cualquier payload de aplicación. Un
  /// `endpointId` distinto invalida la sesión (no se reasocia).
  void assertEndpoint(String incomingEndpointId) {
    _ensureUsable();
    if (incomingEndpointId != endpointId) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.endpointMismatch,
        detail: 'payload arrived on a different Nearby endpoint',
      );
    }
  }

  /// Deriva la clave de sesión. Solo si ambos `hello` están presentes, el peer
  /// fue aceptado y el binding de transcript es correcto.
  Future<P2PSessionKeyMaterial> complete() async {
    _ensureUsable();
    if (_sessionKey != null) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.alreadyCompleted,
        detail: 'session key already derived for this handshake',
      );
    }

    final local = _localHello;
    if (local == null) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.localHelloMissing,
        detail: 'createHello() was not called',
      );
    }
    final remote = _remoteHello;
    final decision = _remoteDecision;
    if (remote == null || decision == null) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.remoteHelloMissing,
        detail: 'acceptPeerHello() was not called',
      );
    }
    if (!decision.accepted) {
      throw P2PHandshakeException(
        P2PHandshakeFailure.remoteHelloRejected,
        detail: decision.detail,
        decision: decision,
      );
    }

    final initiatorHello = role == P2PHandshakeRole.initiator ? local : remote;
    final responderHello = role == P2PHandshakeRole.initiator ? remote : local;
    final initiatorPrior = role == P2PHandshakeRole.initiator
        ? _localPriorTranscriptHash
        : _remotePriorTranscriptHash;
    final responderPrior = role == P2PHandshakeRole.initiator
        ? _remotePriorTranscriptHash
        : _localPriorTranscriptHash;

    if (initiatorPrior != null) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.unexpectedPriorTranscript,
        detail: 'the initiator hello carried a prior transcript',
      );
    }
    if (responderPrior == null) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.transcriptBindingRequired,
        detail: 'the responder hello did not bind the initiator transcript',
      );
    }

    final initiatorHash = await P2PAuthPolicy.transcriptHash(
      hello: initiatorHello,
    );
    if (!_constantTimeEquals(responderPrior, initiatorHash)) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.transcriptBindingRequired,
        detail: 'responder prior does not match the initiator transcript',
      );
    }

    final finalHash = await P2PAuthPolicy.transcriptHash(
      hello: responderHello,
      priorTranscriptHash: initiatorHash,
    );
    _finalTranscriptHash = finalHash;

    final ephemeral = _ephemeralKeyPair;
    if (ephemeral == null) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.localHelloMissing,
        detail: 'ephemeral keypair was destroyed',
      );
    }

    final initiatorStaticPublic = _decodePublicKey(
      initiatorHello.encryptionPublicKeyBase64,
    );
    final responderStaticPublic = _decodePublicKey(
      responderHello.encryptionPublicKeyBase64,
    );
    final initiatorEphemeralPublic = _decodePublicKey(
      initiatorHello.ephemeralPublicKeyBase64,
    );
    final responderEphemeralPublic = _decodePublicKey(
      responderHello.ephemeralPublicKeyBase64,
    );

    final localIsInitiator = role == P2PHandshakeRole.initiator;
    final localStatic = encryptionKeyPair;
    final localEphemeral = ephemeral;

    // dh1 = eph_I × static_R
    final dh1 = localIsInitiator
        ? await X25519DeviceEncryptionService.sharedSecret(
            localKeyPair: localEphemeral,
            remotePublicKey: responderStaticPublic,
          )
        : await X25519DeviceEncryptionService.sharedSecret(
            localKeyPair: localStatic,
            remotePublicKey: initiatorEphemeralPublic,
          );
    // dh2 = static_I × eph_R
    final dh2 = localIsInitiator
        ? await X25519DeviceEncryptionService.sharedSecret(
            localKeyPair: localStatic,
            remotePublicKey: responderEphemeralPublic,
          )
        : await X25519DeviceEncryptionService.sharedSecret(
            localKeyPair: localEphemeral,
            remotePublicKey: initiatorStaticPublic,
          );
    // dh3 = eph_I × eph_R
    final dh3 = localIsInitiator
        ? await X25519DeviceEncryptionService.sharedSecret(
            localKeyPair: localEphemeral,
            remotePublicKey: responderEphemeralPublic,
          )
        : await X25519DeviceEncryptionService.sharedSecret(
            localKeyPair: localEphemeral,
            remotePublicKey: initiatorEphemeralPublic,
          );
    // dh4 = static_I × static_R
    final dh4 = localIsInitiator
        ? await X25519DeviceEncryptionService.sharedSecret(
            localKeyPair: localStatic,
            remotePublicKey: responderStaticPublic,
          )
        : await X25519DeviceEncryptionService.sharedSecret(
            localKeyPair: localStatic,
            remotePublicKey: initiatorStaticPublic,
          );

    final sharedSecretBuilder = BytesBuilder(copy: false);
    sharedSecretBuilder.add(await dh1.extractBytes());
    sharedSecretBuilder.add(await dh2.extractBytes());
    sharedSecretBuilder.add(await dh3.extractBytes());
    sharedSecretBuilder.add(await dh4.extractBytes());
    final sharedSecret = sharedSecretBuilder.takeBytes();

    final initiatorIdentity = _decodePublicKey(
      initiatorHello.identityPublicKeyBase64,
    );
    final responderIdentity = _decodePublicKey(
      responderHello.identityPublicKeyBase64,
    );
    final saltBuilder = BytesBuilder(copy: false);
    saltBuilder.add(initiatorIdentity.bytes);
    saltBuilder.add(responderIdentity.bytes);
    final salt = saltBuilder.takeBytes();

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final master = await hkdf.deriveKey(
      secretKey: SecretKey(sharedSecret),
      nonce: salt,
      info: utf8.encode(_kMasterInfo),
    );
    final sessionInfoBuilder = BytesBuilder(copy: false);
    sessionInfoBuilder.add(utf8.encode(_kSessionInfo));
    sessionInfoBuilder.addByte(0x00);
    sessionInfoBuilder.add(finalHash);
    final sessionKey = await hkdf.deriveKey(
      secretKey: master,
      // RFC 5869: salt ausente = HashLen ceros. Explícito para no depender de
      // la implementación del paquete.
      nonce: Uint8List(32),
      info: sessionInfoBuilder.takeBytes(),
    );

    final material = P2PSessionKeyMaterial(
      keyBytes: Uint8List.fromList(await sessionKey.extractBytes()),
      transcriptHash: finalHash,
      initiatorSessionId: initiatorHello.sessionId,
      responderSessionId: responderHello.sessionId,
      firstContact: decision.firstContact,
    );
    _sessionKey = material;
    return material;
  }

  /// Libera referencias al efímero. Dart no garantiza zeroización de memoria;
  /// esto reduce la ventana de exposición, no la elimina.
  void destroy() {
    _ephemeralKeyPair = null;
    _destroyed = true;
  }

  void _ensureUsable() {
    if (_destroyed) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.destroyed,
        detail: 'handshake session was destroyed',
      );
    }
  }

  static SimplePublicKey _decodePublicKey(String value) {
    final bytes = base64Decode(value.trim());
    if (bytes.length != kIdentityPublicKeyLength) {
      throw const P2PHandshakeException(
        P2PHandshakeFailure.remoteHelloRejected,
        detail: 'public key is not 32 raw bytes',
      );
    }
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

const String _kMasterInfo = 'zone-xtdhs-v1';
const String _kSessionInfo = 'zone-session';
