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

  // Z-007: estado de entrega/lectura (sync con columnas remotas delivered_at/read_at)
  DateTime? deliveredAt;
  DateTime? readAt;

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

@collection
class LocalPendingMessage {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String tempId;

  /// Z-007: PK estable y único generado por el CLIENTE (UUID v4).
  /// Es el MISMO id que se usa como PK en la tabla remota `messages`, de modo
  /// que los reintentos del outbox reutilizan el id → INSERT idempotente
  /// (upsert con ignoreDuplicates / ON CONFLICT (id) DO NOTHING).
  @Index(unique: true, replace: true)
  late String messageId;

  @Index()
  late String matchId;

  late String senderId;
  late String encryptedContent;
  late String nonce;
  late String mac;

  int retryCount = 0;
  DateTime createdAt = DateTime.now();
}
