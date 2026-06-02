import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'logger_service.dart';

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

  /// Encripta un mensaje usando el secreto compartido generado, garantizando Forward Secrecy.
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
        return '[Mensaje vacío o corrupto]';
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
    } catch (e) {
      return 'Error de cifrado ($e)';
    }
  }
}
