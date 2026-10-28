import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'notification_service.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/radar_config.dart';
import 'ble_proximity_service.dart';
import 'discovery_policy.dart';
import 'encounter_key.dart';
import 'entitlement_service.dart';
import 'premium_service.dart';
import 'zone_id_service.dart';
import 'isar_service.dart';
import 'connectivity_service.dart';
import 'p2p_security_service.dart';
import 'chat_e2ee_service.dart';
import 'p2p_handshake_session.dart' show P2PSessionKeyMaterial;
import 'supabase_service.dart';
import 'package:cryptography/cryptography.dart';
import '../models/isar_models.dart';
import 'logger_service.dart';
import 'mesh_policy.dart';
import 'p2p_wiring.dart';
import 'p2p_ake_coordinator.dart';
import 'zone_identity_bootstrap_service.dart';

/// Modelo de usuario descubierto por Nearby Connections.
class NearbyUser {
  NearbyUser({
    required this.endpointId,
    required this.token,
    this.userName = '...',
    this.zoneId = '',
    this.isConnected = false,
    this.identityVerified = false,
    this.distanceMeters,
    this.profile,
  });

  final String endpointId;
  final String token; // Token efímero recibido
  String userName; // Resuelto desde Supabase
  String zoneId; // ZONE-ID real resuelto
  bool isConnected;

  /// Z-004 WI-2 (PHASE E/G): `true` SOLO si el endpoint completó un AKE
  /// (`ZONE-P2P-AKE-1`) con claves ancladas/verificables. `profile_exchange`
  /// recibido sin AKE completado deja esta marca en `false` (identidad
  /// 'unverified' — el despachador NO deriva llave de sesión para él).
  bool identityVerified;

  double? distanceMeters; // Estimado por RSSI BLE
  Map<String, dynamic>? profile; // Perfil completo de Supabase
}

/// Modelo de mensaje recibido via payload.
class NearbyMessage {
  final String fromEndpointId;
  final String? sourceZoneId; // ID original del emisor en la malla
  final String text;
  NearbyMessage({
    required this.fromEndpointId,
    required this.text,
    this.sourceZoneId,
  });
}

/// Servicio Singleton que usa Google Nearby Connections + tokens efímeros de Supabase.
/// El token BT se comparte en lugar del user_id real, protegiendo la identidad.
class NearbyService with WidgetsBindingObserver {
  static final NearbyService _instance = NearbyService._internal();
  factory NearbyService() => _instance;
  NearbyService._internal();

  final Nearby _nearby = Nearby();
  final _supabaseService = SupabaseService();
  final _zoneIdService = ZoneIdService();
  final _bleProximity = BleProximityService();
  final _isar = IsarService();
  final _connectivity = ConnectivityService();
  final _security = P2PSecurityService();
  final _chatE2EE = ChatE2EEService();
  final _logger = LoggerService();

  /// Z-004 PHASE E/G — cable WI-2 (gate del despachador) + WI-6
  /// (rate-limit local). Sin secretos; el estado AKE vive por endpoint
  /// efímero y muere con la conexión.
  final P2pAkeWiring _akeWiring = P2pAkeWiring();

  /// Z-004 PHASE E/G — cableado REAL del handshake `ZONE-P2P-AKE-1`
  /// (coordinador puro con transporte/identidad inyectados; ver
  /// `p2p_ake_coordinator.dart`). Estado por endpoint efímero; material de
  /// sesión por-conexión (NUNCA persistido y jamás escrito en `sk_<zone>`
  /// legacy). La demo física H-01…H-15 permanece NOT RUN.
  P2pAkeCoordinator? _akeCoordinator;

  /// P2P_CLUSTER mejora alcance y descubrimiento bilateral en espacios abiertos.
  static const Strategy _strategy = Strategy.P2P_CLUSTER;
  static const String _serviceId = 'com.dybrocorp.zone';
  static const String _invalidToken = 'ZONE-INIT';

  String _currentToken = _invalidToken;
  String _userId = '';
  String _myZoneId = '';
  bool _stealthMode = false;
  double _discoveryRadiusMeters = RadarConfig.discoveryRadiusMeters;
  Set<String> _blockedUserIds = {};

  double get discoveryRadiusMeters => _discoveryRadiusMeters;

  bool _isAdvertising = false;
  bool _isDiscovering = false;
  bool _isRadarIntendedActive =
      false; // Nueva bandera para persistir el estado deseado
  bool _lifecycleObserverRegistered = false;
  bool _isAppMinimized =
      false; // Bandera para saber si estamos en segundo plano
  bool get isRadarActive => _isRadarIntendedActive;

  // PHASE 2.2.6 — contrato de descubrimiento: lifecycle explícito + sesiones
  // efímeras de endpoint (el endpoint ID es transporte, nunca identidad).
  final DiscoveryLifecycle _lifecycle = DiscoveryLifecycle();
  final EndpointSessions _sessions = EndpointSessions();
  bool _starting = false;

  /// Estado del lifecycle para diagnóstico/UI (sin secretos).
  DiscoveryState get discoveryState => _lifecycle.state;

  Timer? _scanCycleTimer;
  Timer? _tokenRefreshTimer;
  Timer? _globalDiscoveryTimer;

  final Map<String, NearbyUser> _discoveredUsers = {};
  final Set<String> _notifiedUserIds =
      {}; // Para no spamear notificaciones del mismo usuario
  final _discoveredUsersController =
      StreamController<List<NearbyUser>>.broadcast();
  Stream<List<NearbyUser>> get discoveredUsersStream =>
      _discoveredUsersController.stream;
  List<NearbyUser> get discoveredUsers => _discoveredUsers.values.toList();

  final _incomingMessagesController =
      StreamController<NearbyMessage>.broadcast();
  Stream<NearbyMessage> get incomingMessagesStream =>
      _incomingMessagesController.stream;

  // Z-003 (FASE 1.4): cola fail-closed de mensajes mesh pendientes de llave de sesión.
  final List<MeshPendingMessage> _pendingMeshMessages = [];
  static const int _maxPendingMeshMessages = 200;
  final _meshStatusController = StreamController<MeshStatusEvent>.broadcast();
  Stream<MeshStatusEvent> get meshStatusStream => _meshStatusController.stream;
  List<MeshPendingMessage> get pendingMeshMessages =>
      List.unmodifiable(_pendingMeshMessages);

  final Map<String, dynamic> _pendingConnections = {};
  final Set<String> _connectedEndpoints = {};
  final Set<String> _resolvingEndpoints = {};

  // Grace Period: Evita que los usuarios desaparezcan inmediatamente en reinicios de ciclo
  final Map<String, Timer> _lostEndpointsGraceTimers = {};

  // Mesh Routing Table: Map<ZoneId, MeshRoute>
  final Map<String, MeshRoute> _routingTable = {};
  static const int _maxMeshHops = 5;
  static const int _maxRoutingTableEntries = 1024;

  // Z-005 (FASE 1.6): Dedup con LRU + TTL (sin clear() global). Reemplaza el
  // Set<String> con clear() que permitía replay tras reinicio del set.
  final MeshDedup _seenMessageIds = MeshDedup();

  int get routingTableSize => _routingTable.values.where(_isRouteActive).length;

  bool _isRouteActive(MeshRoute route) {
    return _connectedEndpoints.contains(route.nextHopEndpointId);
  }

  // ──────────────────────────────────────────────────────────────
  //  Inicialización
  // ──────────────────────────────────────────────────────────────

  Future<void> initialize(String userId) async {
    if (userId.isEmpty) {
      _logger.debug(
        '[NearbyService] Error: Intentando inicializar con userId vacío',
      );
      return;
    }
    _userId = userId;
    _ensureLifecycleObserver();
    await _connectivity.initialize();
    await _loadUserContext();
    await _restoreLocalMeshRoutes();
    await _refreshToken();
  }

  Future<void> _loadUserContext() async {
    _myZoneId = _zoneIdService.zoneId ?? '';
    _blockedUserIds = await _supabaseService.getBlockedUserIds(_userId);
    final profile = await _zoneIdService.getMyProfile();
    _stealthMode = profile?['stealth_mode'] == true;
    _myZoneId = profile?['zone_id'] as String? ?? _myZoneId;
    await _loadDiscoveryRadius();
    await _cacheOwnProfileForOffline();

    // Cargar estado del radar
    final prefs = await SharedPreferences.getInstance();
    _isRadarIntendedActive = prefs.getBool('radar_active') ?? false;
  }

  Future<void> _cacheOwnProfileForOffline() async {
    try {
      final profile = await _zoneIdService.getMyProfile();
      if (profile == null) return;
      await _isar.saveProfile({
        ...profile,
        'publicKey': _security.publicBase64,
        'public_key': _security.publicBase64,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      _logger.debug('[NearbyService] No se pudo cachear perfil local: $e');
    }
  }

  Future<void> _restoreLocalMeshRoutes() async {
    try {
      _routingTable.clear();
      final routes = await _isar.getRecentRoutes();
      for (final route in routes) {
        if (route.targetZoneId == _myZoneId) continue;
        if (route.nextHopEndpointId.startsWith('MESH:')) continue;
        _routingTable[route.targetZoneId] = route;
      }
      if (_routingTable.isNotEmpty) {
        _logger.debug(
          '[NearbyService] Rutas mesh restauradas: ${_routingTable.length}',
        );
      }
    } catch (e) {
      _logger.debug('[NearbyService] No se pudieron restaurar rutas mesh: $e');
    }
  }

  Future<void> _loadDiscoveryRadius() async {
    final prefs = await SharedPreferences.getInstance();
    final isPremium = await PremiumService.instance.ensureLoaded();
    _discoveryRadiusMeters = RadarConfig.effectiveRadius(
      prefs.getDouble(RadarConfig.prefsDiscoveryRadiusKey),
      isPremium: isPremium,
    );
  }

  /// Actualiza el radio de detección (metros) y persiste la preferencia.
  Future<void> setDiscoveryRadiusMeters(double meters) async {
    final isPremium = await PremiumService.instance.ensureLoaded();
    _discoveryRadiusMeters = RadarConfig.effectiveRadius(
      meters,
      isPremium: isPremium,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      RadarConfig.prefsDiscoveryRadiusKey,
      _discoveryRadiusMeters,
    );
  }

  void _ensureLifecycleObserver() {
    if (_lifecycleObserverRegistered) return;
    WidgetsBinding.instance.addObserver(this);
    _lifecycleObserverRegistered = true;
  }

  Future<void> _refreshToken() async {
    if (_userId.isEmpty) return;
    try {
      final token = await _supabaseService.generateBtToken(_userId);
      if (token != null && token.isNotEmpty) {
        _currentToken = token;
        _logger.debug('[NearbyService] Token BT renovado via Supabase');
      } else {
        // Fallback Offline: usar pseudónimo HMAC (no expone el ZONE-ID real)
        final pseudonym = await _offlinePseudonym(_myZoneId);
        await _savePseudonymMapping(pseudonym, _myZoneId);
        _currentToken = 'OFFLINE:$pseudonym';
        _logger.debug(
          '[NearbyService] Advertencia: Usando token OFFLINE pseudónimo',
        );
      }
    } catch (e) {
      final pseudonym = await _offlinePseudonym(_myZoneId);
      await _savePseudonymMapping(pseudonym, _myZoneId);
      _currentToken = 'OFFLINE:$pseudonym';
      _logger.debug(
        '[NearbyService] Error renovando token, usando fallback OFFLINE pseudónimo: $e',
      );
    }
  }

  /// Genera un pseudónimo determinístico a partir del zoneId usando HMAC-SHA256.
  /// Ambos dispositivos independientemente producen el mismo resultado sin exponer el zoneId real.
  Future<String> _offlinePseudonym(String zoneId) async {
    final hmac = Hmac.sha256();
    final mac = await hmac.calculateMac(
      utf8.encode(zoneId),
      secretKey: SecretKey(utf8.encode(zoneId)),
    );
    return base64Url.encode(mac.bytes).substring(0, 32);
  }

  // ──────────────────────────────────────────────────────────────
  //  Pseudonym ↔ ZoneId Cache (en SecureStorage)
  // ──────────────────────────────────────────────────────────────

  Future<void> _savePseudonymMapping(String pseudonym, String zoneId) async {
    try {
      const storage = FlutterSecureStorage();
      await storage.write(key: 'pseudo_$pseudonym', value: zoneId);
    } catch (e) {
      _logger.debug('[NearbyService] Error guardando pseudónimo: $e');
    }
  }

  Future<String?> _resolvePseudonym(String pseudonym) async {
    try {
      const storage = FlutterSecureStorage();
      return await storage.read(key: 'pseudo_$pseudonym');
    } catch (e) {
      _logger.debug('[NearbyService] Error leyendo pseudónimo: $e');
      return null;
    }
  }

  bool get _hasValidToken =>
      _currentToken.isNotEmpty && _currentToken != _invalidToken;

  // ──────────────────────────────────────────────────────────────
  //  AppLifecycle — pausa en background (ahorra batería)
  // ──────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _isAppMinimized = true;
      // No pausar el radar si _isRadarIntendedActive == true.
      if (!_isRadarIntendedActive) {
        _pauseScanning();
      }
    } else if (state == AppLifecycleState.detached) {
      unawaited(_shutdownRuntimeSession());
    } else if (state == AppLifecycleState.resumed) {
      _isAppMinimized = false;
      if (_isRadarIntendedActive) {
        _resumeScanning();
      }
    }
  }

  Future<void> _shutdownRuntimeSession() async {
    await stopRadar();
    await _zoneIdService.endRuntimeSession();
  }

  void _pauseScanning() {
    _scanCycleTimer?.cancel();
    _nearby.stopAdvertising();
    _nearby.stopDiscovery();
    _bleProximity.stopScanning();
    _isAdvertising = false;
    _isDiscovering = false;
  }

  Future<bool> startRadar() async {
    // GATE PREMIUM (fail-closed): el radar Bluetooth es función Premium
    // verificada en backend (docs/redesign/ZONE_FREEMIUM_ARCHITECTURE.md §2.4).
    // `loadForce` revalida SIEMPRE contra `get_my_entitlements` (z215) —
    // un flag local nunca habilita esto. Transición documentada: mientras
    // z215 no esté en remoto, el fallback legacy `users.is_premium` mantiene
    // la continuidad de usuarios con Premium legado.
    final entitlement = await EntitlementService.instance.loadForce();
    if (!entitlement.allowsBluetooth) {
      _logger.debug(
        '[NearbyService] Radar BT bloqueado: estado entitlement '
        '${entitlement.state.name}.',
      );
      _lifecycle.transportFailed(DiscoveryError.premiumRequired);
      return false;
    }

    // Idempotencia ante invocaciones concurrentes (doble-tap, resume+tap).
    if (_starting) {
      _logger.debug('[NearbyService] Arranque ya en curso, ignorando.');
      return _isDiscovering;
    }
    if (!_lifecycle.canStart) {
      _logger.debug('[NearbyService] Arranque ignorado por lifecycle.');
      return _isDiscovering;
    }
    _starting = true;
    _lifecycle.beginStart();
    try {
      return await _startRadarInternal();
    } finally {
      _starting = false;
    }
  }

  Future<bool> _startRadarInternal() async {
    _isRadarIntendedActive = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('radar_active', true);

    _ensureLifecycleObserver();
    await _loadUserContext();
    await _refreshToken();

    if (!_hasValidToken) {
      _logger.debug(
        '[NearbyService] No se puede iniciar radar: token BT inválido',
      );
      _lifecycle.transportFailed(DiscoveryError.invalidZoneIdentity);
      return false;
    }

    _scanCycleTimer?.cancel();
    _tokenRefreshTimer?.cancel();
    _globalDiscoveryTimer?.cancel();

    // Añadir un pequeño jitter aleatorio para evitar colisiones de descubrimiento bilateral
    final jitter = (DateTime.now().millisecondsSinceEpoch % 800);
    await Future.delayed(Duration(milliseconds: jitter));

    var advertisingOk = true;
    if (!_stealthMode) {
      advertisingOk = await _startAdvertising();
      if (!advertisingOk) {
        _logger.debug('[NearbyService] Advertising no disponible (degradado).');
      }
    } else {
      await _stopAdvertising();
      _logger.debug(
        '[NearbyService] Modo timidez: solo descubrimiento, sin anunciar',
      );
    }

    // Discovery secuencial con retraso
    await Future.delayed(const Duration(milliseconds: 300));
    final discoveryOk = await _startDiscovery();
    if (!discoveryOk) {
      _lifecycle.transportFailed(DiscoveryError.discoveryFailed);
      return false;
    }
    await _bleProximity.startScanning();

    // BILATERAL OFFLINE: mostrar rutas mesh activas con perfiles cacheados.
    await _discoverMeshUsers();

    // Ciclo de reinicio más inteligente (cada 45s en lugar de 30s para dar estabilidad)
    _scanCycleTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      if (_isDiscovering) {
        _logger.debug('[NearbyService] Reinicio estratégico de discovery...');
        await _nearby.stopDiscovery();
        _isDiscovering = false;
        await Future.delayed(
          const Duration(milliseconds: 1500),
        ); // Más tiempo para que el stack BT se limpie
        if (_isRadarIntendedActive) await _startDiscovery();
      }
      // Refrescar rutas mesh activas.
      if (_isRadarIntendedActive) {
        await _discoverMeshUsers();
      }
    });

    // Rotación de token y advertising (cada 5m)
    _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await _refreshToken();
      if (!_hasValidToken) return;
      if (_stealthMode) return;
      if (_isAdvertising && _isRadarIntendedActive) {
        await _stopAdvertising();
        await Future.delayed(const Duration(seconds: 1));
        await _startAdvertising();
      }
    });

    // Actualiza cache de perfiles activos sin agregarlos al radar visible.
    _globalDiscoveryTimer = Timer.periodic(const Duration(minutes: 2), (
      _,
    ) async {
      if (_isRadarIntendedActive && _connectivity.hasRealInternet) {
        await _discoverGlobalUsers();
        // Actualizar actividad BT en Supabase
        await _supabaseService.updateBtActivity();
      }
    });

    _lifecycle.transportUp(
      advertising: advertisingOk || _stealthMode,
      discovering: true,
    );
    return true;
  }

  Future<void> stopRadar() async {
    // Idempotente: detenerse dos veces no hace nada la segunda.
    if (_lifecycle.state == DiscoveryState.stopped &&
        !_isRadarIntendedActive &&
        !_isAdvertising &&
        !_isDiscovering) {
      return;
    }
    _lifecycle.beginStop();
    _isRadarIntendedActive = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('radar_active', false);

    _scanCycleTimer?.cancel();
    _tokenRefreshTimer?.cancel();
    _globalDiscoveryTimer?.cancel();
    await _stopAdvertising();
    await _stopDiscovery();
    // Teardown total de endpoints: stopAdvertising/stopDiscovery NO
    // desconectan (contrato del plugin 4.3.0); el apagado explícito sí.
    try {
      await _nearby.stopAllEndpoints();
    } catch (e) {
      _logger.debug('[NearbyService] Error en stopAllEndpoints: $e');
    }
    _bleProximity.stopScanning();
    for (final timer in _lostEndpointsGraceTimers.values) {
      timer.cancel();
    }
    _lostEndpointsGraceTimers.clear();
    _discoveredUsers.clear();
    _resolvingEndpoints.clear();
    // Limpieza del estado efímero de transporte (CASE B/D): sin esto, un
    // reinicio creería seguir conectado a endpoints muertos.
    _connectedEndpoints.clear();
    _pendingConnections.clear();
    _routingTable.clear();
    _sessions.clear();
    _emitDiscoveredUsers();
    _lifecycle.stopped();
  }

  void _resumeScanning() {
    if (!_isRadarIntendedActive) return;
    startRadar();
  }

  /// Inicia advertising. Retorna el resultado REAL del plugin 4.3.0
  /// (antes se ignoraba: un `false` del plugin era un fallo silencioso).
  Future<bool> _startAdvertising() async {
    if (_stealthMode || !_hasValidToken) return false;
    if (_isAdvertising) {
      await _stopAdvertising();
    }
    try {
      final ok = await _nearby.startAdvertising(
        _currentToken,
        _strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
      _isAdvertising = ok;
      if (!ok) {
        _logger.debug(
          '[NearbyService] startAdvertising devolvió false (radio no disponible).',
        );
      }
      return ok;
    } catch (e) {
      _logger.debug('[NearbyService] Error al iniciar advertising: $e');
      _isAdvertising = false;
      return false;
    }
  }

  /// Inicia discovery. Retorna el resultado REAL del plugin 4.3.0.
  Future<bool> _startDiscovery() async {
    if (!_hasValidToken) return false;
    if (_isDiscovering) {
      await _stopDiscovery();
    }
    try {
      final ok = await _nearby.startDiscovery(
        _currentToken,
        _strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: _serviceId,
      );
      _isDiscovering = ok;
      if (!ok) {
        _logger.debug(
          '[NearbyService] startDiscovery devolvió false (radio no disponible).',
        );
      }
      return ok;
    } catch (e) {
      _logger.debug('[NearbyService] Error al iniciar discovery: $e');
      _isDiscovering = false;
      return false;
    }
  }

  Future<void> _stopAdvertising() async {
    if (!_isAdvertising) return;
    try {
      await _nearby.stopAdvertising();
    } catch (e) {
      _logger.debug('[NearbyService] Error al detener advertising: $e');
    }
    _isAdvertising = false;
  }

  Future<void> _stopDiscovery() async {
    if (!_isDiscovering) return;
    try {
      await _nearby.stopDiscovery();
    } catch (e) {
      _logger.debug('[NearbyService] Error al detener discovery: $e');
    }
    _isDiscovering = false;
  }

  // ──────────────────────────────────────────────────────────────
  //  Discovery — resuelve token → perfil via Supabase
  // ──────────────────────────────────────────────────────────────

  void _onEndpointFound(String id, String receivedToken, String serviceId) {
    // El lifecycle detenido/en parada no muta estado (callbacks tardíos).
    if (!_lifecycle.acceptsCallbacks || !_isRadarIntendedActive) return;
    if (receivedToken.isEmpty || receivedToken == _invalidToken) return;

    // Si estaba en el periodo de gracia para ser eliminado, cancelar el timer
    _lostEndpointsGraceTimers[id]?.cancel();
    _lostEndpointsGraceTimers.remove(id);

    // Deduplicación de sesión (CASE A): el mismo endpoint re-anunciado con el
    // MISMO token no se reprocesa; con token NUEVO (rotación 5m) sí.
    if (!_sessions.noteFound(id, receivedToken)) {
      return;
    }

    if (!_bleProximity.isTokenWithinRadius(
      receivedToken,
      _discoveryRadiusMeters,
    )) {
      return;
    }

    // Cuando Nearby encuentra un dispositivo activo, eliminar entradas mesh
    // para ese mismo usuario y evitar duplicados.
    if (receivedToken.startsWith('OFFLINE:')) {
      final pseudonym = receivedToken.replaceFirst('OFFLINE:', '');
      unawaited(_resolvePseudonym(pseudonym).then((zoneId) {
        if (zoneId != null) {
          _discoveredUsers.remove('MESH:$zoneId');
        }
      }));
    }

    if (!_discoveredUsers.containsKey(id)) {
      _discoveredUsers[id] = NearbyUser(
        endpointId: id,
        token: receivedToken,
        userName: 'Cargando...',
      );
      _emitDiscoveredUsers();
    }

    // Iniciar conexión inmediatamente para resolver perfiles P2P (Offline-first)
    unawaited(requestConnection(id));

    unawaited(_resolveTokenAsync(id, receivedToken));
  }

  Future<void> _resolveTokenAsync(String endpointId, String token) async {
    if (_resolvingEndpoints.contains(endpointId)) return;
    _resolvingEndpoints.add(endpointId);

    try {
      Map<String, dynamic>? profile;
      String? resolvedZoneId;

      // 1. Manejo de tokens Offline con pseudónimos
      if (token.startsWith('OFFLINE:')) {
        final pseudonym = token.replaceFirst('OFFLINE:', '');
        resolvedZoneId = await _resolvePseudonym(pseudonym);
        if (resolvedZoneId != null) {
          _logger.debug(
            '[NearbyService] Pseudónimo offline resuelto: $pseudonym → $resolvedZoneId',
          );
        } else {
          _logger.debug(
            '[NearbyService] Pseudónimo offline sin caché: $pseudonym (esperando P2P)',
          );
        }
        // Buscar INMEDIATAMENTE en Isar para resolución bilateral rápida
        if (resolvedZoneId != null) {
          final cachedLocal = await _isar.getProfile(resolvedZoneId);
          if (cachedLocal != null) {
            profile = {
              'id': cachedLocal.userId,
              'zone_id': cachedLocal.zoneId,
              'display_name': cachedLocal.displayName,
              'avatar_url': cachedLocal.avatarUrl,
              'publicKey': cachedLocal.publicKey,
              'public_key': cachedLocal.publicKey,
              'updatedAt': cachedLocal.updatedAt.toIso8601String(),
            };
            _logger.debug(
              '[NearbyService] Perfil OFFLINE resuelto desde Isar para $resolvedZoneId',
            );
          }
        }
      }

      // 2. Intentar resolver vía Supabase si tenemos internet real y no tenemos perfil aún
      if (profile == null &&
          resolvedZoneId == null &&
          _connectivity.hasRealInternet) {
        for (var attempt = 0; attempt < 2; attempt++) {
          profile = await _supabaseService.resolveToken(token);
          if (profile != null) {
            resolvedZoneId = profile['zone_id'] as String?;
            break;
          }
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
        }
      }

      // 3. Fallback: Si tenemos zoneId pero no perfil, buscar en Isar
      if (resolvedZoneId != null && profile == null) {
        final local = await _isar.getProfile(resolvedZoneId);
        if (local != null) {
          profile = {
            'id': local.userId,
            'zone_id': local.zoneId,
            'display_name': local.displayName,
            'avatar_url': local.avatarUrl,
            'publicKey': local.publicKey,
            'public_key': local.publicKey,
            'updatedAt': local.updatedAt.toIso8601String(),
          };
          _logger.debug(
            '[NearbyService] Perfil recuperado de Isar para $resolvedZoneId',
          );
        }
      }

      if (!_discoveredUsers.containsKey(endpointId)) return;

      // 4. Si tenemos el ZoneID pero no perfil completo, mostrar ZoneID como fallback
      if (profile == null && resolvedZoneId != null) {
        profile = {'zone_id': resolvedZoneId, 'display_name': resolvedZoneId};
      }

      // 5. Sin zoneId alguno: intentar via mesh routing
      if (profile == null) {
        _logger.debug(
          '[NearbyService] Perfil no resuelto vía servidor o caché. Intentando mesh routing.',
        );

        for (final routeEntry in _routingTable.entries) {
          final zoneId = routeEntry.key;
          final route = routeEntry.value;

          if (zoneId.isNotEmpty && route.distance <= _maxMeshHops) {
            final meshProfile = await _isar.getProfile(zoneId);
            if (meshProfile != null) {
              profile = {
                'id': meshProfile.userId,
                'zone_id': meshProfile.zoneId,
                'display_name': meshProfile.displayName,
                'avatar_url': meshProfile.avatarUrl,
                'publicKey': meshProfile.publicKey,
                'public_key': meshProfile.publicKey,
                'updatedAt': meshProfile.updatedAt.toIso8601String(),
              };
              resolvedZoneId = zoneId;
              _logger.debug(
                '[NearbyService] Perfil recuperado de mesh routing para $zoneId',
              );
              break;
            }
          }
        }

        // Sin perfil alguno: mostrar como usuario detectado pendiente de intercambio P2P.
        // PHASE 2.2.6 (frontera de identidad): el token de transporte NUNCA
        // se publica como identidad — zoneId queda vacío hasta la resolución
        // autoritativa (el token vive solo en `user.token`).
        if (profile == null && _discoveredUsers.containsKey(endpointId)) {
          final user = _discoveredUsers[endpointId]!;
          user.userName = 'Usuario Cercano';
          user.zoneId = '';
          _emitDiscoveredUsers();
          return;
        }

        if (profile == null) {
          _logger.debug(
            '[NearbyService] Esperando intercambio P2P para resolver perfil...',
          );
          return;
        }
      }

      final profileId = profile['id'] as String?;
      final profileZoneId = profile['zone_id'] as String?;

      if (profileId == _userId ||
          (profileZoneId != null &&
              profileZoneId.isNotEmpty &&
              profileZoneId == _myZoneId)) {
        _logger.debug(
          '[NearbyService] Somos nosotros mismos, descartando endpoint y desconectando.',
        );
        _discoveredUsers.remove(endpointId);
        _emitDiscoveredUsers();
        disconnectFrom(endpointId);
        return;
      }

      if (profileId != null && _blockedUserIds.contains(profileId)) {
        _discoveredUsers.remove(endpointId);
        _emitDiscoveredUsers();
        return;
      }

      final distance = _bleProximity.distanceMetersForToken(token);
      if (distance != null &&
          !RadarConfig.isDistanceWithinRadius(
            distance,
            _discoveryRadiusMeters,
          )) {
        _discoveredUsers.remove(endpointId);
        _emitDiscoveredUsers();
        return;
      }

      final user = _discoveredUsers[endpointId]!;
      user.userName =
          profile['display_name'] ?? profile['zone_id'] ?? 'Usuario';
      user.profile = profile;

      // PHASE 2.2.6 (frontera de identidad): el binding endpoint→identidad
      // solo acepta handles ZONE canónicos. Si falla, la tarjeta se degrada
      // a no-resuelta (nunca se publica un identificador no verificado).
      final candidateZone = (profile['zone_id'] ?? '').toString();
      try {
        _sessions.bindIdentity(endpointId, candidateZone);
        user.zoneId = _sessions.zoneFor(endpointId)!;
      } on InvalidDiscoveryIdentityError {
        _logger.debug(
          '[NearbyService] Identidad no canónica, degradando tarjeta.',
        );
        user.userName = 'Usuario Cercano';
        user.zoneId = '';
        _discoveredUsers[endpointId] = user;
        _resolvingEndpoints.remove(endpointId);
        _emitDiscoveredUsers();
        return;
      }

      _discoveredUsers[endpointId] = user;
      _resolvingEndpoints.remove(endpointId);

      if (_isAppMinimized && !_notifiedUserIds.contains(user.zoneId)) {
        _notifiedUserIds.add(user.zoneId);
        NotificationService().showDiscoveryNotification(user.userName);
      }

      _emitDiscoveredUsers();

      if (user.zoneId.isNotEmpty) {
        // PHASE 2.2.3 — clave canónica del encuentro (par ordenado + bucket
        // UTC). `null` ⇒ identidad no verificable: se omite el encuentro
        // fail-closed (el perfil/UI no se ven afectados).
        final encounterKey = await EncounterKey.tryCanonicalKey(
          myZone: _myZoneId,
          peerZone: user.zoneId,
          seenAt: DateTime.now(),
        );
        if (encounterKey == null) {
          _logger.debug('[NearbyService] Encuentro omitido: identidad inválida.');
        } else {
          if (_connectivity.hasRealInternet) {
            await _supabaseService.registerEncounter(
              _userId,
              user.zoneId,
              encounterKey: encounterKey,
            );
          }
          await _isar.saveEncounter(
            userId: _userId,
            otherZoneId: user.zoneId,
            isSynced: _connectivity.hasRealInternet,
            encounterKey: encounterKey,
          );
        }
        if (profileId != null) await _isar.saveProfile(profile);
      }
    } catch (e) {
      _logger.debug('[NearbyService] Error al resolver token: $e');
      // No eliminar usuario si falla la resolución - puede funcionar offline
    } finally {
      _resolvingEndpoints.remove(endpointId);
    }
  }

  void _onEndpointLost(String? id) {
    if (id == null) return;
    if (!_lifecycle.acceptsCallbacks) return;

    // Iniciar periodo de gracia de 10 segundos antes de eliminar definitivamente
    _lostEndpointsGraceTimers[id]?.cancel();
    _lostEndpointsGraceTimers[id] = Timer(const Duration(seconds: 10), () {
      _discoveredUsers.remove(id);
      _resolvingEndpoints.remove(id);
      _lostEndpointsGraceTimers.remove(id);
      // CASE D: con la tarjeta expira también la sesión efímera de
      // transporte (un redescubrimiento futuro reprocesa limpio).
      _sessions.noteLost(id);
      _emitDiscoveredUsers();
      _logger.debug(
        '[NearbyService] Endpoint $id eliminado definitivamente tras periodo de gracia.',
      );
    });

    _logger.debug(
      '[NearbyService] Endpoint $id perdido. Entrando en periodo de gracia de 10s...',
    );
  }

  // ──────────────────────────────────────────────────────────────
  //  Conexión
  // ──────────────────────────────────────────────────────────────

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    _pendingConnections[id] = info;
    acceptConnection(id);
  }

  void _onConnectionResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      _connectedEndpoints.add(id);
      _sessions.noteConnected(id);
      _lifecycle.endpointConnected();
      // Z-004 (PHASE E/G): AKE REAL — se abre el handshake `ZONE-P2P-AKE-1`
      // sobre la conexión establecida (hello Ed25519/X25519 firmado; falla
      // cerrado si la identidad de la fundación aún no está).
      unawaited(_startAkeHandshake(id));
      if (_discoveredUsers.containsKey(id)) {
        _discoveredUsers[id]!.isConnected = true;
        _emitDiscoveredUsers();

        // Si estamos offline o preferimos P2P, intercambiamos perfiles inmediatamente
        unawaited(_shareProfileP2P(id));

        // Mesh: Compartir nuestra tabla de rutas
        _shareRoutingTable(id);

        // Descubrir usuarios mesh después de establecer conexión
        unawaited(_discoverMeshUsers());
      }
    } else {
      // CASE C: fallo de conexión — limpiar intento pendiente (el endpoint
      // sigue conocido para futuros reintentos; ver noteConnectionFailed).
      _pendingConnections.remove(id);
      _sessions.noteConnectionFailed(id);
      _logger.debug(
        '[NearbyService] Conexión fallida con ${DiscoveryException.sanitizeEndpoint(id)}.',
      );
    }
  }

  void _onDisconnected(String id) {
    _connectedEndpoints.remove(id);
    _pendingConnections.remove(id);
    _sessions.noteDisconnected(id);
    // Z-004 WI-2: el estado AKE vive SOLO con el endpoint (efímero); la
    // reconexión re-negocia (WI-6 conserva la ventana de radio).
    _akeWiring.noteDisconnected(id);
    _akeCoordinator?.onDisconnected(id);
    _lifecycle.endpointDisconnected(_sessions.connectedCount);
    if (_discoveredUsers.containsKey(id)) {
      _discoveredUsers[id]!.isConnected = false;
      _emitDiscoveredUsers();
    }
  }

  Future<void> requestConnection(String endpointId) async {
    if (!_hasValidToken) return;
    // CASE A/B: un solo intento lógico por endpoint (conectado o en curso).
    if (!_sessions.noteConnectionAttempt(endpointId)) {
      return;
    }
    try {
      final ok = await _nearby.requestConnection(
        _currentToken,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      if (!ok) {
        _sessions.noteConnectionFailed(endpointId);
        _logger.debug(
          '[NearbyService] requestConnection devolvió false '
          '(${DiscoveryException.sanitizeEndpoint(endpointId)}).',
        );
      }
    } catch (e) {
      _sessions.noteConnectionFailed(endpointId);
      _logger.debug('[NearbyService] Error al solicitar conexión: $e');
    }
  }

  Future<void> acceptConnection(String endpointId) async {
    try {
      await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: _onPayloadReceived,
        onPayloadTransferUpdate: _onPayloadTransferUpdate,
      );
    } catch (e) {
      _logger.debug('[NearbyService] Error al aceptar conexión: $e');
    }
  }

  Future<void> rejectConnection(String endpointId) async {
    try {
      await _nearby.rejectConnection(endpointId);
      _pendingConnections.remove(endpointId);
    } catch (e) {
      _logger.debug('[NearbyService] Error al rechazar conexión: $e');
    }
  }

  void disconnectFrom(String endpointId) {
    _nearby.disconnectFromEndpoint(endpointId);
    _connectedEndpoints.remove(endpointId);
    _sessions.noteDisconnected(endpointId);
    _akeWiring.noteDisconnected(endpointId);
    _akeCoordinator?.onDisconnected(endpointId);
    _lifecycle.endpointDisconnected(_sessions.connectedCount);
    if (_discoveredUsers.containsKey(endpointId)) {
      _discoveredUsers[endpointId]!.isConnected = false;
      _emitDiscoveredUsers();
    }
  }

  Future<void> sendMessage(String endpointId, String message) async {
    if (!_connectedEndpoints.contains(endpointId)) return;
    try {
      await _nearby.sendBytesPayload(endpointId, utf8.encode(message));
    } catch (e) {
      _logger.debug('[NearbyService] Error al enviar mensaje: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Z-004 (PHASE E/G) — Cableado REAL del handshake ZONE-P2P-AKE-1
  // (WI-1/WI-2/WI-4 locales). Coordinador puro con transporte/identidad
  // inyectados. Material de sesión por-conexión: NO se persiste.
  // ──────────────────────────────────────────────────────────────

  /// Canal protegido del endpoint (o `null` si el AKE no completó —
  /// fail-closed: una conexión inválida NO intercambia mensajes protegidos).
  P2pAkeChannel? akeChannel(String endpointId) =>
      _akeCoordinator?.channel(endpointId);

  P2pAkeCoordinator? _ensureAkeCoordinator() {
    final existing = _akeCoordinator;
    if (existing != null) return existing;
    // Fail-closed: sin bootstrap de identidad no hay material para firmar.
    final bootstrapSvc = ZoneIdentityBootstrapService();
    if (!bootstrapSvc.isInitialized) return null;
    final bootstrap = bootstrapSvc.activeBootstrap;
    if (bootstrap == null) return null;
    final coordinator = P2pAkeCoordinator(
      identityLoader: _loadAkeIdentity,
      frameSender: _sendAkeFrame,
      quotaGate: (endpointId) =>
          _akeWiring.consumeHandshakeQuota(endpointId) ==
          P2pAkeRateDecision.attemptAllowed,
      keyMaterialListener: _onAkeKeyMaterial,
    );
    _akeCoordinator = coordinator;
    return coordinator;
  }

  /// Identidad para el AKE desde la FUNDACIÓN (single-source): contexto
  /// público + material del dispositivo primario (seeds ya en almacén seguro;
  /// el runtime usa los PARES en memoria — sin nueva superficie de secretos).
  Future<P2pAkeIdentityMaterial?> _loadAkeIdentity() async {
    try {
      final svc = ZoneIdentityBootstrapService();
      if (!svc.isInitialized) return null;
      final bootstrap = svc.activeBootstrap;
      if (bootstrap == null) return null;
      final context = svc.context;
      final material =
          await bootstrap.registry.loadDeviceKeyMaterial(context.deviceId);
      // ZONE-ID: verdad del servicio Zone; fallback al metadata de cuenta de
      // la fundación. Vacío ⇒ sin firma (el policy lo exigiría igual).
      var zoneId = _zoneIdService.zoneId ?? '';
      if (zoneId.isEmpty) {
        final account = await bootstrap.registry.loadAccountMetadata();
        zoneId = account?.zoneId ?? '';
      }
      return P2pAkeIdentityMaterial(
        zoneId: zoneId,
        accountId: context.accountId,
        deviceId: context.deviceId,
        identityKeyPair: material.signingKeyPair,
        encryptionKeyPair: material.encryptionKeyPair,
        encryptionKeyVersion: 1,
      );
    } catch (e) {
      _logger.debug('[NearbyService] Identidad AKE no disponible (fail-closed).');
      return null;
    }
  }

  Future<bool> _sendAkeFrame(
    String endpointId,
    Map<String, dynamic> frame,
  ) async {
    if (!_connectedEndpoints.contains(endpointId)) return false;
    try {
      await _nearby.sendBytesPayload(endpointId, utf8.encode(jsonEncode(frame)));
      return true;
    } catch (e) {
      _logger.debug('[NearbyService] Error enviando frame AKE: $e');
      return false;
    }
  }

  /// Material SETTLED: marca AKE completado (gate WI-2 autenticado para este
  /// endpoint) y actualiza la etiqueta honesta de UI. El material de sesión
  /// NO se guarda fuera de memoria viva (por diseño; ver coordinador).
  void _onAkeKeyMaterial(String endpointId, P2PSessionKeyMaterial material) {
    _akeWiring.markAkeCompleted(endpointId);
    _logger.debug(
      '[NearbyService] AKE completado (${material.transcriptHash.length}B '
      'transcript, firstContact=${material.firstContact}); material '
      'por-conexión en memoria; SKs legacy Z-212 intactos.',
    );
    final user = _discoveredUsers[endpointId];
    if (user != null) {
      // Anclaje OOB aún no implementado: primer contacto ⇒ sigue unverified
      // (honesto). Cuando exista tienda de anclas, no-firstContact ⇒ true.
      user.identityVerified = !material.firstContact;
      _emitDiscoveredUsers();
    }
  }

  Future<void> _startAkeHandshake(String endpointId) async {
    final coordinator = _ensureAkeCoordinator();
    if (coordinator == null) {
      _logger.debug(
        '[NearbyService] AKE no iniciable (bootstrap de identidad pendiente).',
      );
      return;
    }
    try {
      await coordinator.onConnected(endpointId);
    } on Object {
      _logger.debug('[NearbyService] AKE: error iniciando handshake.');
    }
  }

  Future<void> _handleAkeHelloFrame(
    String endpointId,
    Map<String, dynamic> clean,
  ) async {
    final coordinator = _ensureAkeCoordinator();
    if (coordinator == null) {
      _logger.debug('[NearbyService] AKE descartado: sin identidad lista.');
      return;
    }
    final outcome = await coordinator.onPeerHello(endpointId, clean);
    if (!outcome.accepted && outcome.rejection != null) {
      final reason = outcome.rejection!.reason.name;
      _logger.debug(
        '[NearbyService] AKE hello rechazado (fail-closed): $reason.',
      );
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      final String text;
      try {
        text = utf8.decode(payload.bytes!);
      } catch (e) {
        _logger.debug('[NearbyService] Payload no-UTF8 descartado: $e');
        return;
      }

      final dynamic decoded;
      try {
        decoded = jsonDecode(text);
      } catch (e) {
        // Z-212: fail-closed. Un payload no-JSON NUNCA se inyecta como mensaje
        // (el camino legado en claro permitía spoofing de remitente/contenido).
        _logger.debug('[NearbyService] Payload no-JSON descartado (fail-closed).');
        return;
      }
      if (decoded is! Map) {
        _logger.debug('[NearbyService] Payload JSON no-objeto descartado.');
        return;
      }
      final data = Map<String, dynamic>.from(decoded);
      final type = data['type'];

      // Z-004 WI-2/WI-6 (PHASE E/G): los frames AKE se despachan ANTES que
      // `profile_exchange`. Reglas:
      //  - forma gruesa fail-closed (validateAkeFrame) — nada malformado
      //    llega al registro;
      //  - rate-limit local por endpoint (WI-6) — intentos repetidos no
      //    consumen la radio;
      //  - registro de progreso hello/cert y DESPACHO REAL al coordinador
      //    AKE (WI-1/WI-4 locales): un `ake_hello` entra al handshake
      //    `ZONE-P2P-AKE-1`; un `ake_cert` (WI-8 prep) solo se registra.
      //    El AKE COMPLETO ya deriva material POR-CONEXIÓN en memoria; la
      //    demo física (H-01) sigue NOT RUN por separado.
      if (type is String && data['data'] is Map) {
        final akeData = Map<String, dynamic>.from(data['data'] as Map);
        if (type == kP2pAkeHelloType || type == kP2pAkeCertType) {
          final clean = _akeWiring.validateAkeFrame(
            type: type,
            data: akeData,
          );
          if (clean == null) {
            _logger.debug(
              '[NearbyService] Frame AKE malformado descartado ($type).',
            );
            return;
          }
          if (_akeWiring.consumeHandshakeQuota(endpointId) ==
              P2pAkeRateDecision.attemptDenied) {
            _logger.debug(
              '[NearbyService] Rate-limit WI-6 agotado para el endpoint; '
              'frame AKE descartado (WI-6).',
            );
            return;
          }
          _akeWiring.noteAkeFrameReceived(
            endpointId: endpointId,
            isHello: type == kP2pAkeHelloType,
          );
          if (type == kP2pAkeHelloType) {
            unawaited(_handleAkeHelloFrame(endpointId, clean));
          } else {
            _logger.debug(
              '[NearbyService] Frame AKE registrado ($type, WI-8 prep; '
              'el handshake completo vive en el coordinador AKE).',
            );
          }
          return;
        }
      }

      if (type == 'profile_exchange') {
        // PHASE 2.2.6 (§6): validar ANTES de tocar estado — identidad
        // canónica + cero claves secretas. Inválido ⇒ descartar.
        try {
          final clean = DiscoveryPayload.validateProfileExchange(data['data']);
          _handleProfileExchange(endpointId, clean);
        } on InvalidDiscoveryIdentityError {
          _logger.debug(
            '[NearbyService] profile_exchange inválido, descartado.',
          );
        }
      } else if (type == 'routing_table') {
        final routes = MeshPolicy.validateRoutingTable(data['data']);
        if (routes.isEmpty) {
          _logger.debug('[NearbyService] routing_table inválida, descartada.');
          return;
        }
        _handleRoutingTableUpdate(endpointId, routes);
      } else if (type == 'mesh_msg') {
        final packet = MeshPolicy.validateIncomingPacket(data);
        if (packet == null) {
          _logger.warning(
            '[NearbyService] mesh_msg inválido descartado de $endpointId',
          );
          return;
        }
        _handleMeshMessage(endpointId, packet);
      } else {
        _logger.debug('[NearbyService] Tipo de payload desconocido descartado.');
      }
    }
  }

  Future<void> _shareProfileP2P(String endpointId) async {
    final profile = await _zoneIdService.getMyProfile();
    if (profile == null) return;

    // Z-212: no difundir datos que el dueño marcó como privados. El perfil
    // propio se comparte por radio; la visibilidad debe aplicarse en origen.
    final avatarVisible = profile['avatar_is_public'] == true;
    final igVisible = profile['ig_visible'] == true;
    final fbVisible = profile['fb_visible'] == true;
    final tiktokVisible = profile['tiktok_visible'] == true;

    final exchangeData = {
      'type': 'profile_exchange',
      'data': {
        'id': profile['id'],
        'zone_id': profile['zone_id'],
        'display_name': profile['display_name'],
        'avatar_url': avatarVisible ? profile['avatar_url'] : null,
        'bio': profile['bio'],
        'instagram_handle': igVisible ? profile['instagram_handle'] : null,
        'facebook_handle': fbVisible ? profile['facebook_handle'] : null,
        'tiktok_handle': tiktokVisible ? profile['tiktok_handle'] : null,
        'publicKey': _security.publicBase64,
        'public_key': _security.publicBase64,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    };

    unawaited(sendMessage(endpointId, jsonEncode(exchangeData)));
  }

  void _handleProfileExchange(
    String endpointId,
    Map<String, dynamic> profileData,
  ) async {
    _logger.debug(
      '[NearbyService] Perfil P2P recibido de $endpointId: ${profileData['zone_id']}',
    );

    // PHASE 2.2.6 (frontera de identidad): enlazar endpoint→identidad ANTES
    // de derivar llaves, persistir o rutear. Falla cerrado si el handle no
    // es canónico (nunca entra a sk_*, Isar, routing ni UI como identidad).
    final boundZone = (profileData['zone_id'] ?? '').toString();
    try {
      _sessions.bindIdentity(endpointId, boundZone);
    } on InvalidDiscoveryIdentityError {
      _logger.debug(
        '[NearbyService] Intercambio P2P con identidad inválida, omitido.',
      );
      return;
    }

    // Derivación de llave de sesión si viene clave pública
    final remotePublicKey =
        (profileData['publicKey'] as String?) ??
        (profileData['public_key'] as String?);
    final remoteZoneId = profileData['zone_id'] as String?;

    // Z-004 WI-2 (PHASE E/G): gate del despachador. `profile_exchange`
    // SIN AKE completado en este endpoint NO alimenta la derivación de
    // llaves: marca 'unverified' (fallback propietario aprobado — NO es
    // descarte de conexión) y el bloque Z-212 completo se OMITE (ni
    // derivación ni conservación ni flush por esta vía falla cerrada).
    final akeGate = _akeWiring.gateProfileExchange(endpointId);
    var identityVerified = akeGate == P2pProfileExchangeGate.authenticatedPath;

    if (akeGate == P2pProfileExchangeGate.unverifiedFallback) {
      _logger.debug(
        '[NearbyService] WI-2: profile_exchange sin AKE completado para '
        '$endpointId — identidad "unverified"; derivación y gestión de '
        'llave de sesión OMITIDAS para este exchange.',
      );
    } else if (remotePublicKey != null && remoteZoneId != null) {
      _logger.debug('[NearbyService] Derivando llave de sesión P2P (AKE autenticado)...');
      try {
        // Z-212: NUNCA reemplazar una llave ya establecida por una clave que
        // llega sin prueba de posesión (mitiga key-substitution/MITM tras el
        // primer contacto). El primer contacto sigue siendo TOFU y está
        // documentado como riesgo Z-004 hasta integrar identidad firmada.
        final existingKey = await _security.getSessionKey(remoteZoneId);
        if (existingKey == null) {
          final sessionKey = await _security.deriveSessionKey(remotePublicKey);
          if (sessionKey != null) {
            await _security.saveSessionKey(remoteZoneId, sessionKey);
            _logger.debug(
              '[NearbyService] Llave de sesión guardada de forma segura.',
            );
          }
        } else {
          _logger.debug(
            '[NearbyService] Llave de sesión existente conservada para $remoteZoneId.',
          );
        }
        // Z-003 (FASE 1.4): al existir llave, descargar la cola fail-closed.
        final sessionKey = await _security.getSessionKey(remoteZoneId);
        if (sessionKey != null) {
          await _flushPendingMeshMessages(remoteZoneId);
        }
      } catch (e) {
        _logger.debug('[NearbyService] Error derivando llave P2P: $e');
      }
    }

    // Guardar en Isar (payload remoto validado; saveProfile valida id/fechas).
    try {
      await _isar.saveProfile(profileData);
    } catch (e) {
      _logger.debug('[NearbyService] Perfil P2P no persistido: $e');
    }

    // Registrar encuentro localmente (PHASE 2.2.3: clave canónica; sin
    // identidad verificable se omite fail-closed — además corrige el crash
    // potencial previo si `zone_id` venía nulo).
    final peerZoneId = profileData['zone_id'] as String?;
    final p2pEncounterKey = (peerZoneId == null || peerZoneId.isEmpty)
        ? null
        : await EncounterKey.tryCanonicalKey(
            myZone: _myZoneId,
            peerZone: peerZoneId,
            seenAt: DateTime.now(),
          );
    if (p2pEncounterKey == null) {
      _logger.debug('[NearbyService] Encuentro P2P omitido: identidad inválida.');
    } else {
      await _isar.saveEncounter(
        userId: _userId,
        otherZoneId: peerZoneId!,
        isSynced: _connectivity.hasRealInternet,
        encounterKey: p2pEncounterKey,
      );
    }

    // Actualizar UI si el usuario está en el radar
    if (_discoveredUsers.containsKey(endpointId)) {
      final user = _discoveredUsers[endpointId]!;
      user.userName =
          profileData['display_name'] ?? profileData['zone_id'] ?? 'Usuario';
      user.zoneId = profileData['zone_id'] ?? '';
      user.profile = profileData;
      // Z-004 WI-2: etiqueta honesta de verificación de identidad para UI
      // (true SOLO con AKE completado en este endpoint).
      user.identityVerified = identityVerified;

      // Guardar mapeo pseudonym→zoneId si el token es offline
      if (user.token.startsWith('OFFLINE:')) {
        final pseudonym = user.token.replaceFirst('OFFLINE:', '');
        await _savePseudonymMapping(pseudonym, profileData['zone_id']);
      }

      _emitDiscoveredUsers();
    }

    // Mesh: Añadir ruta directa a nuestra tabla
    _updateRoutingTable(profileData['zone_id'], endpointId, 1);
  }

  // ──────────────────────────────────────────────────────────────
  //  Mesh Routing Logic
  // ──────────────────────────────────────────────────────────────

  void _shareRoutingTable(String targetEndpointId) {
    // Compartir rutas conocidas (incluyéndonos a nosotros)
    final routes = <Map<String, dynamic>>[];

    // Ruta hacia mí mismo (distancia 0)
    routes.add({'zoneId': _myZoneId, 'distance': 0});

    // Otras rutas conocidas
    _routingTable.forEach((zoneId, route) {
      if (route.distance < _maxMeshHops) {
        routes.add({'zoneId': zoneId, 'distance': route.distance});
      }
    });

    unawaited(
      sendMessage(
        targetEndpointId,
        jsonEncode({'type': 'routing_table', 'data': routes}),
      ),
    );
  }

  void _handleRoutingTableUpdate(
    String fromEndpointId,
    List<MeshRouteHint> routes,
  ) {
    _logger.debug(
      '[NearbyService] Actualización de tabla Mesh desde $fromEndpointId',
    );
    for (final r in routes) {
      final zoneId = r.zoneId;
      final distance = r.distance;

      if (zoneId == _myZoneId) continue;
      if (distance + 1 > _maxMeshHops) continue;

      // Si es una ruta más corta o nueva, actualizar
      final existing = _routingTable[zoneId];
      if (existing == null || (distance + 1) < existing.distance) {
        _updateRoutingTable(zoneId, fromEndpointId, distance + 1);
      }
    }
  }

  void _updateRoutingTable(String zoneId, String nextHop, int distance) {
    // Anti-DoS: cota del estado de rutas; evicta la actualización más antigua.
    if (!_routingTable.containsKey(zoneId) &&
        _routingTable.length >= _maxRoutingTableEntries) {
      String? oldestKey;
      DateTime? oldestAt;
      _routingTable.forEach((key, route) {
        if (oldestAt == null || route.lastUpdate.isBefore(oldestAt!)) {
          oldestKey = key;
          oldestAt = route.lastUpdate;
        }
      });
      if (oldestKey != null) _routingTable.remove(oldestKey);
    }

    final route = MeshRoute()
      ..targetZoneId = zoneId
      ..nextHopEndpointId = nextHop
      ..distance = distance
      ..lastUpdate = DateTime.now();

    _routingTable[zoneId] = route;
    unawaited(_isar.updateRoute(zoneId, nextHop, distance));
    _logger.debug(
      '[NearbyService] Ruta Mesh actualizada: $zoneId vía $nextHop (saltos: $distance)',
    );
  }

  Future<void> sendMeshMessage(String targetZoneId, String message) async {
    final route = _routingTable[targetZoneId];

// Z-003 (FASE 1.4): fail-closed — NUNCA se envía texto en claro.
    // Si no hay llave de sesión o el cifrado falla, el mensaje se encola y se
    // reintenta al derivarse la llave (_handleProfileExchange → _flushPendingMeshMessages).
    final sessionKey = await _security.getSessionKey(targetZoneId);
    var encrypted = <String, dynamic>{};
    var encryptOk = false;
    if (sessionKey != null) {
      try {
        final sessionKeyBytes = base64Decode(sessionKey);
        final sharedSecret = SecretKey(sessionKeyBytes);
        encrypted =
            await _chatE2EE.encryptMessage(message, sharedSecret);
        encryptOk = true;
        _logger.debug(
          '[NearbyService] Mensaje Mesh cifrado para $targetZoneId',
        );
      } catch (e) {
        _logger.debug('[NearbyService] Error cifrando mensaje Mesh: $e');
      }
    }

    final decision = MeshPolicy.decideSend(
      hasSessionKey: sessionKey != null,
      encryptOk: encryptOk,
    );
    if (decision == MeshSendDecision.queueForKey) {
      _enqueueMeshMessage(targetZoneId, message);
      return;
    }

    final packet = MeshPolicy.ciphertextPacket(
      source: _myZoneId,
      target: targetZoneId,
      encryptedContent: encrypted['encrypted_content'] as String,
      nonce: encrypted['nonce'] as String,
      mac: encrypted['mac'] as String,
    );

    if (route != null && _isRouteActive(route)) {
      _logger.debug(
        '[NearbyService] Enviando mensaje Mesh a $targetZoneId vía ${route.nextHopEndpointId}',
      );
      unawaited(sendMessage(route.nextHopEndpointId, jsonEncode(packet)));
    } else {
      // Flood: Si no hay ruta, enviar a todos los vecinos
      _logger.debug(
        '[NearbyService] No hay ruta para $targetZoneId, inundando red...',
      );
      for (final endpoint in _connectedEndpoints) {
        unawaited(sendMessage(endpoint, jsonEncode(packet)));
      }
    }
  }

  /// Z-003 (FASE 1.4): encola un mensaje mesh pendiente de llave (fail-closed).
  /// Con tope de tamaño para evitar crecimiento ilimitado en memoria.
  void _enqueueMeshMessage(String targetZoneId, String message) {
    if (_pendingMeshMessages.length >= _maxPendingMeshMessages) {
      _pendingMeshMessages.removeAt(0);
    }
    _pendingMeshMessages.add(MeshPendingMessage(
      targetZoneId: targetZoneId,
      message: message,
      queuedAt: DateTime.now(),
    ));
    _meshStatusController.add(MeshStatusEvent(MeshStatusKind.queued, targetZoneId));
    _logger.debug(
      '[NearbyService] Mensaje Mesh ENCOLADO (fail-closed) para $targetZoneId — '
      'pendiente de llave de sesión',
    );
  }

  /// Z-003 (FASE 1.4): reintenta los mensajes pendientes hacia `targetZoneId`
  /// cuando ya existe una llave de sesión (hook desde `_handleProfileExchange`).
  Future<void> _flushPendingMeshMessages(String targetZoneId) async {
    final pending = _pendingMeshMessages
        .where((m) => m.targetZoneId == targetZoneId)
        .toList();
    if (pending.isEmpty) return;
    _pendingMeshMessages.removeWhere((m) => m.targetZoneId == targetZoneId);
    for (final item in pending) {
      await sendMeshMessage(item.targetZoneId, item.message);
    }
    _meshStatusController.add(MeshStatusEvent(MeshStatusKind.flushed, targetZoneId));
    _logger.debug(
      '[NearbyService] Cola mesh descargada para $targetZoneId '
      '(${pending.length} mensaje(s))',
    );
  }

  void _handleMeshMessage(String fromEndpointId, MeshPacket packet) async {
    // Z-212: el paquete ya pasó validación estricta (tipos, ZONE-IDs, UUID,
    // ciphertext acotado, hops). Aquí solo se aplica el contrato de relay.

    // Z-005 (FASE 1.6): dedup LRU+TTL — register() devuelve false si ya estaba
    // dentro de la ventana (duplicado); nunca borra todo el set.
    if (!_seenMessageIds.register(packet.msgId)) {
      _logger.debug(
        '[NearbyService] Mensaje Mesh duplicado ignorado: ${packet.msgId}',
      );
      return;
    }

    if (packet.target == _myZoneId) {
      // Validar si hay un match/permiso antes de procesar
      final profile = await _isar.getProfile(packet.source);
      if (profile != null) {
        _processIncomingMeshMessage(packet.source, packet, fromEndpointId);
      } else {
        _logger.debug(
          '[NearbyService] Mensaje Mesh ignorado: No hay perfil/match previo con ${packet.source}',
        );
      }
      return;
    }

    final hops = packet.hops + 1;
    if (hops >= _maxMeshHops) return;

    // Relay: reenviar el paquete reconstruido (nunca se muta el original).
    final relayPacket = {
      'type': 'mesh_msg',
      'source': packet.source,
      'target': packet.target,
      'msgId': packet.msgId,
      'text': packet.ciphertext,
      'nonce': packet.nonce,
      'mac': packet.mac,
      'hops': hops,
      'isEncrypted': true,
    };
    final route = _routingTable[packet.target];

    if (route != null && _isRouteActive(route)) {
      // Reenviar al siguiente salto conocido
      if (route.nextHopEndpointId != fromEndpointId) {
        unawaited(
          sendMessage(route.nextHopEndpointId, jsonEncode(relayPacket)),
        );
      }
    } else {
      // Flood relay: A todos excepto de donde vino
      for (final endpoint in _connectedEndpoints) {
        if (endpoint != fromEndpointId) {
          unawaited(sendMessage(endpoint, jsonEncode(relayPacket)));
        }
      }
    }
  }

  Future<void> _processIncomingMeshMessage(
    String sourceZoneId,
    MeshPacket packet,
    String fromEndpointId,
  ) async {
    var text = packet.ciphertext;
    final sessionKey = await _security.getSessionKey(sourceZoneId);
    if (sessionKey != null) {
      try {
        final sessionKeyBytes = base64Decode(sessionKey);
        final sharedSecret = SecretKey(sessionKeyBytes);
        text = await _chatE2EE.decryptMessage(
          text,
          packet.nonce,
          packet.mac,
          sharedSecret,
        );
        _logger.debug(
          '[NearbyService] Mensaje Mesh descifrado de $sourceZoneId',
        );
      } catch (e) {
        text =
            '[Error de descifrado: la llave de sesión podría ser inválida]';
        _logger.debug('[NearbyService] Error descifrando mensaje Mesh: $e');
      }
    } else {
      text = '[Mensaje cifrado recibido pero no se tiene la llave de sesión]';
    }

    _logger.debug(
      '[NearbyService] Mensaje Mesh procesado de $sourceZoneId: $text',
    );
    _incomingMessagesController.add(
      NearbyMessage(
        fromEndpointId: fromEndpointId,
        text: text,
        sourceZoneId: sourceZoneId,
      ),
    );
  }

  /// Verifica si un usuario está disponible para chat P2P directo.
  bool isPeerConnected(String zoneId) {
    final route = _routingTable[zoneId];
    return route != null && route.distance == 1 && _isRouteActive(route);
  }

  /// Verifica si un usuario es alcanzable vía Mesh.
  bool isPeerReachable(String zoneId) {
    final route = _routingTable[zoneId];
    return route != null && _isRouteActive(route);
  }

  /// Carga usuarios alcanzables por rutas mesh recientes al radar.
  Future<void> _discoverMeshUsers() async {
    try {
      _logger.debug(
        '[NearbyService] Descubriendo usuarios vía mesh routing...',
      );

      for (final routeEntry in _routingTable.entries) {
        final zoneId = routeEntry.key;
        final route = routeEntry.value;

        if (zoneId == _myZoneId) continue;
        if (!_isRouteActive(route)) continue;

        // Si ya está presente (por Nearby directo o caché), solo actualizar conexión
        final existing = _discoveredUsers.values.firstWhere(
          (u) => u.zoneId == zoneId,
          orElse: () => NearbyUser(endpointId: '', token: ''),
        );
        if (existing.endpointId.isNotEmpty) {
          // Actualizar estado de conexión si cambió
          existing.isConnected = route.distance == 1;
          continue;
        }

        final profile = await _isar.getProfile(zoneId);
        if (profile != null) {
          final meshEndpointId = 'MESH:$zoneId';
          _discoveredUsers[meshEndpointId] = NearbyUser(
            endpointId: meshEndpointId,
            token: 'MESH:$zoneId',
            userName: profile.displayName ?? zoneId,
            zoneId: zoneId,
            isConnected: route.distance == 1,
            distanceMeters: null,
            profile: {
              'id': profile.userId,
              'zone_id': profile.zoneId,
              'display_name': profile.displayName,
              'avatar_url': profile.avatarUrl,
              'publicKey': profile.publicKey,
              'public_key': profile.publicKey,
            },
          );
          _logger.debug(
            '[NearbyService] Usuario mesh agregado al radar: $zoneId (saltos: ${route.distance})',
          );
        }
      }

      _emitDiscoveredUsers();
    } catch (e) {
      _logger.debug('[NearbyService] Error descubriendo usuarios mesh: $e');
    }
  }

  void _onPayloadTransferUpdate(
    String endpointId,
    PayloadTransferUpdate update,
  ) {}

  // ──────────────────────────────────────────────────────────────
  //  STRESS TESTING & SIMULATION
  // ──────────────────────────────────────────────────────────────

  /// Actualiza perfiles desde Supabase sin agregar usuarios fuera de rango al radar.
  Future<void> _discoverGlobalUsers() async {
    try {
      _logger.debug(
        '[NearbyService] Iniciando descubrimiento global de usuarios activos...',
      );
      final activeUsers = await _supabaseService.getActiveUsersForRadar();

      for (final userData in activeUsers) {
        final zoneId = userData['zone_id'] as String?;
        final userId = userData['id'] as String?;

        if (zoneId == null || userId == null) continue;
        if (zoneId == _myZoneId || userId == _userId) continue;
        if (_blockedUserIds.contains(userId)) continue;

        // Persistir en caché local siempre
        await _isar.saveProfile(userData);

        // Si el usuario ya está en el radar por Nearby o mesh, actualizar su perfil.
        bool alreadyInRadar = false;
        for (final discovered in _discoveredUsers.values) {
          if (discovered.zoneId == zoneId) {
            discovered.userName = userData['display_name'] as String? ?? zoneId;
            discovered.profile = userData;
            alreadyInRadar = true;
            break;
          }
        }

        if (!alreadyInRadar) {
          _logger.debug(
            '[NearbyService] Perfil global cacheado, esperando detecciÃ³n BLE/Nearby: $zoneId',
          );
        }
      }

      _emitDiscoveredUsers();
      _logger.debug(
        '[NearbyService] CachÃ© global actualizada. Usuarios visibles: ${_discoveredUsers.length}',
      );
    } catch (e) {
      _logger.debug('[NearbyService] Error en descubrimiento global: $e');
    }
  }

  void _emitDiscoveredUsers() {
    if (!_discoveredUsersController.isClosed) {
      _discoveredUsersController.add(discoveredUsers);
    }
  }

  void dispose() {
    unawaited(stopRadar());
    if (_lifecycleObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleObserverRegistered = false;
    }
    _discoveredUsersController.close();
    _incomingMessagesController.close();
    _meshStatusController.close();
  }
}
