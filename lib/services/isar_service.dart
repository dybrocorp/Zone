import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/isar_models.dart';

/// Servicio para la base de datos local Isar.
/// Optimizada para Mesh Networks y CRDTs.
class IsarService {
  static final IsarService _instance = IsarService._internal();
  factory IsarService() => _instance;
  IsarService._internal();

  late Isar isar;

  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    isar = await Isar.open([
      LocalProfileSchema,
      LocalEncounterSchema,
      LocalMessageSchema,
      MeshRouteSchema,
      LocalPendingMessageSchema,
      // PHASE 2.2.5: outbox durable de mutaciones de match.
      LocalMatchOperationSchema,
    ], directory: dir.path);
  }

  // ──────────────────────────────────────────────────────────
  //  PROFILES (CRDT: Last Write Wins)
  // ──────────────────────────────────────────────────────────

  Future<void> saveProfile(Map<String, dynamic> data) async {
    // Z-212: el perfil remoto es input no confiable. Sin un users.id estable
    // no se persiste (antes `userId` null reventaba Isar o envenenaba el LWW).
    final rawUserId = data['id'] ?? data['userId'];
    if (rawUserId is! String || rawUserId.trim().isEmpty) return;
    final userId = rawUserId.trim();

    final now = DateTime.now().toUtc();
    final rawUpdatedAt = data['updatedAt'] ?? data['updated_at'];
    var newUpdatedAt = now;
    if (rawUpdatedAt is String) {
      try {
        newUpdatedAt = DateTime.parse(rawUpdatedAt).toUtc();
      } catch (_) {
        newUpdatedAt = now;
      }
    }
    // Un timestamp futuro lejano ganaría TODOS los LWW para siempre. Se
    // tolera un margen pequeño de reloj y se normaliza el resto a `now`.
    final maxAccepted = now.add(const Duration(minutes: 5));
    if (newUpdatedAt.isAfter(maxAccepted)) newUpdatedAt = now;

    final rawZoneId = data['zone_id'] ?? data['zoneId'];
    final zoneId = rawZoneId is String && rawZoneId.trim().isNotEmpty
        ? rawZoneId.trim().toUpperCase()
        : null;

    await isar.writeTxn(() async {
      final existing = await isar.localProfiles
          .filter()
          .userIdEqualTo(userId)
          .findFirst();

      // CRDT Logic: Last Write Wins (LWW)
      if (existing != null &&
          existing.updatedAt.toUtc().isAfter(newUpdatedAt)) {
        return;
      }

      final resolvedZoneId = zoneId ?? existing?.zoneId;
      if (resolvedZoneId == null || resolvedZoneId.isEmpty) return;

      final profile = (existing ?? LocalProfile())
        ..userId = userId
        ..zoneId = resolvedZoneId
        ..displayName = data['display_name'] ?? data['displayName']
        ..avatarUrl = data['avatar_url'] ?? data['avatarUrl']
        ..bio = data['bio']
        ..instagramHandle = data['instagram_handle']
        ..facebookHandle = data['facebook_handle']
        ..tiktokHandle = data['tiktok_handle']
        ..publicKey =
            data['public_key'] ?? data['publicKey'] ?? existing?.publicKey
        ..lastSeen = now
        ..updatedAt = newUpdatedAt;

      await isar.localProfiles.putByUserId(profile);
    });
  }

  Future<LocalProfile?> getProfile(String zoneId) async {
    return await isar.localProfiles.filter().zoneIdEqualTo(zoneId).findFirst();
  }

  Future<LocalProfile?> getProfileByUserId(String userId) async {
    return await isar.localProfiles.filter().userIdEqualTo(userId).findFirst();
  }

  // ──────────────────────────────────────────────────────────
  //  ENCOUNTERS
  // ──────────────────────────────────────────────────────────

  /// PHASE 2.2.3 — idempotent encounter recording.
  ///
  /// - Con `encounterKey` (filas nuevas): si ya existe una fila con la misma
  ///   clave canónica, no se inserta nada (first-wins). La comprobación y la
  ///   inserción ocurren en UNA `writeTxn` (atómica y serializada por Isar),
  ///   de modo que callbacks concurrentes de descubrimiento no duplican.
  /// - Sin clave (filas históricas / rutas sin identidad verificada): dedup
  ///   por bucket horario UTC sobre (userId, otherZoneId, seenAt). Las filas
  ///   existentes NUNCA se borran ni se reescriben aquí.
  Future<void> saveEncounter({
    required String userId,
    required String otherZoneId,
    bool isSynced = false,
    String? encounterKey,
  }) async {
    final now = DateTime.now();
    await isar.writeTxn(() async {
      if (encounterKey != null && encounterKey.isNotEmpty) {
        final dup = await isar.localEncounters
            .filter()
            .encounterKeyEqualTo(encounterKey)
            .findFirst();
        if (dup != null) return;
      } else {
        final bucketStart = DateTime.utc(
          now.toUtc().year,
          now.toUtc().month,
          now.toUtc().day,
          now.toUtc().hour,
        );
        final dup = await isar.localEncounters
            .filter()
            .userIdEqualTo(userId)
            .otherZoneIdEqualTo(otherZoneId)
            .seenAtGreaterThan(bucketStart)
            .findFirst();
        if (dup != null) return;
      }

      final encounter = LocalEncounter()
        ..userId = userId
        ..otherZoneId = otherZoneId
        ..seenAt = now
        ..encounterKey = (encounterKey == null || encounterKey.isEmpty)
            ? null
            : encounterKey
        ..isSynced = isSynced;

      await isar.localEncounters.put(encounter);
    });
  }

  Future<List<LocalEncounter>> getUnsyncedEncounters() async {
    return await isar.localEncounters.filter().isSyncedEqualTo(false).findAll();
  }

  Future<void> markEncounterSynced(int id) async {
    await isar.writeTxn(() async {
      final encounter = await isar.localEncounters.get(id);
      if (encounter != null) {
        encounter.isSynced = true;
        await isar.localEncounters.put(encounter);
      }
    });
  }

  // ──────────────────────────────────────────────────────────
  //  MESH ROUTES
  // ──────────────────────────────────────────────────────────

  Future<void> updateRoute(
    String targetZoneId,
    String nextHop,
    int distance,
  ) async {
    final route = MeshRoute()
      ..targetZoneId = targetZoneId
      ..nextHopEndpointId = nextHop
      ..distance = distance
      ..lastUpdate = DateTime.now();

    await isar.writeTxn(() async {
      await isar.meshRoutes.putByTargetZoneId(route);
    });
  }

  Future<MeshRoute?> getRoute(String targetZoneId) async {
    return await isar.meshRoutes
        .filter()
        .targetZoneIdEqualTo(targetZoneId)
        .findFirst();
  }

  Future<List<MeshRoute>> getRecentRoutes({
    Duration maxAge = const Duration(minutes: 30),
  }) async {
    final cutoff = DateTime.now().subtract(maxAge);
    return await isar.meshRoutes
        .filter()
        .lastUpdateGreaterThan(cutoff)
        .findAll();
  }

  // ──────────────────────────────────────────────────────────
  //  MESSAGES
  // ──────────────────────────────────────────────────────────

  Future<void> saveMessage(LocalMessage msg) async {
    await isar.writeTxn(() async {
      await isar.localMessages.putByMessageId(msg);
    });
  }

  Future<List<LocalMessage>> getMessages(String matchId) async {
    return await isar.localMessages
        .filter()
        .matchIdEqualTo(matchId)
        .sortByCreatedAt()
        .findAll();
  }

  Future<List<LocalMessage>> getUnsyncedMessages() async {
    return await isar.localMessages.filter().isSyncedEqualTo(false).findAll();
  }

  Future<void> markMessageSynced(int id) async {
    await isar.writeTxn(() async {
      final message = await isar.localMessages.get(id);
      if (message != null) {
        message.isSynced = true;
        await isar.localMessages.put(message);
      }
    });
  }

  /// Elimina todos los datos locales de Isar.
  /// Usado durante eliminación de cuenta o logout seguro.
  Future<void> clearAll() async {
    await isar.writeTxn(() async {
      await isar.localProfiles.clear();
      await isar.localEncounters.clear();
      await isar.localMessages.clear();
      await isar.meshRoutes.clear();
      await isar.localPendingMessages.clear();
    });
  }

  // ──────────────────────────────────────────────────────────
  //  PENDING MESSAGES (Cola offline)
  // ──────────────────────────────────────────────────────────

  Future<void> savePendingMessage({
    required String tempId,
    required String messageId,
    required String matchId,
    required String senderId,
    required String encryptedContent,
    required String nonce,
    required String mac,
  }) async {
    final pending = LocalPendingMessage()
      ..tempId = tempId
      ..messageId = messageId
      ..matchId = matchId
      ..senderId = senderId
      ..encryptedContent = encryptedContent
      ..nonce = nonce
      ..mac = mac;

    await isar.writeTxn(() async {
      await isar.localPendingMessages.putByTempId(pending);
    });
  }

  Future<List<LocalPendingMessage>> getPendingMessages() async {
    return await isar.localPendingMessages.where().findAll();
  }

  Future<List<LocalPendingMessage>> getPendingMessagesForMatch(String matchId) async {
    return await isar.localPendingMessages
        .filter()
        .matchIdEqualTo(matchId)
        .findAll();
  }

  /// Z-212: recupera la fila del outbox por su tempId para reintentos
  /// idempotentes (reutiliza el messageId estable, nunca genera uno nuevo).
  Future<LocalPendingMessage?> getPendingMessage(String tempId) async {
    return await isar.localPendingMessages
        .filter()
        .tempIdEqualTo(tempId)
        .findFirst();
  }

  Future<void> deletePendingMessage(String tempId) async {
    await isar.writeTxn(() async {
      final pending = await isar.localPendingMessages
          .filter()
          .tempIdEqualTo(tempId)
          .findFirst();
      if (pending != null) {
        await isar.localPendingMessages.delete(pending.id);
      }
    });
  }

  Future<void> incrementRetryCount(String tempId) async {
    await isar.writeTxn(() async {
      final pending = await isar.localPendingMessages
          .filter()
          .tempIdEqualTo(tempId)
          .findFirst();
      if (pending != null) {
        pending.retryCount++;
        await isar.localPendingMessages.put(pending);
      }
    });
  }
}
