/// Z-003 (FASE 1.4) · Política fail-closed del mesh — decisión CTO 2026-09-23.
///
/// La malla NUNCA transporta texto en claro para mensajes `mesh_msg`:
///  - **Emisor:** si no hay llave de sesión o el cifrado falla, el mensaje se
///    ENCOLA (nunca se envía en claro) y se reintenta al derivarse la llave.
///  - **Relay/receptor:** los paquetes con `isEncrypted != true` se descartan.
///
/// No introduce criptografía nueva: reutiliza la derivación X25519/ECDH y el
/// cifrado AEAD existentes (`p2p_security_service` / `chat_e2ee_service`).
library;

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
        'msgId': DateTime.now().millisecondsSinceEpoch.toString(),
        'text': encryptedContent,
        'nonce': nonce,
        'mac': mac,
        'hops': 0,
        'isEncrypted': true,
      };
}