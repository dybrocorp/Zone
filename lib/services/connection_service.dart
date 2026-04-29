import '../services/supabase_service.dart';

class ConnectionService {
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();

  final _supabaseService = SupabaseService();

  /// Envía una solicitud de match a través de Supabase.
  Future<bool> sendConnectionRequest(String myId, String theirId) async {
    final matchId = await _supabaseService.requestMatch(myId, theirId);
    return matchId != null;
  }

  /// Acepta un match.
  Future<void> acceptRequest(String matchId) async {
    await _supabaseService.acceptMatch(matchId);
  }

  /// Rechaza un match.
  Future<void> rejectRequest(String matchId) async {
    await _supabaseService.rejectMatch(matchId);
  }
}
