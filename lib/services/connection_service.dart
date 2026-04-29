class ConnectionService {
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();

  /// Solicita conectarse con un usuario encontrado en el Radar.
  Future<void> sendConnectionRequest(String senderId, String receiverId) async {
    print('INFO: Solicitud de Supabase enviada de $senderId a $receiverId');
    // TODO: Implementar Supabase.instance.client.from('connection_requests').insert(...)
  }

  /// Acepta el chat con alguien.
  Future<void> acceptRequest(String requestId) async {
    print('INFO: Aceptando solicitud $requestId. Preparando entorno de llaves E2EE.');
    // TODO: Actualizar status a 'accepted' y forjar canal
  }

  /// Rechaza el chat con alguien.
  Future<void> rejectRequest(String requestId) async {
    print('INFO: Rechazando solicitud $requestId');
    // TODO: Actualizar status a 'rejected'
  }
}
