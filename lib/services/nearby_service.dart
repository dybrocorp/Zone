import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'notification_service.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/radar_config.dart';
import 'ble_proximity_service.dart';
import 'premium_service.dart';
import 'zone_id_service.dart';
import 'isar_service.dart';
import 'connectivity_service.dart';
import 'p2p_security_service.dart';
import 'chat_e2ee_service.dart';
import 'supabase_service.dart';
import 'package:cryptography/cryptography.dart';
import '../models/isar_models.dart';
import 'logger_service.dart';

/// Modelo de usuario descubierto por Nearby Connections.
class NearbyUser {
  final String endpointId;
  final String token; // Token efímero recibido
  String userName; // Resuelto desde Supabase
  String zoneId; // ZONE-ID real resuelto
  bool isConnected;
  double? distanceMeters; // Estimado por RSSI BLE
  Map<String, dynamic>? profile; // Perfil completo de Supabase

  NearbyUser({
    required this.endpointId,
    required this.token,
    this.userName = '...',
    this.zoneId = '',
    this.isConnected = false,
    this.distanceMeters,
    this.profile,
  });
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

  final Map<String, dynamic> _pendingConnections = {};
  final Set<String> _connectedEndpoints = {};
  final Set<String> _resolvingEndpoints = {};

  // Grace Period: Evita que los usuarios desaparezcan inmediatamente en reinicios de ciclo
  final Map<String, Timer> _lostEndpointsGraceTimers = {};

  // Mesh Routing Table: Map<ZoneId, MeshRoute>
  final Map<String, MeshRoute> _routingTable = {};
  static const int _maxMeshHops = 5;

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
        // Fallback Offline: Usar ZoneID directamente si no hay internet
        _currentToken = 'OFFLINE:$_myZoneId';
        _logger.debug(
          '[NearbyService] Advertencia: Usando token OFFLINE ($_currentToken)',
        );
      }
    } catch (e) {
      _currentToken = 'OFFLINE:$_myZoneId';
      _logger.debug(
        '[NearbyService] Error renovando token, usando fallback OFFLINE: $e',
      );
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
      return false;
    }

    _scanCycleTimer?.cancel();
    _tokenRefreshTimer?.cancel();
    _globalDiscoveryTimer?.cancel();

    // Añadir un pequeño jitter aleatorio para evitar colisiones de descubrimiento bilateral
    final jitter = (DateTime.now().millisecondsSinceEpoch % 800);
    await Future.delayed(Duration(milliseconds: jitter));

    if (!_stealthMode) {
      await _startAdvertising();
    } else {
      await _stopAdvertising();
      _logger.debug(
        '[NearbyService] Modo timidez: solo descubrimiento, sin anunciar',
      );
    }

    // Discovery secuencial con retraso
    await Future.delayed(const Duration(milliseconds: 300));
    await _startDiscovery();
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

    return true;
  }

  Future<void> stopRadar() async {
    _isRadarIntendedActive = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('radar_active', false);

    _scanCycleTimer?.cancel();
    _tokenRefreshTimer?.cancel();
    _globalDiscoveryTimer?.cancel();
    await _stopAdvertising();
    await _stopDiscovery();
    _bleProximity.stopScanning();
    for (final timer in _lostEndpointsGraceTimers.values) {
      timer.cancel();
    }
    _lostEndpointsGraceTimers.clear();
    _discoveredUsers.clear();
    _resolvingEndpoints.clear();
    _emitDiscoveredUsers();
  }

  void _resumeScanning() {
    if (!_isRadarIntendedActive) return;
    startRadar();
  }

  Future<void> _startAdvertising() async {
    if (_stealthMode || !_hasValidToken) return;
    if (_isAdvertising) {
      await _stopAdvertising();
    }
    try {
      await _nearby.startAdvertising(
        _currentToken,
        _strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
      _isAdvertising = true;
    } catch (e) {
      _logger.debug('[NearbyService] Error al iniciar advertising: $e');
      _isAdvertising = false;
    }
  }

  Future<void> _startDiscovery() async {
    if (!_hasValidToken) return;
    if (_isDiscovering) {
      await _stopDiscovery();
    }
    try {
      await _nearby.startDiscovery(
        _currentToken,
        _strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: _serviceId,
      );
      _isDiscovering = true;
    } catch (e) {
      _logger.debug('[NearbyService] Error al iniciar discovery: $e');
      _isDiscovering = false;
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
    if (receivedToken.isEmpty || receivedToken == _invalidToken) return;

    // Si estaba en el periodo de gracia para ser eliminado, cancelar el timer
    _lostEndpointsGraceTimers[id]?.cancel();
    _lostEndpointsGraceTimers.remove(id);

    if (!_bleProximity.isTokenWithinRadius(
      receivedToken,
      _discoveryRadiusMeters,
    )) {
      return;
    }

    // Cuando Nearby encuentra un dispositivo activo, eliminar entradas mesh
    // para ese mismo usuario y evitar duplicados.
    if (receivedToken.startsWith('OFFLINE:')) {
      final zoneId = receivedToken.replaceFirst('OFFLINE:', '');
      _discoveredUsers.remove('MESH:$zoneId');
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

      // 1. Manejo de tokens Offline directo
      if (token.startsWith('OFFLINE:')) {
        resolvedZoneId = token.replaceFirst('OFFLINE:', '');
        _logger.debug(
          '[NearbyService] Token Offline detectado para $resolvedZoneId',
        );
        // Buscar INMEDIATAMENTE en Isar para resolución bilateral rápida
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

        // Sin perfil alguno: mostrar como usuario detectado pendiente de intercambio P2P
        if (profile == null && _discoveredUsers.containsKey(endpointId)) {
          final user = _discoveredUsers[endpointId]!;
          user.userName = 'Usuario Cercano';
          user.zoneId = token;
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
      user.zoneId = profile['zone_id'] ?? '';
      user.profile = profile;

      _discoveredUsers[endpointId] = user;
      _resolvingEndpoints.remove(endpointId);

      if (_isAppMinimized && !_notifiedUserIds.contains(user.zoneId)) {
        _notifiedUserIds.add(user.zoneId);
        NotificationService().showDiscoveryNotification(user.userName);
      }

      _emitDiscoveredUsers();

      if (user.zoneId.isNotEmpty) {
        if (_connectivity.hasRealInternet) {
          await _supabaseService.registerEncounter(_userId, user.zoneId);
        }
        await _isar.saveEncounter(
          userId: _userId,
          otherZoneId: user.zoneId,
          isSynced: _connectivity.hasRealInternet,
        );
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

    // Iniciar periodo de gracia de 10 segundos antes de eliminar definitivamente
    _lostEndpointsGraceTimers[id]?.cancel();
    _lostEndpointsGraceTimers[id] = Timer(const Duration(seconds: 10), () {
      _discoveredUsers.remove(id);
      _resolvingEndpoints.remove(id);
      _lostEndpointsGraceTimers.remove(id);
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
      _pendingConnections.remove(id);
    }
  }

  void _onDisconnected(String id) {
    _connectedEndpoints.remove(id);
    _pendingConnections.remove(id);
    if (_discoveredUsers.containsKey(id)) {
      _discoveredUsers[id]!.isConnected = false;
      _emitDiscoveredUsers();
    }
  }

  Future<void> requestConnection(String endpointId) async {
    if (!_hasValidToken) return;
    try {
      await _nearby.requestConnection(
        _currentToken,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
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

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      final text = utf8.decode(payload.bytes!);

      try {
        final Map<String, dynamic> data = jsonDecode(text);
        final type = data['type'];

        if (type == 'profile_exchange') {
          _handleProfileExchange(endpointId, data['data']);
        } else if (type == 'routing_table') {
          _handleRoutingTableUpdate(endpointId, data['data']);
        } else if (type == 'mesh_msg') {
          _handleMeshMessage(endpointId, data);
        }
      } catch (e) {
        // Tratar como mensaje directo legado o ignorar si no es JSON válido
        _incomingMessagesController.add(
          NearbyMessage(fromEndpointId: endpointId, text: text),
        );
      }
    }
  }

  Future<void> _shareProfileP2P(String endpointId) async {
    final profile = await _zoneIdService.getMyProfile();
    if (profile == null) return;

    final exchangeData = {
      'type': 'profile_exchange',
      'data': {
        'id': profile['id'],
        'zone_id': profile['zone_id'],
        'display_name': profile['display_name'],
        'avatar_url': profile['avatar_url'],
        'bio': profile['bio'],
        'instagram_handle': profile['instagram_handle'],
        'facebook_handle': profile['facebook_handle'],
        'tiktok_handle': profile['tiktok_handle'],
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

    // Derivación de llave de sesión si viene clave pública
    final remotePublicKey =
        (profileData['publicKey'] as String?) ??
        (profileData['public_key'] as String?);
    if (remotePublicKey != null) {
      _logger.debug('[NearbyService] Derivando llave de sesión P2P...');
      final sessionKey = await _security.deriveSessionKey(remotePublicKey);
      if (sessionKey != null) {
        profileData['sessionKey'] = sessionKey;
        _logger.debug('[NearbyService] Llave de sesión establecida con éxito.');
      }
    }

    // Guardar en Isar
    await _isar.saveProfile(profileData);

    // Registrar encuentro localmente
    await _isar.saveEncounter(
      userId: _userId,
      otherZoneId: profileData['zone_id'],
      isSynced: _connectivity.hasRealInternet,
    );

    // Actualizar UI si el usuario está en el radar
    if (_discoveredUsers.containsKey(endpointId)) {
      final user = _discoveredUsers[endpointId]!;
      user.userName =
          profileData['display_name'] ?? profileData['zone_id'] ?? 'Usuario';
      user.zoneId = profileData['zone_id'] ?? '';
      user.profile = profileData;
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

  void _handleRoutingTableUpdate(String fromEndpointId, List<dynamic> routes) {
    _logger.debug(
      '[NearbyService] Actualización de tabla Mesh desde $fromEndpointId',
    );
    for (final r in routes) {
      final zoneId = r['zoneId'] as String;
      final distance = r['distance'] as int;

      if (zoneId == _myZoneId) continue;

      // Si es una ruta más corta o nueva, actualizar
      final existing = _routingTable[zoneId];
      if (existing == null || (distance + 1) < existing.distance) {
        _updateRoutingTable(zoneId, fromEndpointId, distance + 1);
      }
    }
  }

  void _updateRoutingTable(String zoneId, String nextHop, int distance) {
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
    final profile = await _isar.getProfile(targetZoneId);

    Map<String, dynamic> packet = {
      'type': 'mesh_msg',
      'source': _myZoneId,
      'target': targetZoneId,
      'msgId': DateTime.now().millisecondsSinceEpoch.toString(),
      'text': message,
      'hops': 0,
      'isEncrypted': false,
    };

    // Intentar cifrar si tenemos llave de sesión
    if (profile?.sessionKey != null) {
      try {
        final sessionKeyBytes = base64Decode(profile!.sessionKey!);
        final sharedSecret = SecretKey(sessionKeyBytes);
        final encrypted = await _chatE2EE.encryptMessage(message, sharedSecret);

        packet['text'] = encrypted['encrypted_content'];
        packet['nonce'] = encrypted['nonce'];
        packet['mac'] = encrypted['mac'];
        packet['isEncrypted'] = true;
        _logger.debug(
          '[NearbyService] Mensaje Mesh cifrado para $targetZoneId',
        );
      } catch (e) {
        _logger.debug('[NearbyService] Error cifrando mensaje Mesh: $e');
      }
    }

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

  void _handleMeshMessage(
    String fromEndpointId,
    Map<String, dynamic> packet,
  ) async {
    final target = packet['target'] as String;
    final source = packet['source'] as String;
    final hops = (packet['hops'] as int) + 1;

    if (target == _myZoneId) {
      // Validar si hay un match/permiso antes de procesar
      final profile = await _isar.getProfile(source);
      if (profile != null) {
        _processIncomingMeshMessage(source, packet, fromEndpointId);
      } else {
        _logger.debug(
          '[NearbyService] Mensaje Mesh ignorado: No hay perfil/match previo con $source',
        );
      }
      return;
    }

    if (hops >= _maxMeshHops) return;

    // Relay: Reenviar mensaje
    packet['hops'] = hops;
    final route = _routingTable[target];

    if (route != null && _isRouteActive(route)) {
      // Reenviar al siguiente salto conocido
      if (route.nextHopEndpointId != fromEndpointId) {
        unawaited(sendMessage(route.nextHopEndpointId, jsonEncode(packet)));
      }
    } else {
      // Flood relay: A todos excepto de donde vino
      for (final endpoint in _connectedEndpoints) {
        if (endpoint != fromEndpointId) {
          unawaited(sendMessage(endpoint, jsonEncode(packet)));
        }
      }
    }
  }

  Future<void> _processIncomingMeshMessage(
    String sourceZoneId,
    Map<String, dynamic> packet,
    String fromEndpointId,
  ) async {
    String text = packet['text'] as String;
    final isEncrypted = packet['isEncrypted'] as bool? ?? false;

    if (isEncrypted) {
      final profile = await _isar.getProfile(sourceZoneId);
      if (profile?.sessionKey != null) {
        try {
          final sessionKeyBytes = base64Decode(profile!.sessionKey!);
          final sharedSecret = SecretKey(sessionKeyBytes);
          text = await _chatE2EE.decryptMessage(
            text,
            packet['nonce'] as String,
            packet['mac'] as String,
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

  void simulateMeshTraffic(int messageCount) {
    _logger.debug(
      '[NearbyService] Iniciando simulacion de estres: $messageCount mensajes...',
    );
    for (var i = 0; i < messageCount; i++) {
      final mockPacket = {
        'type': 'mesh_msg',
        'source': 'MOCK-USER-$i',
        'target': _myZoneId,
        'msgId': 'mock-$i-${DateTime.now().millisecondsSinceEpoch}',
        'text': 'Mensaje de prueba numero $i - Malla de seguridad activa.',
        'hops': 1,
        'isEncrypted': false,
      };

      Timer(Duration(milliseconds: i * 50), () {
        _handleMeshMessage('MOCK-ENDPOINT-$i', mockPacket);
      });
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
  }
}
