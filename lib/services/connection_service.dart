import '../services/nearby_service.dart';

class ConnectionService {
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();

  final NearbyService _nearbyService = NearbyService();

  /// Solicita conectarse con un usuario encontrado en el Radar.
  Future<void> sendConnectionRequest(String endpointId) async {
    print('INFO: Enviando solicitud de conexión a $endpointId');
    await _nearbyService.requestConnection(endpointId);
  }

  /// Acepta la conexión con alguien.
  Future<void> acceptRequest(String endpointId) async {
    print('INFO: Aceptando conexión de $endpointId. Preparando entorno E2EE.');
    await _nearbyService.acceptConnection(endpointId);
  }

  /// Rechaza la conexión con alguien.
  Future<void> rejectRequest(String endpointId) async {
    print('INFO: Rechazando conexión de $endpointId');
    await _nearbyService.rejectConnection(endpointId);
  }

  /// Desconecta de un usuario.
  void disconnect(String endpointId) {
    _nearbyService.disconnectFrom(endpointId);
  }

  /// Envía un mensaje de texto a un usuario conectado.
  Future<void> sendMessage(String endpointId, String message) async {
    await _nearbyService.sendMessage(endpointId, message);
  }
}
