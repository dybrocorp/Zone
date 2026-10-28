/// Z-004 / PHASE E §7.8 — Cableado P2P: **gate del despachador** (WI-2) y
/// **rate-limit local** (WI-6).
///
/// Estado: DISEÑADO + IMPLEMENTADO (unidades PROBADAS LOCALMENTE).
/// El handshake AKE COMPLETO (WI-1/WI-3/WI-4) sigue SIN CABLEAR a nivel
/// transporte: la demostración física (H-01…H-15) permanece pendiente y el
/// estado honesto de esta fase es *gate prep* — `ake_hello`/`ake_cert` se
/// despachan, se clasifican y se registran, PERO no deriva ni guarda clave
/// de sesión hasta completar WI-1/WI-3 con dispositivos físicos.
///
/// Qué resuelve cada control (fuente: `docs/audit/PHASE_E_P2P_AUTH_DESIGN.md'
/// §7.8.2 matriz de trazabilidad, filas WI-2 y WI-6):
///
/// - **WI-2** — `profile_exchange` recibido ANTES de un AKE completado en
///   su endpoint NO alimenta la derivación de llaves: el despachador en
///   `nearby_service.dart` consulta [P2pAkeWiring.gateProfileExchange]:
///   sin AKE completado ⇒ decisión `unverifiedFallback` (se guarda la
///   marca 'unverified' y se OMITE la derivación/guardado de llave de
///   sesión; identidad → sin bloqueo de UI pero con etiqueta honesta).
///
/// - **WI-6** — intentos repetidos de handshake del mismo peer ⇒
///   rate-limit local (protección de radio, NO criptográfica):
///   contador LRU con TTL por endpoint (patrón [MeshDedup] de
///   `mesh_policy.dart`, con tope por ventana deslizante humoral).
///   Fail-closed: agotado el cupo ⇒ `attemptDenied` hasta que la ventana
///   TTL libere cupo.
///
/// Sin secretos: este módulo no toca material privado ni deriva nada.
library;

import 'dart:typed_data';

/// Resultado del gate WI-2 para `profile_exchange`.
enum P2pProfileExchangeGate {
  /// AKE completado en el endpoint: tratamiento autenticado
  /// (derivación/guardado permitido por el despachador).
  authenticatedPath,

  /// SIN AKE completado: marca 'unverified' y OMITIR derivación de llave
  /// (datos de perfil visibles, identidad NO verificada — WI-2 honesto).
  unverifiedFallback,
}

/// Resultado del rate-limit WI-6 para `ake_hello`/`ake_cert`.
enum P2pAkeRateDecision {
  /// Cupo disponible: se permite procesar el frame.
  attemptAllowed,

  /// Cupo agotado en la ventana para este endpoint: descartar el frame
  /// (fail-closed hasta que la ventana TTL libere).
  attemptDenied,
}

/// Tipos de payload AKE canónicos (si cambian, invalidan handshakes viejos).
const String kP2pAkeHelloType = 'ake_hello';
const String kP2pAkeCertType = 'ake_cert';

/// Campos mínimos de un frame AKE de este wire (forma gruesa; la CRÍPTICA
/// completa la valida P2PAuthPolicy/P2PHandshakeSession).
const Set<String> _kAkeHelloRequiredFields = {
  'v',
  'session_id',
  'nonce',
  'identity_pk',
  'encryption_pk',
  'fp',
  'sig',
};
const Set<String> _kAkeCertRequiredFields = {
  'v',
  'session_id',
  'device_cert',
  'sig',
};

/// Estado AKE por endpoint (transporte: los endpoint IDs son efímeros y este
/// estado muere con la conexión — NUNCA clave de identidad).
class P2pAkeEndpointState {
  P2pAkeEndpointState._();

  bool akeCompleted = false;
  bool helloSeen = false;
  bool certSeen = false;
}

/// Cable WI-2 + WI-6. Componente de despachador (puro; sin secretos).
class P2pAkeWiring {
  P2pAkeWiring({
    this.maxHandshakeAttemptsPerWindow = 5,
    this.window = const Duration(minutes: 10),
    this.maxTrackedEndpoints = 64,
  });

  /// Cupo WI-6: intentos de handshake por endpoint por ventana.
  final int maxHandshakeAttemptsPerWindow;

  /// Ventana TTL deslizante de intentos (alineada con la caché anti-replay
  /// de la fundación: 10 min).
  final Duration window;

  /// Tope LRU de endpoints rastreados (eviction de la entrada más antigua).
  final int maxTrackedEndpoints;

  final Map<String, P2pAkeEndpointState> _endpoints = {};
  final Map<String, List<DateTime>> _attemptWindow = {};

  // ───────────────────────────────────────────────────────────
  // WI-2 — gate del despachador de payloads
  // ───────────────────────────────────────────────────────────

  /// Marca el frame AKE recibido (llamar DESPUÉS de pasar el rate-limit y
  /// la forma gruesa). Los AKE están en progreso, no completados.
  void noteAkeFrameReceived({
    required String endpointId,
    required bool isHello,
  }) {
    final state = _stateFor(endpointId);
    if (isHello) {
      state.helloSeen = true;
    } else {
      state.certSeen = true;
    }
  }

  /// Marca el AKE del endpoint COMO COMPLETADO (solo cuando la sesión AKE
  /// haya terminado con éxito con anclas verificadas — crude WI-1/WI-3 se
  /// cableará cuando la flota requiera este camino, no antes).
  void markAkeCompleted(String endpointId) {
    _stateFor(endpointId).akeCompleted = true;
  }

  /// ¿El endpoint tiene AKE completado?
  bool hasCompletedAke(String endpointId) =>
      _endpoints[endpointId]?.akeCompleted ?? false;

  /// WI-2 — decisión del gate para un `profile_exchange` entrante.
  P2pProfileExchangeGate gateProfileExchange(String endpointId) =>
      hasCompletedAke(endpointId)
          ? P2pProfileExchangeGate.authenticatedPath
          : P2pProfileExchangeGate.unverifiedFallback;

  // ───────────────────────────────────────────────────────────
  // WI-6 — rate-limit local por endpoint (LRU + TTL)
  // ───────────────────────────────────────────────────────────

  /// ¿Se puede intentar handshake para este endpoint AHORA?
  /// Fail-closed: sin cupo ⇒ [P2pAkeRateDecision.attemptDenied].
  P2pAkeRateDecision checkHandshakeQuota(
    String endpointId, {
    DateTime? now,
  }) {
    final stamp = now ?? DateTime.now().toUtc();
    final list = _attemptWindow[endpointId];
    if (list == null) return P2pAkeRateDecision.attemptAllowed;
    list.removeWhere((t) => stamp.difference(t) >= window);
    if (list.length >= maxHandshakeAttemptsPerWindow) {
      return P2pAkeRateDecision.attemptDenied;
    }
    return P2pAkeRateDecision.attemptAllowed;
  }

  /// Registra un intento (llamar SIEMPRE tras [checkHandshakeQuota]
  /// permitido y por CADA frame procesado — éxito o fallo; el límite es
  /// de VOLUMEN, no de éxito).
  void recordHandshakeAttempt(String endpointId, {DateTime? now}) {
    final stamp = now ?? DateTime.now().toUtc();
    _attemptWindow.putIfAbsent(endpointId, () => <DateTime>[]).add(stamp);
    _evictOldestIfNeeded();
  }

  /// Combinación cómoda para el despachador: quota + (si hay) intento.
  P2pAkeRateDecision consumeHandshakeQuota(
    String endpointId, {
    DateTime? now,
  }) {
    if (checkHandshakeQuota(endpointId, now: now) ==
        P2pAkeRateDecision.attemptDenied) {
      return P2pAkeRateDecision.attemptDenied;
    }
    recordHandshakeAttempt(endpointId, now: now);
    return P2pAkeRateDecision.attemptAllowed;
  }

  // ───────────────────────────────────────────────────────────
  // Reconexión de endpoints — estado de transporte muere con la conexión
  // ───────────────────────────────────────────────────────────

  /// Un `endpointId` es efímero: al desconectar se olvida TODO su estado
  /// de identidad/AKE — la reconexión (nuevo endpoint) re-negocia con
  /// efímeros frescos. Los datos de USO de radio de WI-6 sobreviven
  /// (protección anclada al peer), pero jamás datos de identidad.
  void noteDisconnected(String endpointId) {
    _endpoints.remove(endpointId);
  }

  /// Solo para tests / reset total del servicio.
  void resetForTest() {
    _endpoints.clear();
    _attemptWindow.clear();
  }

  // ───────────────────────────────────────────────────────────
  // Forma gruesa de frames AKE (fail-closed; la cripto es la de la fundación)
  // ───────────────────────────────────────────────────────────

  /// Valida la forma mínima de un frame AKE (`ake_hello`/`ake_cert`).
  /// Devuelve el mapa de data SANEADO (solo claves conocidas) o `null`.
  /// No valida firma/hash — eso es responsabilidad de AKE (P2PHandshakeSession
  /// / P2PAuthPolicy) cuando el WI-1/WI-3 se cablee.
  Map<String, dynamic>? validateAkeFrame({
    required String type,
    required Map<String, dynamic> data,
  }) {
    final required = switch (type) {
      kP2pAkeHelloType => _kAkeHelloRequiredFields,
      kP2pAkeCertType => _kAkeCertRequiredFields,
      _ => null,
    };
    if (required == null) return null;
    for (final field in required) {
      final value = data[field];
      if (value == null || (value is String && value.trim().isEmpty)) {
        return null;
      }
    }
    if (data['v'] is! int || (data['v'] as int) < 1) {
      return null;
    }
    // Copia fail-closed: SOLO claves conocidas del wire (sin inyección de
    // campos extraños hacia el handshake).
    final clean = <String, dynamic>{};
    for (final field in {
      ..._kAkeHelloRequiredFields,
      ..._kAkeCertRequiredFields,
    }) {
      final v = data[field];
      if (v is String || v is Uint8List) clean[field] = v;
    }
    return clean;
  }

  // ───────────────────────────────────────────────────────────
  // internals
  // ───────────────────────────────────────────────────────────

  P2pAkeEndpointState _stateFor(String endpointId) =>
      _endpoints.putIfAbsent(endpointId, () => P2pAkeEndpointState._());

  void _evictOldestIfNeeded() {
    if (_attemptWindow.length <= maxTrackedEndpoints) return;
    // Eviction LRU: descarta el endpoint con MENOR actividad reciente
    // (su intento más reciente es el más antiguo).
    String? oldestKey;
    DateTime? oldestNewest;
    _attemptWindow.forEach((key, list) {
      final newest = list.isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : list.last;
      if (oldestNewest == null || newest.isBefore(oldestNewest!)) {
        oldestNewest = newest;
        oldestKey = key;
      }
    });
    if (oldestKey != null) _attemptWindow.remove(oldestKey);
  }
}
