import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/e2ee_message_crypto.dart';
import 'logger_service.dart';

/// Servicio que gestiona E2EE capa mensaje.
///
/// v1 (Z-101): secreto compartido X25519 estático-estático como clave ChaCha20
/// directa, columnas `encrypted_content`/`nonce`/`mac`.
/// v2 (PHASE G §6.6 paso 2): sobre el MISMO shared secret, clave derivada por
/// HKDF por dirección + AAD canónico + envelope auto-descriptivo `zt2:`.
/// La implementación v2 vive en `lib/crypto/e2ee_message_crypto.dart`.
class ChatE2EEService {
  static final ChatE2EEService _instance = ChatE2EEService._internal();
  factory ChatE2EEService() => _instance;
  ChatE2EEService._internal();

  final _logger = LoggerService();

  final _x25519 = X25519();
  final _algorithm = Chacha20.poly1305Aead();
  
  SimpleKeyPair? _myKeyPair;
  bool get isInitialized => _myKeyPair != null;
  SimpleKeyPair? get myKeyPair => _myKeyPair;

  /// Genera las claves públicas y privadas locales para este cliente.
  /// La política dicta que el secreto privado nunca abandona el dispositivo.
  Future<SimpleKeyPair> generateKeyPair() async {
    _myKeyPair = await _x25519.newKeyPair();
    return _myKeyPair!;
  }

  /// Recupera o genera un par de claves.
  Future<SimpleKeyPair> getOrCreateKeyPair() async {
    if (_myKeyPair != null) return _myKeyPair!;
    return await generateKeyPair();
  }

  /// Inicializa el par de claves desde un secreto privado guardado (base64).
  Future<void> initFromPrivateBase64(String privateKeyBase64) async {
    final privateKeyBytes = base64Decode(privateKeyBase64);
    _myKeyPair = await _x25519.newKeyPairFromSeed(privateKeyBytes);
  }

  /// Deriva el secreto compartido usando tu clave privada y la clave pública extraída de Supabase del otro usuario.
  Future<SecretKey> computeSharedSecret(SimplePublicKey otherPublicKey) async {
    if (_myKeyPair == null) throw Exception("Keypair no inicializada. Generala primero.");
    return await _x25519.sharedSecretKey(
      keyPair: _myKeyPair!,
      remotePublicKey: otherPublicKey,
    );
  }

  /// Helper para convertir un string base64 de Supabase en un objeto SimplePublicKey.
  SimplePublicKey? importPublicKeyFromBase64(String base64Str) {
    try {
      return SimplePublicKey(
        base64Decode(base64Str.trim()),
        type: KeyPairType.x25519,
      );
    } catch (e) {
      return null;
    }
  }

  /// Encripta un mensaje usando el secreto compartido X25519 estático-estático.
  ///
  /// Z-101 / Fase G: este esquema NO tiene forward secrecy (sin HKDF de AKE,
  /// sin AAD, sin claves efímeras). La FS sólo llegará con las versiones
  /// v3/v4 de `docs/audit/PHASE_G_E2EE_KEY_ESTABLISHMENT.md`; hasta entonces
  /// prohibido afirmarla en documentación o marketing. El comentario anterior
  /// ("garantizando Forward Secrecy") era falso y se corrigió (Fase G §6.6
  /// paso 1, sin cambio de comportamiento).
  Future<Map<String, dynamic>> encryptMessage(String text, SecretKey sharedSecret) async {
    final clearTextBytes = utf8.encode(text);
    final secretBox = await _algorithm.encrypt(
      clearTextBytes,
      secretKey: sharedSecret,
    );
    
    final eContent = base64Encode(secretBox.cipherText);
    final nContent = base64Encode(secretBox.nonce);
    final mContent = base64Encode(secretBox.mac.bytes);
    
    // VALIDACÍON LOCAL PARA CONFIRMAR QUE EL MAC NO ES TRUNCADO
    _logger.debug('[DEBUG-CRYPTO] Encrypted Len: ${eContent.length}, Nonce: ${nContent.length}, Mac: ${mContent.length}');

    return {
      'encrypted_content': eContent,
      'nonce': nContent,
      'mac': mContent,
    };
  }

  /// Desencripta un cipherText proveniente de Supabase usando el secreto local
  Future<String> decryptMessage(
    String cipherTextBase64, 
    String nonceBase64, 
    String macBase64, 
    SecretKey sharedSecret
  ) async {
    try {
      if (cipherTextBase64.isEmpty || nonceBase64.isEmpty || macBase64.isEmpty) {
        return '[🔒 Mensaje vacío o corrupto]';
      }

      final secretBox = SecretBox(
        base64Decode(cipherTextBase64.trim()),
        nonce: base64Decode(nonceBase64.trim()),
        mac: Mac(base64Decode(macBase64.trim())),
      );

      final clearTextBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: sharedSecret,
      );

      return utf8.decode(clearTextBytes);
    } on SecretBoxAuthenticationError {
      // El MAC no coincide: la clave pública del otro usuario cambió (reinstalación / nuevo dispositivo)
      // o el mensaje fue cifrado con llaves antiguas. No es un error de la app.
      _logger.debug('[E2EE] MAC no válido: el mensaje fue cifrado con unas llaves distintas a las actuales.');
      return '🔒 Mensaje cifrado con llaves anteriores';
    } catch (e) {
      _logger.debug('[E2EE] Error descifrando: $e');
      return '[🔒 No se pudo descifrar]';
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  v2 — PHASE G §6.6 paso 2 (envelope zt2:, HKDF por dirección + AAD)
  // ─────────────────────────────────────────────────────────────────────

  /// `true` si el contenido es un envelope v2 (`zt2:`).
  static bool isV2Envelope(String? encryptedContent) =>
      E2eeMessageCryptoV2.isV2Envelope(encryptedContent);

  /// Clave pública local en bytes crudos (32) si hay par inicializado; null
  /// si no (`initFromPrivateBase64` / `generateKeyPair` aún no ejecutados).
  Future<List<int>?> ownPublicKeyBytes() async {
    final pair = _myKeyPair;
    if (pair == null) return null;
    try {
      final pub = await pair.extractPublicKey();
      return Uint8List.fromList(pub.bytes);
    } catch (_) {
      return null;
    }
  }

  /// Cifra con v2 y devuelve el mapa de columnas del esquema actual
  /// (`encrypted_content` lleva el envelope `zt2:`; `nonce`/`mac` vacíos).
  ///
  /// REQUISITO: `senderId` != `receiverId`; ambos canónicos en ambos lados.
  /// Sin forward secrecy (raíz estático-estático en esta fase) — ver PHASE G.
  Future<Map<String, dynamic>> encryptMessageV2({
    required String text,
    required SecretKey sharedSecret,
    required String senderId,
    required String receiverId,
    required String messageId,
    required String matchId,
    required List<int> senderPublicKeyBytes,
    required List<int> receiverPublicKeyBytes,
    List<int>? nonceOverride,
  }) {
    return E2eeMessageCryptoV2.encrypt(
      text: text,
      sharedSecret: sharedSecret,
      context: E2eeV2MessageContext(
        senderId: senderId,
        receiverId: receiverId,
        messageId: messageId,
        matchId: matchId,
        senderPublicKeyBytes: senderPublicKeyBytes,
        receiverPublicKeyBytes: receiverPublicKeyBytes,
      ),
      nonceOverride: nonceOverride,
    );
  }

  /// Descifra un envelope v2 con candidatos de identidad del receptor
  /// (uid y/o handle ZONE-). Traduce los errores tipados a las mismas
  /// cadenas de usuario que v1 (fail-closed, sin fuga de stack).
  Future<String> decryptMessageV2({
    required String encryptedContent,
    required SecretKey sharedSecret,
    required String senderId,
    required List<String> receiverCandidates,
    required String expectedMessageId,
    required String expectedMatchId,
    required List<int> senderPublicKeyBytes,
    required List<int> receiverPublicKeyBytes,
  }) async {
    try {
      return await E2eeMessageCryptoV2.decrypt(
        encryptedContent: encryptedContent,
        sharedSecret: sharedSecret,
        senderId: senderId,
        receiverCandidates: receiverCandidates,
        expectedMessageId: expectedMessageId,
        expectedMatchId: expectedMatchId,
        senderPublicKeyBytes: senderPublicKeyBytes,
        receiverPublicKeyBytes: receiverPublicKeyBytes,
      );
    } on E2eeV2ParseError catch (e) {
      _logger.debug('[E2EE-v2] Envelope inválido: $e');
      return '[🔒 No se pudo descifrar]';
    } on E2eeV2AuthenticationError {
      _logger.debug(
        '[E2EE-v2] Autenticación AEAD fallida (clave/contexto distinto '
        'o mensaje alterado).',
      );
      return '🔒 Mensaje cifrado con llaves anteriores';
    }
  }

  /// Ruta de descifrado para una FILA del chat: decide v1/v2 por el prefijo
  /// `zt2:` del contenido (clasificación explícita, sin downgrade silencioso).
  ///
  /// v1: usa las columnas `nonce`/`mac` de la fila.
  /// v2: `senderId` = `row.sender_id` (fila RECIBIDA, `sender_id` ≠ identidad
  ///     local); candidatos = identidades locales propias (uid y handle
  ///     ZONE-). Para filas propias (yo como sender), la orientación debe
  ///     invertirse a nivel de llamada — ver `_decryptRowForDisplay` en
  ///     `chat_screen.dart`, que invoca `decryptMessageV2` con la orientación
  ///     explícita por fila.
  Future<String> decryptRowMessage({
    required Map<String, dynamic> row,
    required SecretKey sharedSecret,
    required List<int> senderPublicKeyBytes,
    required List<int> receiverPublicKeyBytes,
    required String? localUid,
    required String? localZoneId,
    required String expectedMatchId,
  }) async {
    final content = row['encrypted_content']?.toString() ?? '';
    if (isV2Envelope(content)) {
      final messageId = row['id']?.toString() ?? '';
      final senderId = row['sender_id']?.toString() ?? '';
      final candidates = <String>[
        if (localUid != null && localUid.isNotEmpty) localUid,
        if (localZoneId != null && localZoneId.isNotEmpty) localZoneId,
      ];
      return decryptMessageV2(
        encryptedContent: content,
        sharedSecret: sharedSecret,
        senderId: senderId,
        receiverCandidates: candidates,
        expectedMessageId: messageId,
        expectedMatchId: expectedMatchId,
        senderPublicKeyBytes: senderPublicKeyBytes,
        receiverPublicKeyBytes: receiverPublicKeyBytes,
      );
    }
    // Ruta v1 legacy (comportamiento original preservado).
    return decryptMessage(
      content,
      row['nonce']?.toString() ?? '',
      row['mac']?.toString() ?? '',
      sharedSecret,
    );
  }
}
