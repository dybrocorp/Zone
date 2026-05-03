import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import 'package:uuid/uuid.dart';

/// Servicio central para todas las operaciones de Supabase:
/// tokens BT, encuentros, matches, mensajes, reportes, bloqueos.
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final _supabase = Supabase.instance.client;
  final _uuid = const Uuid();

  // ──────────────────────────────────────────────────────────
  //  TOKENS BLUETOOTH TEMPORALES
  // ──────────────────────────────────────────────────────────

  /// Genera un token efímero (5 min TTL) para compartir en Nearby Connections.
  /// En vez de compartir el zone_id directamente, se comparte este token.
  Future<String?> generateBtToken(String userId) async {
    try {
      final token = _uuid.v4();
      final expiresAt = DateTime.now().add(const Duration(minutes: 5)).toUtc().toIso8601String();

      await _supabase.from('bt_tokens').insert({
        'user_id': userId,
        'token': token,
        'expires_at': expiresAt,
      });

      return token;
    } catch (e) {
      print('[SupabaseService] Error generando BT token: $e');
      return null;
    }
  }

  /// Resuelve un token BT hacia el zone_id real del usuario.
  /// Devuelve null si el token expiró, ya fue usado, o no existe.
  Future<Map<String, dynamic>?> resolveToken(String token) async {
    try {
      final result = await _supabase
          .from('bt_tokens')
          .select('user_id, users!inner(zone_id, display_name, stealth_mode, public_key, instagram_handle, ig_visible, facebook_handle, fb_visible, tiktok_handle, tiktok_visible)')
          .eq('token', token)
          .eq('used', false)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .maybeSingle();

      if (result == null) return null;

      // Marcar token como usado
      await _supabase
          .from('bt_tokens')
          .update({'used': true})
          .eq('token', token);

      return result['users'] as Map<String, dynamic>;
    } catch (e) {
      print('[SupabaseService] Error resolviendo token: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────
  //  ENCUENTROS ("Nos cruzamos")
  // ──────────────────────────────────────────────────────────

  /// Registra que el usuario vio a `otherZoneId` cerca.
  Future<void> registerEncounter(String userId, String otherZoneId) async {
    try {
      await _supabase.from('encounters').upsert({
        'user_id': userId,
        'other_zone_id': otherZoneId,
        'seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id, other_zone_id, date_trunc(hour, seen_at)');
    } catch (e) {
      // Ignorar duplicados (la constraint UNIQUE maneja esto)
    }
  }

  /// Obtiene la lista de encuentros recientes del usuario (últimas 24h).
  Future<List<Map<String, dynamic>>> getRecentEncounters(String userId) async {
    final since = DateTime.now().subtract(const Duration(hours: 24)).toUtc().toIso8601String();
    final result = await _supabase
        .from('encounters')
        .select()
        .eq('user_id', userId)
        .gte('seen_at', since)
        .order('seen_at', ascending: false);
    return List<Map<String, dynamic>>.from(result);
  }

  // ──────────────────────────────────────────────────────────
  //  MATCHES
  // ──────────────────────────────────────────────────────────

  /// Solicita un match con otro usuario para poder chatear.
  Future<String?> requestMatch(String requesterId, String receiverId) async {
    try {
      final result = await _supabase.from('matches').insert({
        'requester_id': requesterId,
        'receiver_id': receiverId,
        'status': 'pending',
      }).select('id').single();
      return result['id'] as String;
    } catch (e) {
      print('[SupabaseService] Error solicitando match: $e');
      return null;
    }
  }

  /// Acepta un match pendiente.
  Future<void> acceptMatch(String matchId) async {
    await _supabase
        .from('matches')
        .update({'status': 'accepted'})
        .eq('id', matchId);
  }

  /// Rechaza un match pendiente.
  Future<void> rejectMatch(String matchId) async {
    await _supabase
        .from('matches')
        .update({'status': 'rejected'})
        .eq('id', matchId);
  }

  /// Elimina un match y sus mensajes (cascada).
  Future<void> deleteMatch(String matchId) async {
    await _supabase
        .from('matches')
        .delete()
        .eq('id', matchId);
  }

  /// Obtiene todos los matches aceptados del usuario actual.
  Future<List<Map<String, dynamic>>> getAcceptedMatches(String userId) async {
    try {
      final result = await _supabase
          .from('matches')
          .select('*, users!matches_requester_id_fkey(zone_id, display_name), users!matches_receiver_id_fkey(zone_id, display_name)')
          .eq('status', 'accepted')
          .or('requester_id.eq.$userId,receiver_id.eq.$userId');
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      print('[SupabaseService] Error obteniendo matches: $e');
      return [];
    }
  }

  /// Obtiene solicitudes de match pendientes dirigidas al usuario.
  Future<List<Map<String, dynamic>>> getPendingRequests(String userId) async {
    try {
      final result = await _supabase
          .from('matches')
          .select('*, users!matches_requester_id_fkey(zone_id, display_name)')
          .eq('receiver_id', userId)
          .eq('status', 'pending');
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      print('[SupabaseService] Error obteniendo solicitudes match: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────
  //  MENSAJES E2EE
  // ──────────────────────────────────────────────────────────

  /// Envía un mensaje cifrado. Solo funciona si hay un match aceptado.
  Future<void> sendMessage({
    required String matchId,
    required String senderId,
    required String encryptedContent,
    required String nonce,
    required String mac,
  }) async {
    await _supabase.from('messages').insert({
      'match_id': matchId,
      'sender_id': senderId,
      'encrypted_content': encryptedContent,
      'nonce': nonce,
      'mac': mac,
    });
  }

  /// Obtiene mensajes de un match, ordernados por fecha.
  Future<List<Map<String, dynamic>>> getMessages(String matchId) async {
    final result = await _supabase
        .from('messages')
        .select()
        .eq('match_id', matchId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(result);
  }

  /// Escucha mensajes en tiempo real para un match activo.
  RealtimeChannel subscribeToMessages(
    String matchId,
    void Function(Map<String, dynamic> message) onMessage,
  ) {
    return _supabase
        .channel('messages:$matchId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: matchId,
          ),
          callback: (payload) {
            onMessage(payload.newRecord);
          },
        )
        .subscribe();
  }

  // ──────────────────────────────────────────────────────────
  //  REPORTES Y BLOQUEOS
  // ──────────────────────────────────────────────────────────

  /// Reporta un usuario. 3 reportes → shadowban automático (via trigger).
  Future<void> reportUser(String reporterId, String reportedId, String reason) async {
    try {
      await _supabase.from('reports').insert({
        'reporter_id': reporterId,
        'reported_id': reportedId,
        'reason': reason,
      });
    } catch (e) {
      // Ignorar si ya reportó al mismo usuario antes
    }
  }

  /// Bloquea un usuario. El bloqueado no aparecerá más en el radar.
  Future<void> blockUser(String blockerId, String blockedId) async {
    try {
      await _supabase.from('blocked_users').insert({
        'blocker_id': blockerId,
        'blocked_id': blockedId,
      });
    } catch (e) {
      // Ignorar duplicados
    }
  }
  /// Obtiene la lista de usuarios bloqueados por el usuario.
  Future<List<Map<String, dynamic>>> getBlockedUsers(String userId) async {
    try {
      final result = await _supabase
          .from('blocked_users')
          .select('*, users!blocked_users_blocked_id_fkey(zone_id, display_name)')
          .eq('blocker_id', userId);
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      print('[SupabaseService] Error obteniendo usuarios bloqueados: $e');
      return [];
    }
  }

  /// Desbloquea un usuario.
  Future<void> unblockUser(String blockerId, String blockedId) async {
    await _supabase
        .from('blocked_users')
        .delete()
        .eq('blocker_id', blockerId)
        .eq('blocked_id', blockedId);
  }

  // ──────────────────────────────────────────────────────────
  //  PERFIL PÚBLICO
  // ──────────────────────────────────────────────────────────

  /// Busca un perfil por ZONE-ID público.
  Future<Map<String, dynamic>?> getProfileByZoneId(String zoneId) async {
    final result = await _supabase
        .from('users')
        .select()
        .eq('zone_id', zoneId)
        .eq('is_shadowbanned', false)
        .maybeSingle();
    return result;
  }

  /// Escucha notificaciones globales (mensajes y nuevos matches) para el usuario.
  void startGlobalNotificationListener(String myUid) {
    // 1. Escuchar Nuevos Mensajes en cualquier match
    _supabase
        .channel('global_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            final msg = payload.newRecord;
            final senderId = msg['sender_id'] as String;
            final matchId = msg['match_id'] as String;

            if (senderId != myUid) {
              // Si no estamos en el chat abierto actualmente
              if (NotificationService.currentActiveMatchId != matchId) {
                // Obtener nombre del remitente (opcional, por ahora genérico por privacidad)
                NotificationService().showMessageNotification('Alguien', 'Te ha enviado un mensaje seguro.');
              }
            }
          },
        )
        .subscribe();

    // 2. Escuchar Nuevos Matches (Solicitudes)
    _supabase
        .channel('global_matches')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'matches',
          callback: (payload) {
            final match = payload.newRecord;
            final u1 = match['user1_id'] as String;
            final u2 = match['user2_id'] as String;

            if (u2 == myUid) {
              NotificationService().showMatchRequestNotification('Un usuario cercano');
            }
          },
        )
        .subscribe();
  }
}
