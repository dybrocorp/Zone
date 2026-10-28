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

  /// PHASE 2.2.3 — canonical encounter key (`ZEN-1:<sha256 hex>`), derivado
  /// del par ordenado de ZONE-IDs + bucket horario UTC. Nulo SOLO en filas
  /// históricas previas a esta fase (legibles y sincronizables como antes);
  /// las filas nuevas siempre lo llevan. Ver `lib/services/encounter_key.dart`.
  @Index()
  String? encounterKey;

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

/// PHASE 2.2.5 — Outbox durable de mutaciones de match (offline-first).
///
/// Misma filosofía que `LocalPendingMessage` (Z-007) aplicada a matches:
/// identidad de operación ESTABLE y determinista (`operationId`), reemplazo
/// idempotente por clave (`putByOperationId`), borrado al completar, filas
/// `failed` conservadas para diagnóstico/reintento manual. Ver
/// `lib/services/match_outbox.dart` (identidad, backoff, clasificación) y
/// `lib/services/match_outbox_processor.dart` (replay convergente).
///
/// La fila NO contiene secretos: solo UUIDs públicos, tipo/estado/contadores
/// y un código corto de error. El `serverMatchId` real solo se conoce tras
/// confirmación del backend — jamás se inventa localmente.
@collection
class LocalMatchOperation {
  Id id = Isar.autoIncrement;

  /// Identidad estable de la operación:
  /// request `mr:<low>:<high>:<requester>:<receiver>`,
  /// accept `ma:<serverMatchId>:<actor>`, reject `mj:<serverMatchId>:<actor>`.
  @Index(unique: true, replace: true)
  late String operationId;

  /// `request` | `accept` | `reject`.
  late String operationType;

  /// Par canónico Phase 2.2.4 (min/max de los UUIDs de `users.id`).
  @Index()
  late String canonicalLow;

  @Index()
  late String canonicalHigh;

  /// Actor (quien pidió / receiver que acepta-rechaza). UUID de `users.id`.
  @Index()
  late String actorUserId;

  /// Solo `request`: el otro participante.
  String? targetUserId;

  /// Solo `accept`/`reject`: id del match en el servidor. Nulo hasta que el
  /// servidor lo confirma (requests offline) o conocido (accept/reject de
  /// filas ya sincronizadas).
  String? serverMatchId;

  /// `pending` | `inflight` | `failed`.
  @Index()
  late String state;

  int retryCount = 0;

  /// Próximo intento permitido (backoff). Nulo = procesable de inmediato.
  DateTime? nextAttemptAt;

  late DateTime createdAt;

  /// Código corto de último fallo (`network`, `server`, `auth`, `malformed`,
  /// `missing`, `state`, `conflict`). Nunca texto crudo de excepciones.
  String? lastErrorCode;
}
