import 'package:supabase_flutter/supabase_flutter.dart';
import 'logger_service.dart';
import 'match_pair.dart';
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
  ///
  /// Z-212: SOLO vía RPC `resolve_bt_token` (SECURITY DEFINER, sesión exigida
  /// y visibilidad aplicada server-side). Se eliminó el fallback de SELECT
  /// directo sobre `bt_tokens`: dependía de una política amplia que exponía el
  /// mapping token → user_id de todos los usuarios activos. Si la RPC no está
  /// desplegada, la resolución falla cerrada (null), nunca insegura.
  Future<Map<String, dynamic>?> resolveToken(String token) async {
    if (token.isEmpty || token == 'ZONE-INIT') return null;

    try {
      final rpcResult =
          await _supabase.rpc('resolve_bt_token', params: {'p_token': token});
      if (rpcResult is! Map) return null;
      return Map<String, dynamic>.from(rpcResult);
    } catch (e) {
      _logger.debug(
        '[SupabaseService] resolve_bt_token no disponible (fail-closed): $e',
      );
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
  ///
  /// PHASE 2.2.3 — con `encounterKey` se usa UPSERT sobre el conflicto
  /// (`user_id`, `encounter_key`): reintentos y sincronizaciones repetidas no
  /// crean filas nuevas (requiere la migración `z210_encounter_key.sql`).
  /// Sin clave (filas históricas) se mantiene el INSERT clásico; el índice
  /// horario existente sigue absorbiendo duplicados. RLS sin cambios.
  ///
  /// Z-212: devuelve `true` solo si el servidor aceptó la fila. Antes se
  /// tragaba cualquier error y `_syncEncounters` marcaba el encuentro como
  /// sincronizado aunque RLS/red lo hubieran rechazado (pérdida silenciosa).
  Future<bool> registerEncounter(
    String userId,
    String otherZoneId, {
    String? encounterKey,
  }) async {
    try {
      final row = {
        'user_id': userId,
        'other_zone_id': otherZoneId,
        'seen_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (encounterKey != null && encounterKey.isNotEmpty) {
        row['encounter_key'] = encounterKey;
        await _supabase
            .from('encounters')
            .upsert(row, onConflict: 'user_id,encounter_key');
      } else {
        await _supabase.from('encounters').insert(row);
      }
      return true;
    } catch (e) {
      _logger.debug('[SupabaseService] Error registrando encuentro: $e');
      return false;
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
  ///
  /// PHASE 2.2.4 — deterministic + duplicate-safe + retry-safe:
  /// - CASE 1 (ninguno) → inserta pending, devuelve id válido.
  /// - CASE 2/4 (reintento misma dirección / pending existente) → reutiliza.
  /// - CASE 3 (B→A tras A→B) → MISMO match, sin duplicado (unicidad canónica
  ///   `uq_matches_canonical_pair` + lookup bidireccional).
  /// - CASE 5 (accepted) → reutiliza, NUNCA degrada a pending.
  /// - CASE 6 (rejected) → elimina la fila rechazada y crea una nueva
  ///   (re-request explícito; precede `deleteMatch` con cascada).
  /// - Conflicto concurrente (el reverso ganó la carrera) → recupera el
  ///   canónico existente y devuelve SU id. NULL solo ante fallo real.
  /// `requester_id`/`receiver_id` conservan la dirección (quién acepta).
  Future<String?> requestMatch(String requesterId, String receiverId) async {
    if (requesterId.trim().isEmpty ||
        receiverId.trim().isEmpty ||
        requesterId.trim() == receiverId.trim()) {
      _logger.debug('[SupabaseService] requestMatch inválido (vacío/auto).');
      return null;
    }
    try {
      final existing = await getMatchStatus(requesterId, receiverId);
      final decision = MatchPair.decide(
        existing: existing,
        requesterId: requesterId,
        receiverId: receiverId,
      );
      switch (decision.action) {
        case MatchRequestAction.reuse:
          return decision.matchId;
        case MatchRequestAction.recreate:
          try {
            await deleteMatch(decision.matchId!);
          } catch (e) {
            _logger.debug('[SupabaseService] No se pudo limpiar rejected: $e');
          }
          break;
        case MatchRequestAction.create:
          break;
      }
      try {
        final result = await _supabase.from('matches').insert({
          'requester_id': requesterId,
          'receiver_id': receiverId,
          'status': 'pending',
        }).select('id').single();
        return result['id'] as String;
      } catch (e) {
        // Conflicto (carrera reversa) o transitorio: recuperar el canónico.
        _logger.debug('[SupabaseService] Insert en conflicto, recuperando: $e');
        final recovered = await getMatchStatus(requesterId, receiverId);
        final id = recovered?['id'] as String?;
        return MatchPair.isValidMatchId(id) ? id : null;
      }
    } catch (e) {
      _logger.debug('[SupabaseService] Error solicitando match: $e');
      return null;
    }
  }

  /// Verifica el estado actual del match entre dos usuarios.
  /// Devuelve el objeto match si existe, o null si no hay interacción.
  ///
  /// PHASE 2.2.4 — independiente de la dirección: el `.or()` cubre ambas, y el
  /// orden determinista (earliest primero, `limit(1)`) tolera filas históricas
  /// duplicadas en lugar de lanzar como hacía `maybeSingle()` en solitario.
  Future<Map<String, dynamic>?> getMatchStatus(String userA, String userB) async {
    try {
      final res = await _supabase
          .from('matches')
          .select()
          .or('and(requester_id.eq.$userA,receiver_id.eq.$userB),and(requester_id.eq.$userB,receiver_id.eq.$userA)')
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();
      return res;
    } catch (e) {
      _logger.debug('[SupabaseService] Error obteniendo status del match: $e');
      return null;
    }
  }

  /// Obtiene un match por id (legible solo por participantes vía RLS).
  /// PHASE 2.2.5: el replay del outbox lo usa para clasificar fallos
  /// (ausente ⇒ terminal; presente ⇒ re-chequear autorización/estado).
  Future<Map<String, dynamic>?> getMatchById(String matchId) async {
    try {
      final res = await _supabase
          .from('matches')
          .select()
          .eq('id', matchId)
          .maybeSingle();
      return res;
    } catch (e) {
      _logger.debug('[SupabaseService] Error obteniendo match: $e');
      return null;
    }
  }

  /// Acepta un match pendiente. Solo el receiver (espejo client-side de RLS;
  /// RLS sigue siendo autoritativo). Idempotente: un accepted existente
  /// devuelve true sin reescribir. Devuelve false si no hay fila, no hay
  /// autorización o falla la operación — nunca lanza (los llamadores UI no
  /// capturan excepciones aquí).
  Future<bool> acceptMatch(String matchId) async {
    try {
      final me = _supabase.auth.currentUser?.id;
      final row = await _supabase
          .from('matches')
          .select('id,requester_id,receiver_id,status')
          .eq('id', matchId)
          .maybeSingle();
      if (row == null || me == null) return false;
      if (!MatchPair.canAccept(row, me)) return false;
      if (row['status'] == 'accepted') return true;
      await _supabase
          .from('matches')
          .update({'status': 'accepted'})
          .eq('id', matchId);
      return true;
    } catch (e) {
      _logger.debug('[SupabaseService] Error aceptando match: $e');
      return false;
    }
  }

  /// Rechaza un match. Solo el receiver (espejo de RLS). Idempotente y sin
  /// excepciones, igual que [acceptMatch].
  Future<bool> rejectMatch(String matchId) async {
    try {
      final me = _supabase.auth.currentUser?.id;
      final row = await _supabase
          .from('matches')
          .select('id,requester_id,receiver_id,status')
          .eq('id', matchId)
          .maybeSingle();
      if (row == null || me == null) return false;
      if (!MatchPair.canReject(row, me)) return false;
      if (row['status'] == 'rejected') return true;
      await _supabase
          .from('matches')
          .update({'status': 'rejected'})
          .eq('id', matchId);
      return true;
    } catch (e) {
      _logger.debug('[SupabaseService] Error rechazando match: $e');
      return false;
    }
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
  /// upsert con ON CONFLICT (id) DO NOTHING lo convierte en no-op.
  ///
  /// Devuelve el conjunto de `id`s confirmados por el servidor. El llamador
  /// debe borrar del outbox SOLO esos ids (antes se asumía que los primeros N
  /// habían entrado, perdiendo mensajes cuando un fallo era no contiguo).
  Future<Set<String>> sendMessagesBatch(
    List<Map<String, dynamic>> messages,
  ) async {
    final sent = <String>{};
    for (final msg in messages) {
      final id = msg['id'];
      if (id is! String || id.isEmpty) continue;
      final result = await RetryHelper.withRetry<bool>(
        () async {
          // PostgREST `upsert` + ignoreDuplicates → ON CONFLICT (id) DO NOTHING.
          await _supabase.from('messages').upsert(
            msg,
            onConflict: 'id',
            ignoreDuplicates: true,
          );
          return true;
        },
        maxRetries: 3,
        label: 'batch_msg',
      );
      if (result == true) sent.add(id);
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
      await _supabase.from('messages').upsert(
        payload,
        onConflict: 'id',
        ignoreDuplicates: true,
      );
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
