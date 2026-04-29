import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'supabase_service.dart';

/// Modelo de usuario descubierto por Nearby Connections.
class NearbyUser {
  final String endpointId;
  final String token; // Token efímero recibido
  String userName; // Resuelto desde Supabase
  String zoneId; // ZONE-ID real resuelto
  bool isConnected;
  Map<String, dynamic>? profile; // Perfil completo de Supabase

  NearbyUser({
    required this.endpointId,
    required this.token,
    this.userName = '...',
    this.zoneId = '',
    this.isConnected = false,
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

  static const Strategy _strategy = Strategy.P2P_CLUSTER;
  static const String _serviceId = 'com.dybrocorp.zone';

  /// Token efímero actual (se renueva cada ~4 min)
  String _currentToken = 'ZONE-INIT';
  String _userId = '';

  bool _isAdvertising = false;
  bool _isDiscovering = false;
  bool get isRadarActive => _isAdvertising || _isDiscovering;

  /// Smart scan timers
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

  // ──────────────────────────────────────────────────────────────
  //  Inicialización
  // ──────────────────────────────────────────────────────────────

  /// Inicializa con el userId de Supabase y obtiene el primer token BT.
  Future<void> initialize(String userId) async {
    _userId = userId;
    WidgetsBinding.instance.addObserver(this);
    await _refreshToken();
  }

  /// Renueva el token BT efímero cada 4 minutos.
  Future<void> _refreshToken() async {
    if (_userId.isEmpty) return;
    final token = await _supabaseService.generateBtToken(_userId);
    if (token != null && token.isNotEmpty) {
      _currentToken = token;
    }
  }

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
    _isAdvertising = false;
    _isDiscovering = false;
  }

  void _resumeScanning() {
    if (!isRadarActive) return;
    _startSmartScanCycle();
  }

  // ──────────────────────────────────────────────────────────────
  //  Radar con escaneo inteligente (15s ciclo)
  // ──────────────────────────────────────────────────────────────

  /// Inicia el radar con ciclo inteligente de 15s y renovación de token.
  Future<void> startRadar() async {
    await _startAdvertising();
    await _startDiscovery();
    _startSmartScanCycle();
    // Renovar token cada 4 minutos
    _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 4), (_) async {
      await _refreshToken();
      // Reiniciar advertising con el nuevo token
      if (_isAdvertising) {
        await _nearby.stopAdvertising();
        _isAdvertising = false;
        await _startAdvertising();
      }
    });
  }

  /// Ciclo inteligente: escanea 12s, pausa 3s (reduce consumo de batería).
  void _startSmartScanCycle() {
    _scanCycleTimer?.cancel();
    _scanCycleTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!_isDiscovering) return;
      // Breve pausa para que el stack BT/WiFi respire
      await _nearby.stopDiscovery();
      _isDiscovering = false;
      await Future.delayed(const Duration(seconds: 3));
      await _startDiscovery();
    });
  }

  /// Detiene el radar completamente.
  Future<void> stopRadar() async {
    _scanCycleTimer?.cancel();
    _tokenRefreshTimer?.cancel();
    await _stopAdvertising();
    await _stopDiscovery();
    _discoveredUsers.clear();
    _emitDiscoveredUsers();
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;
    try {
      await _nearby.startAdvertising(
        _currentToken, // ← Token efímero, NO el zone_id real
        _strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
      _isAdvertising = true;
    } catch (e) {
      print('[NearbyService] Error al iniciar advertising: $e');
    }
  }

  Future<void> _startDiscovery() async {
    if (_isDiscovering) return;
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
    }
  }

  Future<void> _stopAdvertising() async {
    if (!_isAdvertising) return;
    await _nearby.stopAdvertising();
    _isAdvertising = false;
  }

  Future<void> _stopDiscovery() async {
    if (!_isDiscovering) return;
    await _nearby.stopDiscovery();
    _isDiscovering = false;
  }

  // ──────────────────────────────────────────────────────────────
  //  Callbacks de Discovery — resuelve token → zone_id via Supabase
  // ──────────────────────────────────────────────────────────────

  void _onEndpointFound(String id, String receivedToken, String serviceId) {
    // Agregar con display temporal mientras se resuelve
    _discoveredUsers[id] = NearbyUser(
      endpointId: id,
      token: receivedToken,
      userName: 'Cargando...',
    );
    _emitDiscoveredUsers();

    // Resolver token en Supabase de forma asíncrona
    _resolveTokenAsync(id, receivedToken);
  }

  Future<void> _resolveTokenAsync(String endpointId, String token) async {
    try {
      final profile = await _supabaseService.resolveToken(token);
      if (profile != null && _discoveredUsers.containsKey(endpointId)) {
        _discoveredUsers[endpointId]!
          ..userName = profile['display_name'] ?? profile['zone_id'] ?? 'ZONE-???'
          ..zoneId = profile['zone_id'] ?? ''
          ..profile = profile;
        _emitDiscoveredUsers();

        // Registrar encuentro en Supabase ("Nos cruzamos")
        if (_userId.isNotEmpty && profile['zone_id'] != null) {
          await _supabaseService.registerEncounter(_userId, profile['zone_id']);
        }
      }
    } catch (e) {
      print('[NearbyService] Error al resolver token: $e');
    }
  }

  void _onEndpointLost(String? id) {
    if (id == null) return;
    _discoveredUsers.remove(id);
    _emitDiscoveredUsers();
  }

  // ──────────────────────────────────────────────────────────────
  //  Callbacks de Conexión
  // ──────────────────────────────────────────────────────────────

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    _pendingConnections[id] = info;
    acceptConnection(id); // Auto-aceptar para radar; el match real va por Supabase
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

  // ──────────────────────────────────────────────────────────────
  //  Acciones de conexión
  // ──────────────────────────────────────────────────────────────

  Future<void> requestConnection(String endpointId) async {
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

  // ──────────────────────────────────────────────────────────────
  //  Envío y recepción de datos (Payloads)
  // ──────────────────────────────────────────────────────────────

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

  // ──────────────────────────────────────────────────────────────
  //  Utilidades
  // ──────────────────────────────────────────────────────────────

  void _emitDiscoveredUsers() {
    _discoveredUsersController.add(discoveredUsers);
  }

  Future<void> requestPermissions() async {}

  void dispose() {
    stopRadar();
    WidgetsBinding.instance.removeObserver(this);
    _discoveredUsersController.close();
    _incomingMessagesController.close();
  }
}
