import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/radar_config.dart';
import 'ble_proximity_service.dart';
import 'premium_service.dart';
import 'supabase_service.dart';
import 'zone_id_service.dart';

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
  final String text;
  NearbyMessage({required this.fromEndpointId, required this.text});
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
  bool _isRadarIntendedActive = false; // Nueva bandera para persistir el estado deseado
  bool _lifecycleObserverRegistered = false;
  bool get isRadarActive => _isRadarIntendedActive;

  Timer? _scanCycleTimer;
  Timer? _tokenRefreshTimer;

  final Map<String, NearbyUser> _discoveredUsers = {};
  final _discoveredUsersController = StreamController<List<NearbyUser>>.broadcast();
  Stream<List<NearbyUser>> get discoveredUsersStream => _discoveredUsersController.stream;
  List<NearbyUser> get discoveredUsers => _discoveredUsers.values.toList();

  final _incomingMessagesController = StreamController<NearbyMessage>.broadcast();
  Stream<NearbyMessage> get incomingMessagesStream => _incomingMessagesController.stream;

  final Map<String, dynamic> _pendingConnections = {};
  final Set<String> _connectedEndpoints = {};
  final Set<String> _resolvingEndpoints = {};

  // ──────────────────────────────────────────────────────────────
  //  Inicialización
  // ──────────────────────────────────────────────────────────────

  Future<void> initialize(String userId) async {
    if (userId.isEmpty) {
      print('[NearbyService] Error: Intentando inicializar con userId vacío');
      return;
    }
    _userId = userId;
    _ensureLifecycleObserver();
    await _loadUserContext();
    await _refreshToken();
  }

  Future<void> _loadUserContext() async {
    _myZoneId = _zoneIdService.zoneId ?? '';
    _blockedUserIds = await _supabaseService.getBlockedUserIds(_userId);
    final profile = await _zoneIdService.getMyProfile();
    _stealthMode = profile?['stealth_mode'] == true;
    _myZoneId = profile?['zone_id'] as String? ?? _myZoneId;
    await _loadDiscoveryRadius();
    
    // Cargar estado del radar
    final prefs = await SharedPreferences.getInstance();
    _isRadarIntendedActive = prefs.getBool('radar_active') ?? false;
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
    _discoveryRadiusMeters = RadarConfig.effectiveRadius(meters, isPremium: isPremium);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(RadarConfig.prefsDiscoveryRadiusKey, _discoveryRadiusMeters);
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
        print('[NearbyService] Token BT renovado');
      } else {
        print('[NearbyService] Advertencia: No se pudo generar token BT');
      }
    } catch (e) {
      print('[NearbyService] Error renovando token: $e');
    }
  }

  bool get _hasValidToken =>
      _currentToken.isNotEmpty && _currentToken != _invalidToken;

  // ──────────────────────────────────────────────────────────────
  //  AppLifecycle — pausa en background (ahorra batería)
  // ──────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _pauseScanning();
    } else if (state == AppLifecycleState.resumed) {
      _resumeScanning();
    }
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
      print('[NearbyService] No se puede iniciar radar: token BT inválido');
      return false;
    }

    _scanCycleTimer?.cancel();
    _tokenRefreshTimer?.cancel();

    if (!_stealthMode) {
      await _startAdvertising();
    } else {
      await _stopAdvertising();
      print('[NearbyService] Modo timidez: solo descubrimiento, sin anunciar');
    }
    await _startDiscovery();
    await _bleProximity.startScanning();

    _scanCycleTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_isDiscovering) {
        print('[NearbyService] Reinicio periódico de discovery (optimizando visibilidad)');
        await _nearby.stopDiscovery();
        _isDiscovering = false;
        await Future.delayed(const Duration(milliseconds: 200));
        await _startDiscovery();
      }
    });

    _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 4), (_) async {
      await _refreshToken();
      if (!_hasValidToken) return;
      if (_stealthMode) return;
      if (_isAdvertising) {
        await _stopAdvertising();
        await _startAdvertising();
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
    await _stopAdvertising();
    await _stopDiscovery();
    _bleProximity.stopScanning();
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
      print('[NearbyService] Error al iniciar advertising: $e');
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
      print('[NearbyService] Error al iniciar discovery: $e');
      _isDiscovering = false;
    }
  }

  Future<void> _stopAdvertising() async {
    if (!_isAdvertising) return;
    try {
      await _nearby.stopAdvertising();
    } catch (e) {
      print('[NearbyService] Error al detener advertising: $e');
    }
    _isAdvertising = false;
  }

  Future<void> _stopDiscovery() async {
    if (!_isDiscovering) return;
    try {
      await _nearby.stopDiscovery();
    } catch (e) {
      print('[NearbyService] Error al detener discovery: $e');
    }
    _isDiscovering = false;
  }

  // ──────────────────────────────────────────────────────────────
  //  Discovery — resuelve token → perfil via Supabase
  // ──────────────────────────────────────────────────────────────

  void _onEndpointFound(String id, String receivedToken, String serviceId) {
    if (receivedToken.isEmpty || receivedToken == _invalidToken) return;

    if (!_bleProximity.isTokenWithinRadius(receivedToken, _discoveryRadiusMeters)) {
      return;
    }

    if (!_discoveredUsers.containsKey(id)) {
      _discoveredUsers[id] = NearbyUser(
        endpointId: id,
        token: receivedToken,
        userName: 'Cargando...',
      );
      _emitDiscoveredUsers();
    }

    _resolveTokenAsync(id, receivedToken);
  }

  Future<void> _resolveTokenAsync(String endpointId, String token) async {
    if (_resolvingEndpoints.contains(endpointId)) return;
    _resolvingEndpoints.add(endpointId);

    try {
      Map<String, dynamic>? profile;
      for (var attempt = 0; attempt < 3; attempt++) {
        profile = await _supabaseService.resolveToken(token);
        if (profile != null) break;
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }

      if (!_discoveredUsers.containsKey(endpointId)) return;

      if (profile == null) {
        _discoveredUsers.remove(endpointId);
        _emitDiscoveredUsers();
        return;
      }

      final profileId = profile['id'] as String?;
      final profileZoneId = profile['zone_id'] as String?;

      if (profileId == _userId ||
          (profileZoneId != null &&
              profileZoneId.isNotEmpty &&
              profileZoneId == _myZoneId)) {
        _discoveredUsers.remove(endpointId);
        _emitDiscoveredUsers();
        return;
      }

      if (profileId != null && _blockedUserIds.contains(profileId)) {
        _discoveredUsers.remove(endpointId);
        _emitDiscoveredUsers();
        return;
      }

      final distance = _bleProximity.distanceMetersForToken(token);
      
      // Si tenemos distancia, validamos que esté en el radio. 
      // Si es null, permitimos que aparezca (algunos dispositivos no reportan RSSI rápido)
      if (distance != null && !RadarConfig.isDistanceWithinRadius(distance, _discoveryRadiusMeters)) {
        print('[NearbyService] Usuario ${profile['zone_id']} fuera de radio (${distance.toStringAsFixed(1)}m > ${_discoveryRadiusMeters}m)');
        _discoveredUsers.remove(endpointId);
        _emitDiscoveredUsers();
        return;
      }

      _discoveredUsers[endpointId]!
        ..userName = profile['display_name'] ?? profile['zone_id'] ?? 'ZONE-???'
        ..zoneId = profile['zone_id'] ?? ''
        ..distanceMeters = distance
        ..profile = profile;
      _emitDiscoveredUsers();

      if (_userId.isNotEmpty && profileZoneId != null && profileZoneId.isNotEmpty) {
        await _supabaseService.registerEncounter(_userId, profileZoneId);
      }
    } catch (e) {
      print('[NearbyService] Error al resolver token: $e');
      _discoveredUsers.remove(endpointId);
      _emitDiscoveredUsers();
    } finally {
      _resolvingEndpoints.remove(endpointId);
    }
  }

  void _onEndpointLost(String? id) {
    if (id == null) return;
    _discoveredUsers.remove(id);
    _resolvingEndpoints.remove(id);
    _emitDiscoveredUsers();
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
      print('[NearbyService] Error al solicitar conexión: $e');
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
      print('[NearbyService] Error al aceptar conexión: $e');
    }
  }

  Future<void> rejectConnection(String endpointId) async {
    try {
      await _nearby.rejectConnection(endpointId);
      _pendingConnections.remove(endpointId);
    } catch (e) {
      print('[NearbyService] Error al rechazar conexión: $e');
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
      print('[NearbyService] Error al enviar mensaje: $e');
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      final text = utf8.decode(payload.bytes!);
      _incomingMessagesController.add(
        NearbyMessage(fromEndpointId: endpointId, text: text),
      );
    }
  }

  void _onPayloadTransferUpdate(String endpointId, PayloadTransferUpdate update) {}

  void _emitDiscoveredUsers() {
    if (!_discoveredUsersController.isClosed) {
      _discoveredUsersController.add(discoveredUsers);
    }
  }

  void dispose() {
    stopRadar();
    if (_lifecycleObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleObserverRegistered = false;
    }
    _discoveredUsersController.close();
    _incomingMessagesController.close();
  }
}
