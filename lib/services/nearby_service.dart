import 'dart:async';
import 'dart:convert';
import 'package:nearby_connections/nearby_connections.dart';

/// Modelo de usuario descubierto por Nearby Connections.
class NearbyUser {
  final String endpointId;
  final String userName;
  bool isConnected;

  NearbyUser({
    required this.endpointId,
    required this.userName,
    this.isConnected = false,
  });
}

/// Modelo de mensaje recibido via payload.
class NearbyMessage {
  final String fromEndpointId;
  final String text;

  NearbyMessage({required this.fromEndpointId, required this.text});
}

/// Servicio Singleton que maneja el descubrimiento de usuarios
/// y la comunicación P2P usando Google Nearby Connections.
class NearbyService {
  static final NearbyService _instance = NearbyService._internal();
  factory NearbyService() => _instance;
  NearbyService._internal();

  final Nearby _nearby = Nearby();

  /// Constantes de configuración
  static const Strategy _strategy = Strategy.P2P_CLUSTER;
  static const String _serviceId = 'com.dybrocorp.zone';

  /// Nombre de usuario local (se configura en initialize)
  String _userName = '';
  String get userName => _userName;

  /// Estado del radar
  bool _isAdvertising = false;
  bool _isDiscovering = false;
  bool get isRadarActive => _isAdvertising || _isDiscovering;

  /// Lista reactiva de usuarios descubiertos
  final Map<String, NearbyUser> _discoveredUsers = {};
  final _discoveredUsersController =
      StreamController<List<NearbyUser>>.broadcast();
  Stream<List<NearbyUser>> get discoveredUsersStream =>
      _discoveredUsersController.stream;
  List<NearbyUser> get discoveredUsers => _discoveredUsers.values.toList();

  /// Stream de mensajes entrantes
  final _incomingMessagesController =
      StreamController<NearbyMessage>.broadcast();
  Stream<NearbyMessage> get incomingMessagesStream =>
      _incomingMessagesController.stream;

  /// Stream de solicitudes de conexión entrantes
  final _connectionRequestController =
      StreamController<ConnectionInfo>.broadcast();
  Stream<ConnectionInfo> get connectionRequestStream =>
      _connectionRequestController.stream;

  /// Mapa de conexiones activas (endpointId -> info)
  final Map<String, ConnectionInfo> _pendingConnections = {};
  final Set<String> _connectedEndpoints = {};

  // ──────────────────────────────────────────────────────────────
  //  Inicialización
  // ──────────────────────────────────────────────────────────────

  /// Inicializa el servicio con el nombre de usuario local.
  void initialize(String userName) {
    _userName = userName;
    print('[NearbyService] Inicializado con usuario: $_userName');
  }

  // ──────────────────────────────────────────────────────────────
  //  Radar (Advertising + Discovery simultáneo)
  // ──────────────────────────────────────────────────────────────

  /// Inicia el radar: advertising + discovery al mismo tiempo.
  Future<void> startRadar() async {
    await _startAdvertising();
    await _startDiscovery();
  }

  /// Detiene el radar completamente.
  Future<void> stopRadar() async {
    await _stopAdvertising();
    await _stopDiscovery();
    _discoveredUsers.clear();
    _emitDiscoveredUsers();
  }

  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;
    try {
      await _nearby.startAdvertising(
        _userName,
        _strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
      _isAdvertising = true;
      print('[NearbyService] Advertising iniciado.');
    } catch (e) {
      print('[NearbyService] Error al iniciar advertising: $e');
    }
  }

  Future<void> _startDiscovery() async {
    if (_isDiscovering) return;
    try {
      await _nearby.startDiscovery(
        _userName,
        _strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: _serviceId,
      );
      _isDiscovering = true;
      print('[NearbyService] Discovery iniciado.');
    } catch (e) {
      print('[NearbyService] Error al iniciar discovery: $e');
    }
  }

  Future<void> _stopAdvertising() async {
    if (!_isAdvertising) return;
    await _nearby.stopAdvertising();
    _isAdvertising = false;
    print('[NearbyService] Advertising detenido.');
  }

  Future<void> _stopDiscovery() async {
    if (!_isDiscovering) return;
    await _nearby.stopDiscovery();
    _isDiscovering = false;
    print('[NearbyService] Discovery detenido.');
  }

  // ──────────────────────────────────────────────────────────────
  //  Callbacks de Discovery
  // ──────────────────────────────────────────────────────────────

  void _onEndpointFound(String id, String userName, String serviceId) {
    print('[NearbyService] Endpoint encontrado: $userName ($id)');
    _discoveredUsers[id] = NearbyUser(
      endpointId: id,
      userName: userName,
    );
    _emitDiscoveredUsers();
  }

  void _onEndpointLost(String? id) {
    if (id == null) return;
    print('[NearbyService] Endpoint perdido: $id');
    _discoveredUsers.remove(id);
    _emitDiscoveredUsers();
  }

  // ──────────────────────────────────────────────────────────────
  //  Callbacks de Conexión
  // ──────────────────────────────────────────────────────────────

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    print('[NearbyService] Conexión iniciada con ${info.endpointName} ($id)');
    _pendingConnections[id] = info;
    _connectionRequestController.add(info);

    // Auto-aceptar para facilitar el descubrimiento del radar.
    // En producción se podría mostrar un diálogo de confirmación.
    acceptConnection(id);
  }

  void _onConnectionResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      print('[NearbyService] ¡Conectado con $id!');
      _connectedEndpoints.add(id);
      if (_discoveredUsers.containsKey(id)) {
        _discoveredUsers[id]!.isConnected = true;
        _emitDiscoveredUsers();
      }
    } else {
      print('[NearbyService] Conexión fallida con $id: $status');
      _pendingConnections.remove(id);
    }
  }

  void _onDisconnected(String id) {
    print('[NearbyService] Desconectado de $id');
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

  /// Solicita conexión a un endpoint descubierto.
  Future<void> requestConnection(String endpointId) async {
    try {
      await _nearby.requestConnection(
        _userName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      print('[NearbyService] Solicitud de conexión enviada a $endpointId');
    } catch (e) {
      print('[NearbyService] Error al solicitar conexión: $e');
    }
  }

  /// Acepta una conexión pendiente.
  Future<void> acceptConnection(String endpointId) async {
    try {
      await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: _onPayloadReceived,
        onPayloadTransferUpdate: _onPayloadTransferUpdate,
      );
      print('[NearbyService] Conexión aceptada con $endpointId');
    } catch (e) {
      print('[NearbyService] Error al aceptar conexión: $e');
    }
  }

  /// Rechaza una conexión pendiente.
  Future<void> rejectConnection(String endpointId) async {
    try {
      await _nearby.rejectConnection(endpointId);
      _pendingConnections.remove(endpointId);
      print('[NearbyService] Conexión rechazada con $endpointId');
    } catch (e) {
      print('[NearbyService] Error al rechazar conexión: $e');
    }
  }

  /// Desconecta de un endpoint.
  void disconnectFrom(String endpointId) {
    _nearby.disconnectFromEndpoint(endpointId);
    _connectedEndpoints.remove(endpointId);
    if (_discoveredUsers.containsKey(endpointId)) {
      _discoveredUsers[endpointId]!.isConnected = false;
      _emitDiscoveredUsers();
    }
    print('[NearbyService] Desconectado de $endpointId');
  }

  // ──────────────────────────────────────────────────────────────
  //  Envío y recepción de datos (Payloads)
  // ──────────────────────────────────────────────────────────────

  /// Envía un mensaje de texto a un endpoint conectado.
  Future<void> sendMessage(String endpointId, String message) async {
    if (!_connectedEndpoints.contains(endpointId)) {
      print('[NearbyService] No conectado a $endpointId, no se puede enviar.');
      return;
    }
    try {
      await _nearby.sendBytesPayload(
        endpointId,
        utf8.encode(message),
      );
      print('[NearbyService] Mensaje enviado a $endpointId');
    } catch (e) {
      print('[NearbyService] Error al enviar mensaje: $e');
    }
  }

  /// Envía un mensaje a todos los endpoints conectados.
  Future<void> broadcastMessage(String message) async {
    for (final endpointId in _connectedEndpoints) {
      await sendMessage(endpointId, message);
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      final text = utf8.decode(payload.bytes!);
      print('[NearbyService] Mensaje de $endpointId: $text');
      _incomingMessagesController.add(
        NearbyMessage(fromEndpointId: endpointId, text: text),
      );
    }
  }

  void _onPayloadTransferUpdate(
      String endpointId, PayloadTransferUpdate update) {
    // Se puede usar para mostrar el progreso de transferencias de archivos.
    if (update.status == PayloadStatus.SUCCESS) {
      print('[NearbyService] Payload transferido exitosamente con $endpointId');
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  Utilidades
  // ──────────────────────────────────────────────────────────────

  void _emitDiscoveredUsers() {
    _discoveredUsersController.add(discoveredUsers);
  }

  /// Solicita todos los permisos necesarios usando PermissionsService.
  Future<void> requestPermissions() async {
    // Se importa dinámicamente para evitar dependencia circular.
    // En la práctica, se llama desde PermissionsService antes de iniciar el radar.
    // Este es un wrapper de conveniencia.
    // Los permisos los maneja PermissionsService.requestAllPermissions().
  }

  /// Limpia todos los recursos al cerrar.
  void dispose() {
    stopRadar();
    _discoveredUsersController.close();
    _incomingMessagesController.close();
    _connectionRequestController.close();
  }
}
