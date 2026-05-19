import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:realtime_client/realtime_client.dart' as rc;
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

  /// Genera un token efímero (10 min TTL) para compartir en Nearby Connections.
  /// En vez de compartir el zone_id directamente, se comparte este token.
  Future<String?> generateBtToken(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final token = _uuid.v4();
      final expiresAt = DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String();

      await _supabase.from('bt_tokens').insert({
        'user_id': userId,
        'token': token,
        'expires_at': expiresAt,
        'used': false,
      });

      return token;
    } catch (e) {
      print('[SupabaseService] Error generando BT token: $e');
      return null;
    }
  }

  /// Resuelve un token BT hacia el perfil del usuario (radar bilateral).
  /// Usa RPC `resolve_bt_token` si está desplegado; si no, consulta directa.
  Future<Map<String, dynamic>?> resolveToken(String token) async {
    if (token.isEmpty || token == 'ZONE-INIT') return null;

    try {
      final rpcResult = await _supabase.rpc('resolve_bt_token', params: {'p_token': token});
      if (rpcResult != null) {
        return Map<String, dynamic>.from(rpcResult as Map);
      }
    } catch (e) {
      print('[SupabaseService] RPC resolve_bt_token no disponible, usando fallback: $e');
    }

    try {
      final result = await _supabase
          .from('bt_tokens')
          .select('user_id, users!inner(*)')
          .eq('token', token)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .maybeSingle();

      if (result == null) return null;

      final user = result['users'] as Map<String, dynamic>;
      if (user['stealth_mode'] == true) return null;
      
      // Filtrar redes sociales según visibilidad
      final filteredUser = Map<String, dynamic>.from(user);
      if (user['ig_visible'] != true) filteredUser['instagram_handle'] = null;
      if (user['fb_visible'] != true) filteredUser['facebook_handle'] = null;
      if (user['tiktok_visible'] != true) filteredUser['tiktok_handle'] = null;
      
      return filteredUser;
    } catch (e) {
      print('[SupabaseService] Error resolviendo token: $e');
      return null;
    }
  }

  /// IDs de usuarios bloqueados por el usuario actual (para filtrar radar).
  Future<Set<String>> getBlockedUserIds(String userId) async {
    try {
      final result = await _supabase
          .from('blocked_users')
          .select('blocked_id')
          .eq('blocker_id', userId);
      return result.map((r) => r['blocked_id'] as String).toSet();
    } catch (e) {
      print('[SupabaseService] Error obteniendo bloqueos: $e');
      return {};
    }
  }

  // ──────────────────────────────────────────────────────────
  //  ENCUENTROS ("Nos cruzamos")
  // ──────────────────────────────────────────────────────────

  /// Registra que el usuario vio a `otherZoneId` cerca.
  Future<void> registerEncounter(String userId, String otherZoneId) async {
    try {
      await _supabase.from('encounters').insert({
        'user_id': userId,
        'other_zone_id': otherZoneId,
        'seen_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      // Ignorar duplicados horarios (índice único funcional)
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
      final rows = await _supabase
          .from('matches')
          .select('*, requester:users!matches_requester_id_fkey(id, zone_id, display_name, avatar_url), receiver:users!matches_receiver_id_fkey(id, zone_id, display_name, avatar_url)')
          .eq('status', 'accepted')
          .or('requester_id.eq.$userId,receiver_id.eq.$userId');

      final enriched = <Map<String, dynamic>>[];
      for (final match in List<Map<String, dynamic>>.from(rows)) {
        final requester = match['requester'] as Map<String, dynamic>?;
        final receiver = match['receiver'] as Map<String, dynamic>?;
        
        final otherUser = requester?['id'] == userId ? receiver : requester;
        
        enriched.add({
          ...match,
          'other_user': otherUser,
        });
      }
      return enriched;
    } catch (e) {
      print('[SupabaseService] Error obteniendo matches: $e');
      return [];
    }
  }

  /// Obtiene solicitudes de match pendientes dirigidas al usuario.
  Future<List<Map<String, dynamic>>> getPendingRequests(String userId) async {
    try {
      final rows = await _supabase
          .from('matches')
          .select('*, requester:users!matches_requester_id_fkey(id, zone_id, display_name, avatar_url)')
          .eq('receiver_id', userId)
          .eq('status', 'pending');

      final enriched = <Map<String, dynamic>>[];
      for (final match in List<Map<String, dynamic>>.from(rows)) {
        enriched.add({
          ...match,
          'requester_user': match['requester'],
        });
      }
      return enriched;
    } catch (e) {
      print('[SupabaseService] Error obteniendo solicitudes match: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> _getUserPublicProfile(String userId) async {
    try {
      final row = await _supabase
          .from('users')
          .select('id, zone_id, display_name, avatar_url')
          .eq('id', userId)
          .eq('is_shadowbanned', false)
          .maybeSingle();
      return row;
    } catch (e) {
      return null;
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
    final messageId = _uuid.v4();
    final payload = {
      'id': messageId,
      'match_id': matchId,
      'sender_id': senderId,
      'encrypted_content': encryptedContent,
      'nonce': nonce,
      'mac': mac,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    // 1. Insertar en DB para persistencia (Segundo plano)
    // No esperamos al insert para el broadcast, así es más rápido
    _supabase.from('messages').insert(payload).then((_) {
      print('[SupabaseService] Mensaje guardado en DB');
    }).catchError((e) {
      print('[SupabaseService] Error guardando mensaje en DB: $e');
    });

    // 2. Enviar via Broadcast para inmediatez (WebSocket puro)
    final normalizedMatchId = matchId.trim().toLowerCase();
    print('[SupabaseService] Enviando Broadcast a canal msgs:$normalizedMatchId');
    
    await _supabase
        .channel('msgs:$normalizedMatchId')
        .sendBroadcastMessage(
          event: 'new_msg',
          payload: payload,
        );
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
    String myUid,
    void Function(Map<String, dynamic> message) onMessage,
    void Function(bool isOnline)? onPresenceChange,
    void Function(bool isTyping)? onTypingChange,
  ) {
    final normalizedMatchId = matchId.trim().toLowerCase();
    
    final channel = _supabase
        .channel('msgs:$normalizedMatchId', opts: const RealtimeChannelConfig(self: true));
        
    channel
        // 1. Escuchar BROADCAST (Mensajes instantáneos)
        .onBroadcast(
          event: 'new_msg',
          callback: (payload) {
            print('[SupabaseService] Realtime (Broadcast): Mensaje recibido!');
            onMessage(Map<String, dynamic>.from(payload));
          },
        )
        // 2. Escuchar EVENTOS DE ESCRITURA
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final senderId = payload['sender_id'];
            final isTyping = payload['is_typing'] as bool? ?? false;
            if (senderId != myUid && onTypingChange != null) {
              onTypingChange(isTyping);
            }
          },
        )
        // 3. Escuchar PRESENCIA (Online/Offline)
        .onPresenceSync((_) {
          if (onPresenceChange != null) {
            final activeUsers = channel.presenceState();
            final others = activeUsers.where((e) {
              final uid = e.state['uid'] as String?;
              return uid != null && uid != myUid;
            }).toList();
            onPresenceChange(others.isNotEmpty);
          }
        })
        // 4. Escuchar POSTGRES (Persistencia - Fallback)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final newRec = payload.newRecord;
            final recMatchId = (newRec['match_id'] as String?)?.trim().toLowerCase();
            if (recMatchId == normalizedMatchId) {
              onMessage(newRec);
            }
          },
        );

    channel.subscribe((status, [error]) async {
      print('[SupabaseService] Estado suscripción mensajes ($normalizedMatchId): $status');
      if (status == RealtimeSubscribeStatus.subscribed) {
        // Al conectarnos, trackeamos nuestra presencia
        await channel.track({'uid': myUid, 'online_at': DateTime.now().toIso8601String()});
      }
      if (error != null) {
        print('[SupabaseService] ERROR suscripción mensajes: $error');
      }
    });

    return channel;
  }

  /// Envía un evento de "escribiendo..." o "dejó de escribir".
  Future<void> sendTypingStatus(RealtimeChannel channel, String myUid, bool isTyping) async {
    await channel.sendBroadcastMessage(
      event: 'typing',
      payload: {
        'sender_id': myUid,
        'is_typing': isTyping,
      },
    );
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
    
    if (result == null) return null;
    if (result['stealth_mode'] == true) return null;

    final filtered = Map<String, dynamic>.from(result);
    if (result['ig_visible'] != true) filtered['instagram_handle'] = null;
    if (result['fb_visible'] != true) filtered['facebook_handle'] = null;
    if (result['tiktok_visible'] != true) filtered['tiktok_handle'] = null;

    return filtered;
  }

  /// Escucha notificaciones globales (mensajes y nuevos matches) para el usuario.
  void startGlobalNotificationListener(String myUid) {
    print('[SupabaseService] Iniciando escucha global de notificaciones para $myUid');

    // 1. Escuchar Nuevos Mensajes en cualquier match
    _supabase
        .channel('global_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            print('[SupabaseService] Notificación Global: Mensaje detectado');
            final msg = payload.newRecord;
            final senderId = msg['sender_id'] as String?;
            final matchId = msg['match_id'] as String?;

            if (senderId != null && senderId != myUid) {
              if (NotificationService.currentActiveMatchId != matchId) {
                print('[SupabaseService] Mostrando notificación de mensaje...');
                NotificationService().showMessageNotification('Alguien', 'Te ha enviado un mensaje seguro.');
              } else {
                print('[SupabaseService] Notificación omitida (chat abierto)');
              }
            }
          },
        )
        .subscribe((status, [error]) {
          print('[SupabaseService] Estado canal global_messages: $status');
          if (error != null) print('[SupabaseService] Error global_messages: $error');
        });

    // 2. Escuchar Nuevos Matches (Solicitudes)
    _supabase
        .channel('global_matches')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'matches',
          callback: (payload) {
            print('[SupabaseService] Notificación Global: Match detectado');
            final match = payload.newRecord;
            final receiverId = match['receiver_id'] as String?;
            if (receiverId == myUid) {
              print('[SupabaseService] Mostrando notificación de solicitud...');
              NotificationService().showMatchRequestNotification('Un usuario cercano');
            }
          },
        )
        .subscribe((status, [error]) {
          print('[SupabaseService] Estado canal global_matches: $status');
          if (error != null) print('[SupabaseService] Error global_matches: $error');
        });
  }
}
