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
  NearbyMessage({required this.fromEndpointId, required this.text, this.sourceZoneId});
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
  bool _isAppMinimized = false; // Bandera para saber si estamos en segundo plano
  bool get isRadarActive => _isRadarIntendedActive;

  Timer? _scanCycleTimer;
  Timer? _tokenRefreshTimer;

  final Map<String, NearbyUser> _discoveredUsers = {};
  final Set<String> _notifiedUserIds = {}; // Para no spamear notificaciones del mismo usuario
  final _discoveredUsersController = StreamController<List<NearbyUser>>.broadcast();
  Stream<List<NearbyUser>> get discoveredUsersStream => _discoveredUsersController.stream;
  List<NearbyUser> get discoveredUsers => _discoveredUsers.values.toList();

  final _incomingMessagesController = StreamController<NearbyMessage>.broadcast();
  Stream<NearbyMessage> get incomingMessagesStream => _incomingMessagesController.stream;

  final Map<String, dynamic> _pendingConnections = {};
  final Set<String> _connectedEndpoints = {};
  final Set<String> _resolvingEndpoints = {};
  
  // Grace Period: Evita que los usuarios desaparezcan inmediatamente en reinicios de ciclo
  final Map<String, Timer> _lostEndpointsGraceTimers = {};
  
  // Mesh Routing Table: Map<ZoneId, MeshRoute>
  final Map<String, MeshRoute> _routingTable = {};
  static const int _maxMeshHops = 5;

  int get routingTableSize => _routingTable.length;

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
    await _connectivity.initialize();
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
    if (state == AppLifecycleState.paused) {
      _isAppMinimized = true;
      // No pausar el radar si _isRadarIntendedActive == true.
      if (!_isRadarIntendedActive) {
        _pauseScanning();
      }
    } else if (state == AppLifecycleState.detached) {
      _pauseScanning();
    } else if (state == AppLifecycleState.resumed) {
      _isAppMinimized = false;
      if (_isRadarIntendedActive) {
        _resumeScanning();
      }
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

    // Añadir un pequeño jitter aleatorio para evitar colisiones de descubrimiento bilateral
    final jitter = (DateTime.now().millisecondsSinceEpoch % 800);
    await Future.delayed(Duration(milliseconds: jitter));

    if (!_stealthMode) {
      await _startAdvertising();
    } else {
      await _stopAdvertising();
      print('[NearbyService] Modo timidez: solo descubrimiento, sin anunciar');
    }
    
    // Discovery secuencial con retraso
    await Future.delayed(const Duration(milliseconds: 300));
    await _startDiscovery();
    await _bleProximity.startScanning();

    // Ciclo de reinicio más inteligente (cada 45s en lugar de 30s para dar estabilidad)
    _scanCycleTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      if (_isDiscovering) {
        print('[NearbyService] Reinicio estratégico de discovery...');
        await _nearby.stopDiscovery();
        _isDiscovering = false;
        await Future.delayed(const Duration(milliseconds: 1500)); // Más tiempo para que el stack BT se limpie
        if (_isRadarIntendedActive) await _startDiscovery();
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

    // Si estaba en el periodo de gracia para ser eliminado, cancelar el timer
    _lostEndpointsGraceTimers[id]?.cancel();
    _lostEndpointsGraceTimers.remove(id);

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

      final user = _discoveredUsers[endpointId]!;
      if (profile != null) {
        user.userName = profile['display_name'] ?? 'Usuario';
        user.zoneId = profile['zone_id'] ?? '';
        user.profile = profile;
      }

      _discoveredUsers[endpointId] = user;
      _resolvingEndpoints.remove(endpointId);
      
      // Notificación en segundo plano si es nuevo
      if (_isAppMinimized && !_notifiedUserIds.contains(user.zoneId)) {
        _notifiedUserIds.add(user.zoneId);
        NotificationService().showDiscoveryNotification(user.userName);
      }
      
      _emitDiscoveredUsers();
      
      // Registrar el encuentro en base de datos de manera silente
      if (user.zoneId.isNotEmpty) {
        _supabaseService.registerEncounter(_userId, user.zoneId);
        _isar.saveEncounter(userId: _userId, otherZoneId: user.zoneId, isSynced: _connectivity.isOnline);
        _isar.saveProfile(profile);
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
    
    // Iniciar periodo de gracia de 10 segundos antes de eliminar definitivamente
    _lostEndpointsGraceTimers[id]?.cancel();
    _lostEndpointsGraceTimers[id] = Timer(const Duration(seconds: 10), () {
      _discoveredUsers.remove(id);
      _resolvingEndpoints.remove(id);
      _lostEndpointsGraceTimers.remove(id);
      _emitDiscoveredUsers();
      print('[NearbyService] Endpoint $id eliminado definitivamente tras periodo de gracia.');
    });
    
    print('[NearbyService] Endpoint $id perdido. Entrando en periodo de gracia de 10s...');
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
        _shareProfileP2P(id);
        
        // Mesh: Compartir nuestra tabla de rutas
        _shareRoutingTable(id);
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
        'publicKey': _security.publicBase64,
        'updatedAt': DateTime.now().toIso8601String(),
      }
    };

    sendMessage(endpointId, jsonEncode(exchangeData));
  }

  void _handleProfileExchange(String endpointId, Map<String, dynamic> profileData) async {
    print('[NearbyService] Perfil P2P recibido de $endpointId: ${profileData['zone_id']}');
    
    // Derivación de llave de sesión si viene clave pública
    final remotePublicKey = profileData['publicKey'] as String?;
    if (remotePublicKey != null) {
      print('[NearbyService] Derivando llave de sesión P2P...');
      final sessionKey = await _security.deriveSessionKey(remotePublicKey);
      if (sessionKey != null) {
        profileData['sessionKey'] = sessionKey;
        print('[NearbyService] Llave de sesión establecida con éxito.');
      }
    }

    // Guardar en Isar
    _isar.saveProfile(profileData);
    
    // Registrar encuentro localmente
    _isar.saveEncounter(
      userId: _userId,
      otherZoneId: profileData['zone_id'],
      isSynced: _connectivity.isOnline,
    );

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

    sendMessage(targetEndpointId, jsonEncode({
      'type': 'routing_table',
      'data': routes,
    }));
  }

  void _handleRoutingTableUpdate(String fromEndpointId, List<dynamic> routes) {
    print('[NearbyService] Actualización de tabla Mesh desde $fromEndpointId');
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
    _isar.updateRoute(zoneId, nextHop, distance);
    print('[NearbyService] Ruta Mesh actualizada: $zoneId vía $nextHop (saltos: $distance)');
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
        print('[NearbyService] Mensaje Mesh cifrado para $targetZoneId');
      } catch (e) {
        print('[NearbyService] Error cifrando mensaje Mesh: $e');
      }
    }

    if (route != null) {
      print('[NearbyService] Enviando mensaje Mesh a $targetZoneId vía ${route.nextHopEndpointId}');
      sendMessage(route.nextHopEndpointId, jsonEncode(packet));
    } else {
      // Flood: Si no hay ruta, enviar a todos los vecinos
      print('[NearbyService] No hay ruta para $targetZoneId, inundando red...');
      for (final endpoint in _connectedEndpoints) {
        sendMessage(endpoint, jsonEncode(packet));
      }
    }
  }

  void _handleMeshMessage(String fromEndpointId, Map<String, dynamic> packet) async {
    final target = packet['target'] as String;
    final source = packet['source'] as String;
    final msgId = packet['msgId'] as String;
    final hops = (packet['hops'] as int) + 1;

    if (target == _myZoneId) {
      // Validar si hay un match/permiso antes de procesar
      final profile = await _isar.getProfile(source);
      if (profile != null) {
        _processIncomingMeshMessage(source, packet, fromEndpointId);
      } else {
        print('[NearbyService] Mensaje Mesh ignorado: No hay perfil/match previo con $source');
      }
      return;
    }

    if (hops >= _maxMeshHops) return;

    // Relay: Reenviar mensaje
    packet['hops'] = hops;
    final route = _routingTable[target];
    
    if (route != null) {
      // Reenviar al siguiente salto conocido
      if (route.nextHopEndpointId != fromEndpointId) {
        sendMessage(route.nextHopEndpointId, jsonEncode(packet));
      }
    } else {
      // Flood relay: A todos excepto de donde vino
      for (final endpoint in _connectedEndpoints) {
        if (endpoint != fromEndpointId) {
          sendMessage(endpoint, jsonEncode(packet));
        }
      }
    }
  }

  Future<void> _processIncomingMeshMessage(String sourceZoneId, Map<String, dynamic> packet, String fromEndpointId) async {
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
          print('[NearbyService] Mensaje Mesh descifrado de $sourceZoneId');
        } catch (e) {
          text = '[Error de descifrado: la llave de sesión podría ser inválida]';
          print('[NearbyService] Error descifrando mensaje Mesh: $e');
        }
      } else {
        text = '[Mensaje cifrado recibido pero no se tiene la llave de sesión]';
      }
    }

    print('[NearbyService] Mensaje Mesh procesado de $sourceZoneId: $text');
    _incomingMessagesController.add(
      NearbyMessage(fromEndpointId: fromEndpointId, text: text, sourceZoneId: sourceZoneId),
    );
  }

  /// Verifica si un usuario está disponible para chat P2P directo.
  bool isPeerConnected(String zoneId) {
    return _routingTable.containsKey(zoneId) && _routingTable[zoneId]!.distance == 1;
  }

  /// Verifica si un usuario es alcanzable vía Mesh.
  bool isPeerReachable(String zoneId) {
    return _routingTable.containsKey(zoneId);
  }

  void _onPayloadTransferUpdate(String endpointId, PayloadTransferUpdate update) {}

  // ──────────────────────────────────────────────────────────────
  //  STRESS TESTING & SIMULATION
  // ──────────────────────────────────────────────────────────────

  /// Simula el recibimiento de múltiples mensajes Mesh para pruebas de estrés.
  void simulateMeshTraffic(int messageCount) {
    print('[NearbyService] Iniciando simulación de estrés: $messageCount mensajes...');
    for (int i = 0; i < messageCount; i++) {
       final mockPacket = {
        'type': 'mesh_msg',
        'source': 'MOCK-USER-$i',
        'target': _myZoneId,
        'msgId': 'mock-$i-${DateTime.now().millisecondsSinceEpoch}',
        'text': 'Mensaje de prueba número $i - Malla de Seguridad Activa.',
        'hops': 1,
        'isEncrypted': false,
      };
      
      // Inyectar manualmente
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
    stopRadar();
    if (_lifecycleObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleObserverRegistered = false;
    }
    _discoveredUsersController.close();
    _incomingMessagesController.close();
  }
}
