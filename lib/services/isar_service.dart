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
    ], directory: dir.path);
  }

  // ──────────────────────────────────────────────────────────
  //  PROFILES (CRDT: Last Write Wins)
  // ──────────────────────────────────────────────────────────

  Future<void> saveProfile(Map<String, dynamic> data) async {
    final userId = data['id'] ?? data['userId'];
    final updatedAtStr = data['updatedAt'] as String?;
    final newUpdatedAt = updatedAtStr != null
        ? DateTime.parse(updatedAtStr)
        : DateTime.now();

    await isar.writeTxn(() async {
      final existing = await isar.localProfiles
          .filter()
          .userIdEqualTo(userId)
          .findFirst();

      // CRDT Logic: Last Write Wins (LWW)
      if (existing != null && existing.updatedAt.isAfter(newUpdatedAt)) {
        return;
      }

      final profile = (existing ?? LocalProfile())
        ..userId = userId
        ..zoneId = data['zone_id'] ?? data['zoneId']
        ..displayName = data['display_name'] ?? data['displayName']
        ..avatarUrl = data['avatar_url'] ?? data['avatarUrl']
        ..bio = data['bio']
        ..instagramHandle = data['instagram_handle']
        ..facebookHandle = data['facebook_handle']
        ..tiktokHandle = data['tiktok_handle']
        ..publicKey =
            data['public_key'] ?? data['publicKey'] ?? existing?.publicKey
        ..lastSeen = DateTime.now()
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

  Future<void> saveEncounter({
    required String userId,
    required String otherZoneId,
    bool isSynced = false,
  }) async {
    final encounter = LocalEncounter()
      ..userId = userId
      ..otherZoneId = otherZoneId
      ..seenAt = DateTime.now()
      ..isSynced = isSynced;

    await isar.writeTxn(() async {
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
