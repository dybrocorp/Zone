import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/discovery_config.dart';
import 'connectivity_service.dart';
import 'internet_discovery_provider.dart';
import 'location_engine.dart';

/// Orquestador del descubrimiento geográfico (GPS + Red).
///
/// Diseño: docs/redesign/ZONE_FREEMIUM_ARCHITECTURE.md §2.3.
///
/// Máquina de estados EXACTA del diseño:
/// `idle · acquiringFix · live · hidden · offline · permissionBlocked ·
/// serverError · requiresAuth`.
///
/// Reglas:
///  - Este coordinador SOLO hace GPS+Red. El modo Bluetooth del radar es una
///    vía independiente de la UI (NUNCA cae automáticamente BT→GPS ni
///    GPS→BT).
///  - Aplica la visibilidad del usuario ANTES de cualquier `publishPresence`
///    (si el usuario se ocultó, no se publica nada; el servidor además
///    re-verifica consent/visibilidad en cada RPC).
///  - "Ocultarse" envía `expire_my_presence` (borrado en el servidor). Sin
///    sesión o sin red: silencioso — el TTL de 30 min es la red de seguridad
///    (privacy > error ruidoso).
///  - Si dejan de llegar pings, la presencia caduca sola server-side (TTL
///    30 min): no hay "última posición eterna".
///  - Cancelación limpia en [dispose]/[stopForLogout].

/// Modo del selector del radar (UI):
/// GPS = descubrimiento gratuito por GPS+Red (este coordinador);
/// Bluetooth = radar Nearby (Premium, vía `NearbyService` existente).
enum DiscoveryMode { gps, bluetooth }

/// Estado visible del descubrimiento geo (banner + lista).
enum GeoStatus {
  idle,
  acquiringFix,
  live,
  hidden,
  offline,
  permissionBlocked,
  serverError,
  requiresAuth,
}

/// Snapshot de UI inmutable del coordinador.
@immutable
class GeoUiState {
  const GeoUiState({
    required this.status,
    this.message,
    this.peers = const [],
    this.radiusMeters = DiscoveryConfig.defaultRadiusMeters,
    this.visibilityIntended = false,
    this.lastErrorText,
  });

  final GeoStatus status;

  /// Mensaje de usuario del estado/banners (sin coordenadas).
  final String? message;

  /// Peers de la última búsqueda (SOLO datos no sensibles: sin coordenadas).
  final List<NearbyGeoUser> peers;
  final double radiusMeters;
  final bool visibilityIntended;

  /// Último error técnico (string sin coordenadas; para diagnóstico/reintento).
  final String? lastErrorText;

  GeoUiState copyWith({
    GeoStatus? status,
    Object? message = _absent,
    List<NearbyGeoUser>? peers,
    double? radiusMeters,
    bool? visibilityIntended,
    Object? lastErrorText = _absent,
  }) {
    return GeoUiState(
      status: status ?? this.status,
      message: message == _absent ? this.message : message as String?,
      peers: peers ?? this.peers,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      visibilityIntended: visibilityIntended ?? this.visibilityIntended,
      lastErrorText: lastErrorText == _absent
          ? this.lastErrorText
          : lastErrorText as String?,
    );
  }

  static const Object _absent = Object();
}

/// Contrato inyectable de conexión (prod: ConnectivityService; tests: fake).
typedef OnlineChecker = bool Function();

typedef GeoClockFn = DateTime Function();

class DiscoveryCoordinator {
  DiscoveryCoordinator({
    LocationEngine? engine,
    InternetDiscoveryProvider? provider,
    OnlineChecker? online,
    GeoClockFn? clock,
    Duration? tickInterval,
  })  : _engine = engine ?? LocationEngine(),
        _provider = provider ?? InternetDiscoveryProvider(),
        _online = online ?? (() => ConnectivityService().hasRealInternet),
        _clock = clock ?? DateTime.now,
        tickInterval = tickInterval ?? const Duration(seconds: 10) {
    _applyPrefsInit();
  }

  final LocationEngine _engine;
  final InternetDiscoveryProvider _provider;
  final OnlineChecker _online;
  final GeoClockFn _clock;

  /// Tick del reloj interno (re-evaluación del bucle).
  final Duration tickInterval;

  /// Cadencia de ping de presencia (server deduplica < 15 s; margen propio).
  static const Duration presencePingInterval = Duration(seconds: 30);

  /// Cadencia de búsqueda de peers.
  static const Duration searchInterval = Duration(seconds: 20);

  final ValueNotifier<GeoUiState> ui =
      ValueNotifier(const GeoUiState(status: GeoStatus.idle));

  Timer? _tickTimer;
  bool _ticking = false;
  bool _disposed = false;

  bool _lastPingOk = false;
  DateTime? _lastPingAt;
  DateTime? _lastSearchAt;

  /// ¿El usuario pidió estar visible? (intención; el servidor es autoridad).
  bool get isIntendedVisible => ui.value.visibilityIntended;

  /// Estado del último fix válido (solo lectura para UI/depuración).
  GeoFix? get lastValidFix => _engine.lastValidFix;

  void _applyPrefsInit() {
    // Estado inicial neutral; la carga real de preferencias ocurre al
    // activarse (setVisibility) vía `loadPreferences` del servidor.
  }

  // ─── acciones del usuario ───────────────────────────────────────────

  /// Enciende el descubrimiento (visibilidad + consentimiento GPS).
  ///
  /// Primero persiste la preferencia server-side (canal único seguro); solo
  /// si el servidor la acepta arranca el bucle. Sin sesión → `requiresAuth`.
  /// Con `visible: true`, es competencia del servidor decidir el radio final
  /// (clamp z214); el cliente sincroniza su UI con `loadPreferences`.
  Future<void> setVisibility({required bool visible}) async {
    _checkNotDisposed();
    if (!visible) {
      await hideNow();
      return;
    }
    try {
      await _provider.savePreferences(
        discoveryEnabled: true,
        locationSharingEnabled: true,
        radiusMeters: ui.value.radiusMeters,
      );
    } on DiscoveryAuthException {
      _setState(status: GeoStatus.requiresAuth);
      return;
    } on Exception catch (e) {
      _setState(status: GeoStatus.serverError, lastErrorText: e.toString());
      return;
    }
    // Sincroniza el radio de UI con lo que el servidor realmente tiene.
    try {
      final prefs = await _provider.loadPreferences();
      _setState(
        radiusMeters: DiscoveryConfig.nearestAllowedRadius(prefs.radiusMeters),
      );
    } on Exception {
      // No crítico: usar el radio elegido localmente; el server re-clampa.
    }
    _lastPingAt = null;
    _lastSearchAt = null;
    _lastPingOk = false;
    _setState(
      status: GeoStatus.acquiringFix,
      visibilityIntended: true,
      lastErrorText: null,
      message: 'Buscando señal de ubicación…',
    );
    _ensureTickLoop();
  }

  /// Cambia el radio (chips {250,500,1000,2000}); re-publica al vuelo.
  Future<void> setRadius(double meters) async {
    _checkNotDisposed();
    final radius = DiscoveryConfig.nearestAllowedRadius(meters);
    _setState(radiusMeters: radius);
    if (!ui.value.visibilityIntended) return;
    _lastPingAt = null;
    try {
      await _provider.savePreferences(
        discoveryEnabled: true,
        locationSharingEnabled: true,
        radiusMeters: radius,
      );
    } on DiscoveryAuthException {
      _setState(status: GeoStatus.requiresAuth);
    } on Exception catch (e) {
      _setState(status: GeoStatus.serverError, lastErrorText: e.toString());
    }
  }

  /// Refresco manual: fuerza fix fresco + ping + búsqueda ya mismo.
  Future<void> manualRefresh() async {
    _checkNotDisposed();
    if (!ui.value.visibilityIntended) {
      _setState(status: GeoStatus.hidden);
      return;
    }
    _lastPingAt = null;
    _lastSearchAt = null;
    _setState(status: GeoStatus.acquiringFix);
    await tickOnce();
  }

  /// Ocultarse INMEDIATO: para el bucle, borra presencia en el servidor y
  /// limpia la lista de peers (la UI no sigue mostrando datos suyos).
  /// Aunque falle la llamada (sin red), el TTL server de 30 min cubre al
  /// usuario; reintento best-effort programado.
  Future<void> hideNow() async {
    _checkNotDisposed();
    await _stopPublishing(
      visibleIntended: false,
      message: 'Ya no estás visible en descubrimiento.',
    );
    ui.value = ui.value.copyWith(status: GeoStatus.hidden, peers: const []);
  }

  /// Logout / cerrar app: igual que ocultarse pero sin mensajes de UI
  /// (mejor esfuerzo; el TTL 30 min es la red de seguridad).
  Future<void> stopForLogout() async {
    if (_disposed) {
      return;
    }
    try {
      await _stopPublishing(visibleIntended: false);
    } on Exception {
      // best-effort
    }
    if (!_disposed) {
      ui.value = const GeoUiState(status: GeoStatus.hidden, peers: []);
    }
    _cancelTickLoop();
  }

  // ─── loop ───────────────────────────────────────────────────────────

  void _ensureTickLoop() {
    _checkNotDisposed();
    if (_tickTimer != null) return;
    // Solo programa el ciclo: los tests conducen [tickOnce] a mano con un
    // tickInterval grande; en producción el primer tick ocurre a los 10 s.
    _tickTimer = Timer.periodic(tickInterval, (_) {
      unawaited(tickOnce());
    });
  }

  void _cancelTickLoop() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// Un paso del bucle (también invocado por el Timer; test-friendly).
  @visibleForTesting
  Future<void> tickOnce() async {
    if (_disposed || _ticking) return;
    _ticking = true;
    try {
      if (!ui.value.visibilityIntended) {
        if (ui.value.status != GeoStatus.hidden) {
          _setState(status: GeoStatus.hidden);
        }
        return;
      }

      // 0) Conectividad: sin internet real → offline (sin RPC inútiles).
      if (!_online()) {
        _setState(status: GeoStatus.offline, message: 'Sin conexión a internet.');
        return;
      }

      // 1) Fix de ubicación. La validez (precisión ≤ 150 m, edad ≤ 2 min)
      //    la valida LocationEngine; nunca se reutiliza un fix viejo.
      var fix = _engine.lastValidFix;
      if (fix == null) {
        _setState(status: GeoStatus.acquiringFix);
        try {
          fix = await _engine.acquireFix();
        } on GeoException catch (e) {
          _onGeoError(e);
          return;
        }
      }

      // 2) Ping de presencia (cadencia ≥ 15 s anti-abuso; server re-verifica).
      final nowAfterFix = _clock();
      if (_lastPingAt == null ||
          nowAfterFix.difference(_lastPingAt!) >= presencePingInterval ||
          !_lastPingOk) {
        try {
          await _provider.publishPresence(
            fix,
            radiusMeters: ui.value.radiusMeters,
          );
          _lastPingAt = nowAfterFix;
          _lastPingOk = true;
        } on DiscoveryAuthException {
          _setState(status: GeoStatus.requiresAuth);
          return;
        }
        // DiscoveryServerException baja al catch exterior → serverError.
      }

      // 3) Búsqueda de peers (re-verifica consent server-side primero).
      final nowBeforeSearch = _clock();
      if (_lastSearchAt == null ||
          nowBeforeSearch.difference(_lastSearchAt!) >= searchInterval) {
        final prefs = await _safeLoadPrefs();
        if (prefs != null && !prefs.discoveryEnabled) {
          // El servidor dice que el usuario ya no está visible (consent
          // revocado desde otra pantalla/dispositivo respetado aquí).
          await _stopPublishing(visibleIntended: false);
          _setState(
            status: GeoStatus.hidden,
            peers: const [],
            message: 'Estás oculto para otros (preferencia del servidor).',
          );
          return;
        }
        try {
          final users = await _provider.discover(
            lat: fix.lat,
            lng: fix.lng,
            radiusMeters:
                DiscoveryConfig.nearestAllowedRadius(ui.value.radiusMeters),
          );
          users.sortByDistance();
          _lastSearchAt = _clock();
          _setState(status: GeoStatus.live, peers: users);
        } on DiscoveryAuthException {
          _setState(status: GeoStatus.requiresAuth);
          return;
        } on DiscoveryServerException catch (e) {
          _setState(
            status: GeoStatus.serverError,
            message: 'El server no respondió. Reintenta en breve.',
            lastErrorText: e.toString(),
          );
          return;
        }
      }

      if (ui.value.status != GeoStatus.live) {
        _setState(status: GeoStatus.live, message: null);
      }
    } on DiscoveryServerException catch (e) {
      _setState(
        status: GeoStatus.serverError,
        message: 'El server no respondió. Reintenta en breve.',
        lastErrorText: e.toString(),
      );
    } on Exception catch (e) {
      _setState(status: GeoStatus.serverError, lastErrorText: e.toString());
    } catch (e) {
      // Error fuera de Exception (programación/estado): fail-closed visible.
      _setState(status: GeoStatus.serverError, lastErrorText: e.toString());
    } finally {
      _ticking = false;
    }
  }

  // ─── helpers ────────────────────────────────────────────────────────

  void _onGeoError(GeoException e) {
    switch (e.code) {
      case GeoErrorCode.permissionDenied:
      case GeoErrorCode.permissionPermanentlyDenied:
      case GeoErrorCode.serviceDisabled:
        // La canasta "bloqueado": permiso no concedido O servicio de
        // ubicación del SO apagado. El hint de [GeoErrorMessages] distingue
        // la causa exacta para el usuario.
        _setState(status: GeoStatus.permissionBlocked, message: e.code.message);
        break;
      case GeoErrorCode.noFixUnusable:
      case GeoErrorCode.timeout:
      case GeoErrorCode.unknown:
        _setState(
          status: GeoStatus.serverError,
          message: e.code.message,
          lastErrorText: e.toString(),
        );
        break;
    }
  }

  Future<DiscoveryPrefs?> _safeLoadPrefs() async {
    try {
      return await _provider.loadPreferences();
    } on DiscoveryAuthException {
      _setState(status: GeoStatus.requiresAuth);
      return null;
    } on Exception {
      return null; // sin prefs → seguimos; el server re-verifica igual.
    }
  }

  /// Para el bucle y borra presencia en el servidor (best-effort + retry).
  Future<void> _stopPublishing({
    required bool visibleIntended,
    String? message,
  }) async {
    _cancelTickLoop();
    _lastPingAt = null;
    _lastSearchAt = null;
    _lastPingOk = false;
    _setState(
      visibilityIntended: visibleIntended,
      peers: const [],
      message: message,
    );
    try {
      await _provider.expirePresence();
    } on DiscoveryAuthException {
      // Sin sesión: nada que borrar server-side (la presencia nunca existió
      // o ya expiró); el TTL 30 min cubre cualquier caso residual.
    } on Exception {
      _scheduleExpireRetry();
    }
  }

  void _scheduleExpireRetry() {
    if (!_disposed) {
      unawaited(() async {
        var canceled = false;
        while (!canceled && !_disposed) {
          try {
            await _provider.expirePresence();
            canceled = true;
          } on DiscoveryAuthException {
            canceled = true; // sin sesión: nada que borrar
          } on Exception {
            await Future<void>.delayed(searchInterval * 3);
          }
        }
      }());
    }
  }

  void _setState({
    GeoStatus? status,
    Object? message = _absent,
    List<NearbyGeoUser>? peers,
    double? radiusMeters,
    bool? visibilityIntended,
    Object? lastErrorText = _absent,
  }) {
    if (_disposed) return;
    ui.value = ui.value.copyWith(
      status: status,
      message: message,
      peers: peers,
      radiusMeters: radiusMeters,
      visibilityIntended: visibilityIntended,
      lastErrorText: lastErrorText,
    );
  }

  static const Object _absent = Object();

  void _checkNotDisposed() {
    if (_disposed) throw StateError('DiscoveryCoordinator disposed');
  }

  /// Cleanup total (pantalla cerrada). Cancela timers; la presencia expira
  /// por TTL server-side (no se promete borrado instantáneo sin conexión).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelTickLoop();
    ui.dispose();
  }
}
