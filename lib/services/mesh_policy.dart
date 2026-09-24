/// Z-003 (FASE 1.4) + Z-005 (FASE 1.6) · Política fail-closed del mesh —
/// decisión CTO 2026-09-23.
///
/// La malla NUNCA transporta texto en claro para mensajes `mesh_msg`:
///  - **Emisor:** si no hay llave de sesión o el cifrado falla, el mensaje se
///    ENCOLA (nunca se envía en claro) y se reintenta al derivarse la llave.
///  - **Relay/receptor:** los paquetes con `isEncrypted != true` se descartan.
///
/// Z-005: identidad única del mensaje (`msgId` UUID v4, sin colisiones por
/// epoch) y deduplicación LRU con TTL en lugar del set con `clear()` global
/// (que permitía replay tras reinicio). Sin criptografía nueva: reutiliza la
/// derivación X25519/ECDH y el cifrado AEAD existentes.
library;

import 'package:uuid/uuid.dart';

/// Decisión del emisor al intentar enviar un mensaje mesh.
enum MeshSendDecision {
  /// Hay llave de sesión y el cifrado tuvo éxito → enviar paquete cifrado.
  encryptAndSend,

  /// No hay llave (o el cifrado falló) → NO enviar; colas para reintento.
  queueForKey,
}

/// Decisión de propagación del relay/receptor.
enum MeshRelayDecision {
  /// Reenviar/aceptar (paquete cifrado válido).
  relay,

  /// Descartar y registrar (paquete en claro — fail-closed).
  dropPlaintext,
}

/// Mensaje mesh pendiente de llave de sesión (cola fail-closed).
class MeshPendingMessage {
  final String targetZoneId;
  final String message;
  final DateTime queuedAt;

  const MeshPendingMessage({
    required this.targetZoneId,
    required this.message,
    required this.queuedAt,
  });
}

/// Evento de estado de la cola mesh (observabilidad / hook de UX).
enum MeshStatusKind { queued, flushed }

class MeshStatusEvent {
  final MeshStatusKind kind;
  final String targetZoneId;

  const MeshStatusEvent(this.kind, this.targetZoneId);
}

/// Z-005 · Deduplicación de mensajes mesh: LRU con TTL (sin `clear()` global).
///
/// Sustituye al `Set<String>` + `clear()` cuando se supera el tope: cada
/// entrada tiene timestamp y caduca por TTL; al superar `maxEntries` se
/// descarta SOLO la entrada más antigua (nunca todo el set), cerrando el
/// vector de replay de los FASE 0.
class MeshDedup {
  MeshDedup({
    this.maxEntries = 500,
    this.ttl = const Duration(minutes: 15),
  });

  /// Tope de entradas vivas (LRU).
  final int maxEntries;

  /// Ventana de deduplicación: entradas más viejas caducan y se olvidan.
  final Duration ttl;

  final Map<String, DateTime> _seen = {};

  /// Devuelve `true` si `id` ya fue visto dentro de la ventana TTL.
  /// NO inserta: solo consulta (inserción a cargo del llamador).
  bool contains(String id) {
    _prune();
    return _seen.containsKey(id);
  }

  /// Registra `id`. Devuelve `false` si ya existía dentro de la ventana
  /// (duplicado) y `true` si es la primera vez (registrado con éxito).
  /// Nunca elimina todo el set: eviction LRU de la entrada más antigua.
  bool register(String id) {
    _prune();
    if (_seen.containsKey(id)) return false;
    _seen[id] = DateTime.now();
    _evictOldestIfNeeded();
    return true;
  }

  /// Caduca las entradas con más de [ttl] de antigüedad (ventana deslizante
  /// horaria por TTL — see FASE 0 Z-005).
  void _prune() {
    final now = DateTime.now();
    _seen.removeWhere((_, ts) => now.difference(ts) > ttl);
  }

  /// Eviction LRU: descarta SOLO la entrada registrada hace más tiempo.
  void _evictOldestIfNeeded() {
    if (_seen.length <= maxEntries) return;
    String? oldestKey;
    var oldestTs = DateTime.now();
    var initialized = false;
    _seen.forEach((key, ts) {
      if (!initialized || ts.isBefore(oldestTs)) {
        oldestKey = key;
        oldestTs = ts;
        initialized = true;
      }
    });
    if (oldestKey != null) _seen.remove(oldestKey);
  }

  /// Solo para tests / restablecimiento completo del servicio.
  void clear() => _seen.clear();

  int get length => _seen.length;
}

class MeshPolicy {
  MeshPolicy._();

  /// Fail-closed del emisor: solo se envía si hay llave Y el cifrado funcionó.
  static MeshSendDecision decideSend({
    required bool hasSessionKey,
    required bool encryptOk,
  }) {
    if (hasSessionKey && encryptOk) return MeshSendDecision.encryptAndSend;
    return MeshSendDecision.queueForKey;
  }

  /// Fail-closed del relay/receptor: solo se propaga contenido cifrado.
  static MeshRelayDecision decideRelay({required bool isEncrypted}) =>
      isEncrypted ? MeshRelayDecision.relay : MeshRelayDecision.dropPlaintext;

  /// Construye el paquete `mesh_msg` SOLO con contenido cifrado
  /// (esta API no acepta texto en claro por construcción).
  ///
  /// Z-005: `msgId` es un UUID v4 único (los epochs mS colisionaban y el set
  /// de dedup con `clear()` permitía replay).
  static Map<String, dynamic> ciphertextPacket({
    required String source,
    required String target,
    required String encryptedContent,
    required String nonce,
    required String mac,
  }) =>
      {
        'type': 'mesh_msg',
        'source': source,
        'target': target,
        'msgId': const Uuid().v4(),
        'text': encryptedContent,
        'nonce': nonce,
        'mac': mac,
        'hops': 0,
        'isEncrypted': true,
      };
}