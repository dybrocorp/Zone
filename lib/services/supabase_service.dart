import 'package:supabase_flutter/supabase_flutter.dart';
import 'logger_service.dart';
import 'notification_service.dart';
import '../utils/retry_helper.dart';
import 'package:uuid/uuid.dart';

/// Servicio central para todas las operaciones de Supabase:
/// tokens BT, encuentros, matches, mensajes, reportes, bloqueos.
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final _logger = LoggerService();

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
      _logger.debug('[SupabaseService] Error generando BT token: $e');
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
      _logger.debug('[SupabaseService] RPC resolve_bt_token no disponible, usando fallback: $e');
    }

    try {
      final result = await _supabase
          .from('bt_tokens')
          .select('user_id, users!inner(*)')
          .eq('token', token)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .maybeSingle();

      if (result == null) return null;

      final user = Map<String, dynamic>.from(result['users'] as Map);
      if (user['stealth_mode'] == true) return null;
      
      // Filtrar redes sociales según visibilidad
      final filteredUser = Map<String, dynamic>.from(user);
      if (user['ig_visible'] != true) filteredUser['instagram_handle'] = null;
      if (user['fb_visible'] != true) filteredUser['facebook_handle'] = null;
      if (user['tiktok_visible'] != true) filteredUser['tiktok_handle'] = null;
      
      return filteredUser;
    } catch (e) {
      _logger.debug('[SupabaseService] Error resolviendo token: $e');
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
      _logger.debug('[SupabaseService] Error obteniendo bloqueos: $e');
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
      _logger.debug('[SupabaseService] Error solicitando match: $e');
      return null;
    }
  }

  /// Verifica el estado actual del match entre dos usuarios.
  /// Devuelve el objeto match si existe, o null si no hay interacción.
  Future<Map<String, dynamic>?> getMatchStatus(String userA, String userB) async {
    try {
      final res = await _supabase
          .from('matches')
          .select()
          .or('and(requester_id.eq.$userA,receiver_id.eq.$userB),and(requester_id.eq.$userB,receiver_id.eq.$userA)')
          .maybeSingle();
      return res;
    } catch (e) {
      _logger.debug('[SupabaseService] Error obteniendo status del match: $e');
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
        final requester = match['requester'] != null ? Map<String, dynamic>.from(match['requester'] as Map) : null;
        final receiver = match['receiver'] != null ? Map<String, dynamic>.from(match['receiver'] as Map) : null;
        
        final otherUser = requester?['id'] == userId ? receiver : requester;
        
        enriched.add({
          ...match,
          'other_user': otherUser,
        });
      }
      return enriched;
    } catch (e) {
      _logger.debug('[SupabaseService] Error obteniendo matches: $e');
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
      _logger.debug('[SupabaseService] Error obteniendo solicitudes match: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────
  //  MENSAJES E2EE
  // ──────────────────────────────────────────────────────────

  /// Envía un mensaje cifrado. Solo funciona si hay un match aceptado.
  /// Retorna true si se guardó en DB correctamente, false si falló.
  Future<bool> sendMessage({
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

    // 1. Insertar en DB con retry (backoff exponencial + jitter)
    bool dbSaved = false;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _supabase.from('messages').insert(payload);
        dbSaved = true;
        _logger.debug('[SupabaseService] Mensaje guardado en DB');
        break;
      } catch (e) {
        _logger.debug('[SupabaseService] Intento ${attempt + 1}/3 falló guardando mensaje: $e');
        if (attempt < 2) {
          final baseDelay = 500 * (1 << attempt);
          final jitter = (baseDelay * 0.5 * (DateTime.now().millisecondsSinceEpoch % 100) / 100).toInt();
          await Future.delayed(Duration(milliseconds: baseDelay + jitter));
        }
      }
    }

    // 2. Enviar via Broadcast para inmediatez (WebSocket puro)
    final normalizedMatchId = matchId.trim().toLowerCase();
    final channelName = 'msgs:$normalizedMatchId';
    
    if (_activeChatChannels.containsKey(channelName)) {
      _logger.debug('[SupabaseService] Enviando Broadcast a canal activo $channelName');
      await _activeChatChannels[channelName]!.sendBroadcastMessage(
        event: 'new_msg',
        payload: payload,
      );
    } else {
      _logger.debug('[SupabaseService] Broadcast falló: Canal no suscrito ($channelName)');
    }

    return dbSaved;
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

  /// Obtiene mensajes paginados (cursor-based).
  Future<List<Map<String, dynamic>>> getMessagesPaginated(
    String matchId, {
    required DateTime before,
    int limit = 50,
  }) async {
    final result = await _supabase
        .from('messages')
        .select()
        .eq('match_id', matchId)
        .lt('created_at', before.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(result).reversed.toList();
  }

  /// Envía múltiples mensajes en lote (para cola offline / outbox Z-007).
  /// IDEMPOTENTE: cada mensaje lleva su id PK estable (UUID v4 generado por el
  /// CLIENTE una sola vez). En los reintentos se reutiliza el MISMO id → el
  /// upsert con ON CONFLICT (id) DO NOTHING lo convierte en no-op. Sin esto un
  /// reintento duplicaría el mensaje (auditoría Z-DUP-*).
  Future<int> sendMessagesBatch(List<Map<String, dynamic>> messages) async {
    int sent = 0;
    for (final msg in messages) {
      final result = await RetryHelper.withRetry<bool>(
        () async {
          // PostgREST `upsert` con onConflict('id') → INSERT ... ON CONFLICT (id)
          // DO NOTHING cuando el payload ya incluye 'id' (cliente estable).
          await _supabase.from('messages').upsert(
            msg,
            onConflict: 'id',
            // ignoreDuplicates solo aplica si el servidor genera el id; aquí el
            // id lo genera el cliente, así que el conflicto cae en DO NOTHING.
          );
          return true;
        },
        maxRetries: 3,
        label: 'batch_msg',
      );
      if (result == true) sent++;
    }
    return sent;
  }

  /// Envía un mensaje de forma idempotente reutilizando el [messageId] que la
  /// app YA generó (PK estable). Si el mensaje ya existe (reintento offline),
  /// el INSERT ... ON CONFLICT (id) DO NOTHING lo ignora → sin duplicados.
  Future<bool> sendMessageIdempotent({
    required String messageId,
    required String matchId,
    required String senderId,
    required String encryptedContent,
    required String nonce,
    required String mac,
    String? p2pMessageId,
  }) async {
    try {
      final payload = {
        'id': messageId,
        'match_id': matchId,
        'sender_id': senderId,
        'encrypted_content': encryptedContent,
        'nonce': nonce,
        'mac': mac,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      await _supabase.from('messages').upsert(payload, onConflict: 'id');
      return true;
    } catch (e) {
      _logger.debug('[SupabaseService] Error enviando mensaje idempotente: $e');
      return false;
    }
  }

  /// Marca un mensaje como entregado para el lector dado.
  /// Z-007: usa RPC SECURITY DEFINER `mark_message_delivered` (gate server-side
  /// auth.uid() == p_reader_id → sin anon, sin exposiciones públicas).
  Future<void> markMessageDelivered(String messageId, String readerId) async {
    try {
      await _supabase.rpc('mark_message_delivered', params: {
        'p_message_id': messageId,
        'p_reader_id': readerId,
      });
    } catch (e) {
      _logger.debug(
          '[SupabaseService] Error marcando mensaje como entregado: $e');
    }
  }

  /// Marca todos los mensajes de un match como LEÍDOS para el lector dado.
  /// Z-007: RPC SECURITY DEFINER `mark_messages_read` — el PK → read_at;
  /// gate auth.uid() == p_reader_id + match aceptado server-side.
  Future<void> markAllMessagesRead(String matchId, String readerId) async {
    try {
      await _supabase.rpc('mark_messages_read', params: {
        'p_match_id': matchId,
        'p_reader_id': readerId,
      });
    } catch (e) {
      _logger.debug(
          '[SupabaseService] Error marcando mensajes como leídos: $e');
    }
  }

  /// Elimina un mensaje propio.
  Future<void> deleteMessage(String messageId) async {
    try {
      await _supabase.from('messages').delete().eq('id', messageId);
    } catch (e) {
      _logger.debug('[SupabaseService] Error eliminando mensaje: $e');
    }
  }

  final Map<String, RealtimeChannel> _activeChatChannels = {};

  /// Desuscribe y limpia el canal de chat para un match dado.
  void unsubscribeFromMessages(String matchId) {
    final normalizedMatchId = matchId.trim().toLowerCase();
    final channelName = 'msgs:$normalizedMatchId';
    final channel = _activeChatChannels.remove(channelName);
    channel?.unsubscribe();
  }

  /// Escucha mensajes en tiempo real para un match activo.
  /// `onMessage` recibe inserciones y broadcasts; `isUpdate` distingue los
  /// eventos UPDATE (receipts `delivered_at`/`read_at`) para que el remitente
  /// repinte su tick Enviado→Entregado→Leído sin tratar el reemplazo como
  /// un mensaje nuevo.
  RealtimeChannel subscribeToMessages(
    String matchId,
    String myUid,
    void Function(Map<String, dynamic> message, {bool isUpdate}) onMessage,
    void Function(bool isOnline)? onPresenceChange,
    void Function(bool isTyping)? onTypingChange,
  ) {
    final normalizedMatchId = matchId.trim().toLowerCase();
    final channelName = 'msgs:$normalizedMatchId';
    
    final channel = _supabase
        .channel(channelName, opts: const RealtimeChannelConfig(self: true));
        
    _activeChatChannels[channelName] = channel;
        
    channel
        // 1. Escuchar BROADCAST (Mensajes instantáneos)
        .onBroadcast(
          event: 'new_msg',
          callback: (eventPayload) {
            _logger.debug('[SupabaseService] Realtime (Broadcast): Mensaje recibido!');
            final rawPayload = eventPayload['payload'];
            final data = rawPayload != null 
                ? Map<String, dynamic>.from(rawPayload as Map) 
                : Map<String, dynamic>.from(eventPayload as Map);
            onMessage(data);
          },
        )
        // 2. Escuchar EVENTOS DE ESCRITURA
        .onBroadcast(
          event: 'typing',
          callback: (eventPayload) {
            final rawPayload = eventPayload['payload'];
            final data = rawPayload != null 
                ? Map<String, dynamic>.from(rawPayload as Map) 
                : Map<String, dynamic>.from(eventPayload as Map);
            final senderId = data['sender_id'];
            final isTyping = data['is_typing'] as bool? ?? false;
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
              for (final p in e.presences) {
                try {
                  final dynamic pl = (p as dynamic).payload;
                  if (pl != null && pl['uid'] != null && pl['uid'] != myUid) return true;
                } catch (_) {}
              }
              return false;
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
        )
        // 5. Escuchar UPDATEs de RECEIPTS (Z-105, FASE 1.7): cuando el otro
        //    participante marca entregado/leído un mensaje, `delivered_at`/
        //    `read_at` cambian vía RPC. Sin este listener, el remitente seguía
        //    viendo "Enviado" para siempre. El merge lo hace el chat (isUpdate).
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final updRec = payload.newRecord;
            final hasReceipt =
                updRec['delivered_at'] != null || updRec['read_at'] != null;
            if (!hasReceipt) return;
            final recMatchId = (updRec['match_id'] as String?)?.trim().toLowerCase();
            if (recMatchId == normalizedMatchId) {
              onMessage(updRec, isUpdate: true);
            }
          },
        );

    channel.subscribe((status, [error]) async {
      _logger.debug('[SupabaseService] Estado suscripción mensajes ($normalizedMatchId): $status');
      if (status == RealtimeSubscribeStatus.subscribed) {
        // Al conectarnos, trackeamos nuestra presencia
        await channel.track({'uid': myUid, 'online_at': DateTime.now().toIso8601String()});
      }
      if (error != null) {
        _logger.debug('[SupabaseService] ERROR suscripción mensajes: $error');
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
      _logger.debug('[SupabaseService] Error obteniendo usuarios bloqueados: $e');
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

  /// Busca un perfil por ZONE-ID público (vía v_profile, Z-002: filtros
  /// server-side: shadowban, bloqueos bidireccionales y privacidad avatar/handles).
  Future<Map<String, dynamic>?> getProfileByZoneId(String zoneId) async {
    final result = await _supabase
        .from('v_profile')
        .select()
        .eq('zone_id', zoneId)
        .maybeSingle();

    if (result == null) return null;
    if (result['stealth_mode'] == true) return null;

    // Z-002: el servidor ya NULIFICA handles/avatar no públicos; no re-filtrar.
    return result;
  }

  /// Obtiene todos los usuarios activos recientemente (últimos 24h) para el radar global.
  /// Esto permite descubrir usuarios incluso cuando no están en rango BLE directo.
  Future<List<Map<String, dynamic>>> getActiveUsersForRadar() async {
    try {
      // Primero intentar usar la función optimizada RPC
      try {
        final rpcResult = await _supabase.rpc('get_active_users_for_radar', params: {'p_limit': 1000});
        if (rpcResult != null && rpcResult is List) {
          return List<Map<String, dynamic>>.from(rpcResult);
        }
      } catch (e) {
        _logger.debug('[SupabaseService] RPC get_active_users_for_radar no disponible, usando fallback: $e');
      }
      
      // Fallback: Consulta directa con índices optimizados (vista v_profile,
      // Z-002: shadowban/bloqueos/privacidad ya filtrados server-side)
      final since = DateTime.now().subtract(const Duration(hours: 24)).toUtc().toIso8601String();
      final result = await _supabase
          .from('v_profile')
          .select('id, zone_id, display_name, avatar_url, public_key, stealth_mode, updated_at')
          .eq('stealth_mode', false)
          .gte('updated_at', since)
          .order('updated_at', ascending: false)
          .limit(1000);
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      _logger.debug('[SupabaseService] Error obteniendo usuarios activos: $e');
      return [];
    }
  }

  /// Actualiza la actividad de Bluetooth del usuario actual
  Future<void> updateBtActivity() async {
    try {
      await _supabase.rpc('update_bt_activity');
    } catch (e) {
      _logger.debug('[SupabaseService] Error actualizando actividad BT: $e');
    }
  }

  /// Obtiene perfiles modificados recientemente (últimas 24h) para pull sync.
  /// Z-002: vista v_profile (filtros server-side). Nota: 'bio' se elimina del
  /// SELECT porque la columna no existe en public.users en remoto (400).
  Future<List<Map<String, dynamic>>> getRecentlyActiveProfiles() async {
    try {
      final since = DateTime.now()
          .subtract(const Duration(hours: 24))
          .toUtc()
          .toIso8601String();
      final result = await _supabase
          .from('v_profile')
          .select('id, zone_id, display_name, avatar_url, public_key, '
              'instagram_handle, facebook_handle, tiktok_handle, '
              'ig_visible, fb_visible, tiktok_visible, '
              'updated_at, created_at')
          .eq('stealth_mode', false)
          .gte('updated_at', since)
          .order('updated_at', ascending: false)
          .limit(200);
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      _logger.debug('[SupabaseService] Error obteniendo perfiles activos: $e');
      return [];
    }
  }

  /// Obtiene estadísticas del radar para monitoreo interno/debugging.
  /// No es llamado desde ninguna pantalla — disponible para herramientas de diagnóstico.
  Future<Map<String, dynamic>?> getRadarStats() async {
    try {
      final result = await _supabase.rpc('get_radar_stats');
      if (result != null) {
        return Map<String, dynamic>.from(result as Map);
      }
    } catch (e) {
      _logger.debug('[SupabaseService] Error obteniendo estadísticas: $e');
    }
    return null;
  }

  RealtimeChannel? _globalMessagesChannel;
  RealtimeChannel? _globalMatchesChannel;

  /// Detiene las escuchas globales de notificaciones.
  void stopGlobalNotificationListener() {
    _globalMessagesChannel?.unsubscribe();
    _globalMessagesChannel = null;
    _globalMatchesChannel?.unsubscribe();
    _globalMatchesChannel = null;
  }

  /// Escucha notificaciones globales (mensajes y nuevos matches) para el usuario.
  void startGlobalNotificationListener(String myUid) {
    stopGlobalNotificationListener();
    _logger.debug('[SupabaseService] Iniciando escucha global de notificaciones para $myUid');

    // 1. Escuchar Nuevos Mensajes en cualquier match
    _globalMessagesChannel = _supabase
        .channel('global_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            _logger.debug('[SupabaseService] Notificación Global: Mensaje detectado');
            final msg = payload.newRecord;
            final senderId = msg['sender_id'] as String?;
            final matchId = msg['match_id'] as String?;

            if (senderId != null && senderId != myUid) {
              if (NotificationService.currentActiveMatchId != matchId) {
                _logger.debug('[SupabaseService] Mostrando notificación de mensaje...');
                NotificationService().showMessageNotification('Alguien', 'Te ha enviado un mensaje seguro.');
              } else {
                _logger.debug('[SupabaseService] Notificación omitida (chat abierto)');
              }
            }
          },
        )
        .subscribe((status, [error]) {
          _logger.debug('[SupabaseService] Estado canal global_messages: $status');
          if (error != null) _logger.debug('[SupabaseService] Error global_messages: $error');
        });

    // 2. Escuchar Nuevos Matches (Solicitudes)
    _globalMatchesChannel = _supabase
        .channel('global_matches')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'matches',
          callback: (payload) {
            _logger.debug('[SupabaseService] Notificación Global: Match detectado');
            final match = payload.newRecord;
            final receiverId = match['receiver_id'] as String?;
            if (receiverId == myUid) {
              _logger.debug('[SupabaseService] Mostrando notificación de solicitud...');
              NotificationService().showMatchRequestNotification('Un usuario cercano');
            }
          },
        )
        .subscribe((status, [error]) {
          _logger.debug('[SupabaseService] Estado canal global_matches: $status');
          if (error != null) _logger.debug('[SupabaseService] Error global_matches: $error');
        });
  }
}
