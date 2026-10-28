/// Z-004 / PHASE E/G — Cableado REAL del handshake `ZONE-P2P-AKE-1` al
/// transporte P2P (`NearbyService`). Coordinador orquestador puro con
/// transporte inyectado: 100% testeable en VM sin el plugin nativo.
///
/// ESTADO: DISEÑADO + IMPLEMENTADO (integración con transporte simulado
/// PROBADA en `test/p2p_ake_coordinator_test.dart`); la demo física
/// H-01…H-15 sigue NOT RUN hasta dos dispositivos reales.
///
/// Flujo sobre una conexión Nearby ya establecida:
///
/// ```text
/// iniciador (autostart al conectar):  onConnected → ake_hello (sin prior)
/// responder (al recibir 1er hello):   onPeerHello → ake_hello (prior=H(hello_I))
/// iniciador (al recibir el 2o hello): onPeerHello(prior) → complete()
/// ambos:                              material de sesión SETTLED (por-conexión)
/// ```
///
/// Política de CONFLICTO (hellos simultáneos — ambos lados se consideraron
/// iniciador y enviaron el suyo): al recibir un hello SIN prior cuando la
/// pista iniciador ya existe, se crea una pista RESPONSER (fork) con
/// sessionId/nonce/efímeros FRESCOS; se responde `ake_hello` con
/// `prior=H(hello_peer)`. Cada lado termina con DOS candidatos de transcript;
/// la selección determinista es el `min` lexicográfico del hash final de
/// transcript ⇒ ambos lados convergen a la MISMA clave y al MISMO rol.
///
/// Reglas fail-closed (todas verificadas por tests):
/// - Un endpoint SIN AKE completado NO tiene canal protegido ([channel]
///   devuelve `null`) — una conexión inválida NO intercambia mensajes
///   protegidos.
/// - Un rechazo del policy nunca deriva ni settle material.
/// - El material NO se persiste: es por-conexión y muere con
///   [onDisconnected]. Nunca se toca el slot `sk_<zone>` legacy (Z-212; no
///   rompe la flota ni la semántica de efímeros).
/// - `deviceStatus`/`revokedAt` NUNCA viajan en el frame; se rellenan con la
///   confianza local del receptor ([localTrust]). Gap documentado: la
///   revocación server-side sigue BLOCKED (backend sin staging).
///
/// Sin secretos en logs: este módulo NO registra en log nada; el host
/// registra solo longitudes/hashes de transcript públicos.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../identity/keys.dart';
import 'p2p_auth_policy.dart';
import 'p2p_handshake_session.dart';
import 'p2p_wiring.dart';

/// Identidad local usada para firmar hellos (fundación de identidad).
class P2pAkeIdentityMaterial {
  const P2pAkeIdentityMaterial({
    required this.zoneId,
    required this.accountId,
    required this.deviceId,
    required this.identityKeyPair,
    required this.encryptionKeyPair,
    this.encryptionKeyVersion = 1,
  });

  /// ZONE-ID canónico `ZONE-XXXXXXXX` (validado fail-closed antes de firmar).
  final String zoneId;

  /// UUID canónico de cuenta (fundación).
  final String accountId;

  /// UUID canónico del dispositivo (fundación).
  final String deviceId;

  /// Par Ed25519 de firma de dispositivo (D1). Solo firma; no viaja.
  final SimpleKeyPair identityKeyPair;

  /// Par X25519 de cifrado de dispositivo (D2). ECDH only; no firma.
  final SimpleKeyPair encryptionKeyPair;

  final int encryptionKeyVersion;
}

/// Confianza LOCAL sobre el estado del dispositivo del peer. La revocación
/// real es server-side (BLOCKED); el default es `active` (gap documentado).
typedef LocalDeviceTrust = DeviceStatus Function(String peerDeviceId);

/// Transporte: envía `frame` al endpoint; `true` solo si la radio lo aceptó.
typedef P2pAkeFrameSender = Future<bool> Function(
  String endpointId,
  Map<String, dynamic> frame,
);

/// WI-6: consumir cupo de radio por frame (enviado o respondido). `false` ⇒
/// descartar (protección de radio; el despachador ya tasa los RECEBIDOS).
typedef P2pAkeQuotaGate = bool Function(String endpointId);

/// Notificación de material de sesión SETTLED. El receptor NO debe
/// persistir: el material es por-conexión.
typedef P2pAkeKeyMaterialListener = void Function(
  String endpointId,
  P2PSessionKeyMaterial material,
);

/// Resultado de procesar un `ake_hello` recibido (evidencia pública, no
/// material).
class P2pAkeHelloOutcome {
  const P2pAkeHelloOutcome._({
    required this.accepted,
    this.rejection,
    this.settled = false,
    this.replySent = false,
  });

  final bool accepted;

  /// Presente cuando [accepted] es `false` (decisión tipada del policy).
  final P2PAuthDecision? rejection;

  /// `true` si el endpoint ya tiene material de sesión fijado.
  final bool settled;

  /// `true` si se envió un frame de respuesta (hello responder).
  final bool replySent;

  @override
  String toString() => 'P2pAkeHelloOutcome(accepted=$accepted, '
      'settled=$settled, replySent=$replySent, rejection=$rejection)';
}

/// Codec de frames `ake_hello` sobre `NearbyService` (JSON, UTF-8).
///
/// Las cadenas firmadas viajan SIN normalizar (la verificación del policy
/// reconstruye el transcript canónico; cualquier trims/normalización aquí
/// rompería la firma — por eso no se toca).
abstract final class P2pAkeHelloCodec {
  static const int kWireVersion = 1;

  static Map<String, dynamic> encode(
    P2PAuthHello hello, {
    List<int>? priorTranscriptHash,
  }) =>
      <String, dynamic>{
        'v': kWireVersion,
        'version': hello.version,
        'zone_id': hello.zoneId,
        'account_id': hello.accountId,
        'device_id': hello.deviceId,
        'identity_alg': hello.identityKeyAlgorithm,
        'identity_pk': hello.identityPublicKeyBase64,
        'encryption_alg': hello.encryptionKeyAlgorithm,
        'encryption_pk': hello.encryptionPublicKeyBase64,
        'encryption_version': hello.encryptionKeyVersion,
        'epk': hello.ephemeralPublicKeyBase64,
        'nonce': hello.nonceBase64,
        'session_id': hello.sessionId,
        'issued_at': hello.issuedAtMs,
        'sig': hello.signatureBase64,
        if (priorTranscriptHash != null)
          'prior_transcript': base64Encode(priorTranscriptHash),
      };

  /// Reconstruye el hello desde el frame. `deviceStatus` viene de la
  /// confianza LOCAL del receptor (`peerStatus`) — nunca del cable.
  static P2PAuthHello? decode(
    Map<String, dynamic> frame, {
    DeviceStatus peerStatus = DeviceStatus.active,
  }) {
    try {
      final version = frame['version'];
      final zoneId = frame['zone_id'];
      final accountId = frame['account_id'];
      final deviceId = frame['device_id'];
      final identityAlg = frame['identity_alg'];
      final identityPk = frame['identity_pk'];
      final encryptionAlg = frame['encryption_alg'];
      final encryptionPk = frame['encryption_pk'];
      final encryptionVersion = frame['encryption_version'];
      final epk = frame['epk'];
      final nonce = frame['nonce'];
      final sessionId = frame['session_id'];
      final issuedAt = frame['issued_at'];
      final sig = frame['sig'];
      if (version is! String ||
          zoneId is! String ||
          accountId is! String ||
          deviceId is! String ||
          identityAlg is! String ||
          identityPk is! String ||
          encryptionAlg is! String ||
          encryptionPk is! String ||
          epk is! String ||
          nonce is! String ||
          sessionId is! String ||
          sig is! String) {
        return null;
      }
      if (encryptionVersion is! int || issuedAt is! int) return null;
      return P2PAuthHello(
        version: version,
        zoneId: zoneId,
        accountId: accountId,
        deviceId: deviceId,
        identityKeyAlgorithm: identityAlg,
        identityPublicKeyBase64: identityPk,
        encryptionKeyAlgorithm: encryptionAlg,
        encryptionPublicKeyBase64: encryptionPk,
        encryptionKeyVersion: encryptionVersion,
        ephemeralPublicKeyBase64: epk,
        nonceBase64: nonce,
        sessionId: sessionId,
        issuedAtMs: issuedAt,
        signatureBase64: sig,
        deviceStatus: peerStatus,
      );
    } on Object {
      return null;
    }
  }
}

/// Bytes mínimos de un frame de canal protegido: 8 (seq) + 1 (rol) + 16 (mac).
const int kP2pAkeChannelMinFrameLength = 8 + 1 + 16;

/// Canal protegido EFÍMERO sobre una sesión AKE completada.
///
/// - ChaCha20-Poly1305 (primitiva aprobada), clave = material de sesión.
/// - Nonce 12B = primeros 4B del transcript hash final ‖ u64be(seq) — el
///   dominio cambia con cada sesión (nunca reutilización).
/// - AAD = transcriptHash ‖ u64be(seq) ‖ 1B rol del emisor (`i`/`r`).
/// - RX anti-replay: `seq` peer estrictamente creciente (replay Y
///   reordenación hacia atrás se rechazan con error tipado).
class P2pAkeChannel {
  P2pAkeChannel._({
    required this.sessionKey,
    required this.transcriptHash,
    required this.amInitiator,
  });

  final Uint8List sessionKey;
  final Uint8List transcriptHash;

  /// Rol de ESTE lado en la sesión transcript-bound elegida.
  final bool amInitiator;

  SecretKey? _secretKey;
  int _txSeq = 0;
  int _rxSeq = 0;

  /// Cifra un payload de aplicación para esta conexión.
  Future<Uint8List> seal(List<int> plaintext, {List<int>? aad}) async {
    final seq = ++_txSeq;
    final senderTag = amInitiator ? _tagInitiator : _tagResponder;
    final aead = Chacha20.poly1305Aead();
    final secretBox = await aead.encrypt(
      plaintext,
      secretKey: _key,
      nonce: _nonceFor(seq),
      aad: _aadBytes(senderTag, seq, aad),
    );
    final out = BytesBuilder(copy: false)
      ..add(_encodeSeq(seq))
      ..addByte(senderTag)
      ..add(secretBox.cipherText)
      ..add(secretBox.mac.bytes);
    return out.toBytes();
  }

  /// Descifra un frame entrante. Falla cerrado: replay, reordenación
  /// descendente, rol del emisor incorrecto y MAC inválida.
  Future<Uint8List> open(Uint8List frame, {List<int>? aad}) async {
    if (frame.length < kP2pAkeChannelMinFrameLength) {
      throw const P2pAkeChannelError('frame_too_short');
    }
    final seq = _seqOf(frame);
    if (seq <= _rxSeq) {
      throw const P2pAkeChannelError('replayed_or_out_of_order');
    }
    final senderTag = frame[8];
    final expected = amInitiator ? _tagResponder : _tagInitiator;
    if (senderTag != expected) {
      throw const P2pAkeChannelError('invalid_sender_role');
    }
    final aead = Chacha20.poly1305Aead();
    final cipher = frame.sublist(9, frame.length - 16);
    final mac = Mac(frame.sublist(frame.length - 16));
    try {
      final plain = await aead.decrypt(
        SecretBox(cipher, nonce: _nonceFor(seq), mac: mac),
        secretKey: _key,
        aad: _aadBytes(senderTag, seq, aad),
      );
      _rxSeq = seq;
      return Uint8List.fromList(plain);
      // Fail-closed ante MAC/algoritmo/formato: nunca exponer parcialmente.
    } on Object {
      throw const P2pAkeChannelError('decrypt_failed');
    }
  }

  SecretKey get _key => _secretKey ??= SecretKey(sessionKey);

  static const int _tagInitiator = 0x69; // 'i'
  static const int _tagResponder = 0x72; // 'r'

  /// 12B: 4B dominio (transcript hash) ‖ 8B seq big-endian.
  Uint8List _nonceFor(int seq) {
    final out = Uint8List(12);
    out.setRange(0, 4, transcriptHash);
    out.setRange(4, 12, _encodeSeq(seq));
    return out;
  }

  Uint8List _aadBytes(int senderTag, int seq, List<int>? extra) {
    final parts = BytesBuilder()
      ..add(transcriptHash)
      ..add(_encodeSeq(seq))
      ..addByte(senderTag);
    if (extra != null) parts.add(extra);
    return parts.toBytes();
  }

  static Uint8List _encodeSeq(int seq) {
    final out = Uint8List(8);
    var v = seq;
    for (var i = 7; i >= 0; i--) {
      out[i] = v & 0xff;
      v >>= 8;
    }
    return out;
  }

  static int _seqOf(Uint8List frame) {
    var seq = 0;
    for (var i = 0; i < 8; i++) {
      seq = (seq << 8) | frame[i];
    }
    return seq;
  }
}

/// Error tipado del canal protegido (sin material sensible).
class P2pAkeChannelError implements Exception {
  const P2pAkeChannelError(this.reason);
  final String reason;

  @override
  String toString() => 'P2pAkeChannelError($reason)';
}

class _Candidate {
  _Candidate(this.transcriptHash, this.material, this.amInitiator);
  final Uint8List transcriptHash;
  final P2PSessionKeyMaterial material;
  final bool amInitiator;
}

class _EndpointAke {
  P2PHandshakeSession? initiator;
  P2PHandshakeSession? responder;
  final List<_Candidate> candidates = [];
  P2PSessionKeyMaterial? settled;
  bool? roleOfSettled;
  Timer? settlementTimer;
  bool listenerNotified = false;

  /// Pista iniciador viva SIN respuesta del peer aún (conflicto pendiente).
  bool get initTrackPending =>
      initiator != null && initiator!.remoteHello == null;
}

/// Orquestador de handshakes por endpoint. UNA instancia por app: posee el
/// replay cache compartido (anti-replay de sessionIds a través de pistas y
/// reconexiones en vida del proceso).
class P2pAkeCoordinator {
  P2pAkeCoordinator({
    required this.identityLoader,
    required this.frameSender,
    required this.quotaGate,
    required this.keyMaterialListener,
    this.localTrust,
    this.settlementWait = const Duration(seconds: 3),
  });

  /// Carga diferida de identidad (null si el bootstrap aún no corrió ⇒
  /// fail-closed, no se firma nada).
  final Future<P2pAkeIdentityMaterial?> Function() identityLoader;

  final P2pAkeFrameSender frameSender;
  final P2pAkeQuotaGate quotaGate;
  final P2pAkeKeyMaterialListener keyMaterialListener;
  final LocalDeviceTrust? localTrust;

  /// Ventana de espera del 2do candidato en conflicto simultáneo.
  final Duration settlementWait;

  final Map<String, _EndpointAke> _endpoints = {};
  final P2PSessionReplayCache _replayCache = P2PSessionReplayCache();

  /// ¿El endpoint completó un AKE con material fijado?
  bool get hasCompletedAke {
    return _endpoints.values.any((e) => e.settled != null);
  }

  bool hasCompletedAkeFor(String endpointId) =>
      _endpoints[endpointId]?.settled != null;

  /// Canal protegido del endpoint (o `null` si el AKE no completó).
  P2pAkeChannel? channel(String endpointId) {
    final state = _endpoints[endpointId];
    final settled = state?.settled;
    if (state == null || settled == null) return null;
    // El candidato ELEGIDO aporta el rol; si el settle ocurrió con material
    // sin rol conocido (no debería por constructor), no canaliza.
    final role = state.roleOfSettled;
    if (role == null) return null;
    return P2pAkeChannel._(
      sessionKey: settled.keyBytes,
      transcriptHash: settled.transcriptHash,
      amInitiator: role,
    );
  }

  /// Inicia el AKE como iniciador ante una conexión establecida. Idempotente
  /// por endpoint: el segundo llamado no reenvía hello ni re-consume radio.
  Future<bool> onConnected(String endpointId) async {
    final state = _endpoints.putIfAbsent(endpointId, _EndpointAke.new);
    if (state.settled != null || state.initiator != null) return true;
    if (!quotaGate(endpointId)) return false;
    final identity = await identityLoader();
    if (identity == null || !_canonicalIdentity(identity)) return false;

    final session = P2PHandshakeSession(
      role: P2PHandshakeRole.initiator,
      zoneId: identity.zoneId,
      accountId: identity.accountId,
      deviceId: identity.deviceId,
      identityKeyPair: identity.identityKeyPair,
      encryptionKeyPair: identity.encryptionKeyPair,
      encryptionKeyVersion: identity.encryptionKeyVersion,
      endpointId: endpointId,
      replayCache: _replayCache,
    );
    final hello = await session.createHello();
    state.initiator = session;
    final sent = await frameSender(endpointId, <String, dynamic>{
      'type': kP2pAkeHelloType,
      'data': P2pAkeHelloCodec.encode(hello),
    });
    if (!sent) {
      // La radio no tomó el frame: la pista queda huérfana (se destruirá al
      // desconectar). Fail-closed: no derivar nada.
      state.initiator = null;
      session.destroy();
      return false;
    }
    return true;
  }

  /// Procesa un `ake_hello` recibido. El frame DEBE venir ya saneado en forma
  /// por el despachador (WI-2/WI-6); aquí se ejecuta la verificación
  /// criptográfica completa y la orquestación de pistas.
  Future<P2pAkeHelloOutcome> onPeerHello(
    String endpointId,
    Map<String, dynamic> frame, {
    DateTime? nowOverride,
  }) async {
    final state = _endpoints.putIfAbsent(endpointId, _EndpointAke.new);
    if (state.settled != null) {
      return const P2pAkeHelloOutcome._(accepted: false, settled: true);
    }
    final now = nowOverride ?? DateTime.now().toUtc();
    final peerStatus = localTrust?.call('') ?? DeviceStatus.active;
    final hello = P2pAkeHelloCodec.decode(frame, peerStatus: peerStatus);
    if (hello == null) return const P2pAkeHelloOutcome._(accepted: false);
    final identity = await identityLoader();
    if (identity == null) return const P2pAkeHelloOutcome._(accepted: false);

    final priorBytes = _priorHashOf(frame);
    final hasPrior = priorBytes != null;

    // ── Caso 1: pista iniciador viva y hello del responder (con prior) ──
    final init = state.initiator;
    if (init != null && hasPrior) {
      final decision = await init.acceptPeerHello(
        hello,
        priorTranscriptHash: priorBytes,
        now: now,
      );
      if (!decision.accepted) {
        // Pista iniciador sigue utilizable para un hello correcto posterior
        // (el policy NO registra rechazos en el replay cache).
        return P2pAkeHelloOutcome._(accepted: false, rejection: decision);
      }
      final material = await _complete(init);
      if (material != null) {
        state.candidates.add(
          _Candidate(material.transcriptHash, material, init.role == P2PHandshakeRole.initiator),
        );
        await _maybeSettle(endpointId, state);
      }
      return P2pAkeHelloOutcome._(
        accepted: true,
        settled: state.settled != null,
      );
    }

    // ── Caso 2: pista iniciador viva + hello SIN prior (conflicto) → fork ──
    if (init != null && !hasPrior && state.responder == null) {
      if (!quotaGate(endpointId)) return const P2pAkeHelloOutcome._(accepted: false);
      final outcome = await _runResponder(
        endpointId,
        state,
        hello,
        identity,
        now: now,
      );
      if (outcome.accepted && state.settled == null) {
        // Esperamos el hello priored del peer para el 2do candidato.
        state.settlementTimer ??= Timer(
          settlementWait,
          () => unawaited(expirePendingSettlement(endpointId)),
        );
      }
      return outcome;
    }

    // ── Caso 3: sin pista iniciador (somos el passivo/responder primario) ──
    if (init == null && !hasPrior && state.responder == null) {
      final outcome = await _runResponder(
        endpointId,
        state,
        hello,
        identity,
        now: now,
      );
      return outcome;
    }

    // Duplicado/inesperado (responder ya existe, o prior sin pista): ignorar.
    return const P2pAkeHelloOutcome._(accepted: false);
  }

  /// Fuerza la evaluación del settlement pendiente (timeout interno; también
  /// utilizable en pruebas deterministas). Sin candidatos ⇒ no-op.
  Future<void> expirePendingSettlement(String endpointId) async {
    final state = _endpoints[endpointId];
    if (state == null) return;
    state.settlementTimer?.cancel();
    state.settlementTimer = null;
    if (state.settled != null) return;
    if (state.candidates.isEmpty) return;
    _settle(endpointId, state);
  }

  /// Cierre determinista: destruye pistas y estado (el AKE muere con la
  /// conexión; la ventana WI-6 de radio sobrevive por diseño del wiring).
  void onDisconnected(String endpointId) {
    final state = _endpoints.remove(endpointId);
    if (state == null) return;
    state.settlementTimer?.cancel();
    state.initiator?.destroy();
    state.responder?.destroy();
  }

  // ──────────────────────────────────────────────────────────
  // internals
  // ──────────────────────────────────────────────────────────

  Future<P2pAkeHelloOutcome> _runResponder(
    String endpointId,
    _EndpointAke state,
    P2PAuthHello peerHello,
    P2pAkeIdentityMaterial identity, {
    required DateTime now,
  }) async {
    final session = P2PHandshakeSession(
      role: P2PHandshakeRole.responder,
      zoneId: identity.zoneId,
      accountId: identity.accountId,
      deviceId: identity.deviceId,
      identityKeyPair: identity.identityKeyPair,
      encryptionKeyPair: identity.encryptionKeyPair,
      encryptionKeyVersion: identity.encryptionKeyVersion,
      endpointId: endpointId,
      replayCache: _replayCache,
    );
    final decision = await session.acceptPeerHello(peerHello, now: now);
    if (!decision.accepted) {
      session.destroy();
      return P2pAkeHelloOutcome._(accepted: false, rejection: decision);
    }
    final initiatorHash = await P2PAuthPolicy.transcriptHash(hello: peerHello);
    final replyHello = await session.createHello(
      priorTranscriptHash: initiatorHash,
    );
    final sent = await frameSender(endpointId, <String, dynamic>{
      'type': kP2pAkeHelloType,
      'data': P2pAkeHelloCodec.encode(
        replyHello,
        priorTranscriptHash: initiatorHash,
      ),
    });
    if (!sent) {
      session.destroy();
      return const P2pAkeHelloOutcome._(accepted: false);
    }
    state.responder = session;
    final material = await _complete(session);
    if (material != null) {
      state.candidates.add(
        _Candidate(material.transcriptHash, material, false),
      );
      // Caso 2 (fork en vivo): NO settle todavía; hay pista iniciador
      // esperando el 2do candidato. Caso 3 (responder primario): settle YA.
      if (!state.initTrackPending) {
        _settle(endpointId, state);
      }
    }
    return P2pAkeHelloOutcome._(
      accepted: true,
      settled: state.settled != null,
      replySent: true,
    );
  }

  Future<P2PSessionKeyMaterial?> _complete(P2PHandshakeSession session) async {
    try {
      return await session.complete();
    } on P2PHandshakeException {
      return null;
    }
  }

  void _settle(String endpointId, _EndpointAke state) {
    if (state.settled != null || state.candidates.isEmpty) return;
    var best = state.candidates.first;
    for (final c in state.candidates.skip(1)) {
      if (_lexLess(c.transcriptHash, best.transcriptHash)) best = c;
    }
    state.settled = best.material;
    state.roleOfSettled = best.amInitiator;
    state.settlementTimer?.cancel();
    state.settlementTimer = null;
    if (!state.listenerNotified) {
      state.listenerNotified = true;
      keyMaterialListener(endpointId, best.material);
    }
  }

  Future<void> _maybeSettle(String endpointId, _EndpointAke state) async {
    if (state.settled != null || state.candidates.isEmpty) return;
    // Pista iniciador aún esperando respuesta del peer ⇒ esperar candidato.
    if (state.initTrackPending) {
      state.settlementTimer ??= Timer(
        settlementWait,
        () => unawaited(expirePendingSettlement(endpointId)),
      );
      return;
    }
    _settle(endpointId, state);
  }

  static bool _lexLess(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] < b[i];
    }
    return a.length < b.length;
  }

  static Uint8List? _priorHashOf(Map<String, dynamic> frame) {
    final prior = frame['prior_transcript'];
    if (prior is String && prior.isNotEmpty) {
      try {
        final bytes = base64Decode(prior);
        if (bytes.length != 32) return null;
        return Uint8List.fromList(bytes);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static bool _canonicalIdentity(P2pAkeIdentityMaterial identity) {
    final zoneOk = RegExp(r'^ZONE-[A-Z0-9]{8}$').hasMatch(identity.zoneId);
    final uuidOk = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
      r'[0-9a-f]{12}$',
    ).hasMatch(identity.accountId);
    return zoneOk && uuidOk;
  }
}
