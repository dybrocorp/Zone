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
    isar = await Isar.open(
      [LocalProfileSchema, LocalEncounterSchema, LocalMessageSchema, MeshRouteSchema],
      directory: dir.path,
    );
  }

  // ──────────────────────────────────────────────────────────
  //  PROFILES (CRDT: Last Write Wins)
  // ──────────────────────────────────────────────────────────

  Future<void> saveProfile(Map<String, dynamic> data) async {
    final userId = data['id'] ?? data['userId'];
    final updatedAtStr = data['updatedAt'] as String?;
    final newUpdatedAt = updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now();

    await isar.writeTxn(() async {
      final existing = await isar.localProfiles.filter().userIdEqualTo(userId).findFirst();
      
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
        ..publicKey = data['publicKey'] ?? existing?.publicKey
        ..sessionKey = data['sessionKey'] ?? existing?.sessionKey
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

  Future<void> updateRoute(String targetZoneId, String nextHop, int distance) async {
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
    return await isar.meshRoutes.filter().targetZoneIdEqualTo(targetZoneId).findFirst();
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
    return await isar.localMessages.filter().matchIdEqualTo(matchId).sortByCreatedAt().findAll();
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
}
