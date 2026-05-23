import 'package:isar/isar.dart';

part 'isar_models.g.dart';

@collection
class LocalProfile {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String userId;

  @Index(unique: true)
  late String zoneId;

  String? displayName;
  String? avatarUrl;
  String? bio;
  
  String? instagramHandle;
  String? facebookHandle;
  String? tiktokHandle;

  String? publicKey; // X25519 Public Key (Base64)
  String? sessionKey; // Derived Shared Secret (Base64)

  DateTime? lastSeen;
  
  // Para CRDT - Last Write Wins
  int version = 0;
  DateTime updatedAt = DateTime.now();

  bool isSynced = true;
}

@collection
class LocalEncounter {
  Id id = Isar.autoIncrement;

  late String userId; // Mi ID
  late String otherZoneId;
  
  @Index()
  late DateTime seenAt;

  double? latitude;
  double? longitude;

  bool isSynced = false;
}

@collection
class LocalMessage {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String messageId;

  @Index()
  late String matchId;

  late String senderId;
  late String receiverId;

  late String encryptedContent;
  late String nonce;
  late String mac;

  @Index()
  late DateTime createdAt;

  bool isP2p = false;
  bool isSynced = false;

  // Para Mesh Routing
  int hopCount = 0;
}

@collection
class MeshRoute {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String targetZoneId;

  @Index()
  late String nextHopEndpointId;

  int distance = 1; // Número de saltos
  DateTime lastUpdate = DateTime.now();
}
