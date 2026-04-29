import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class ChatE2EEService {
  static final ChatE2EEService _instance = ChatE2EEService._internal();
  factory ChatE2EEService() => _instance;
  ChatE2EEService._internal();

  final _x25519 = X25519();
  final _algorithm = Chacha20.poly1305Aead();
  
  SimpleKeyPair? _myKeyPair;

  /// Genera las claves públicas y privadas locales para este cliente.
  /// La política dicta que el secreto privado nunca abandona el dispositivo.
  Future<SimpleKeyPair> generateKeyPair() async {
    _myKeyPair = await _x25519.newKeyPair();
    return _myKeyPair!;
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
  SimplePublicKey importPublicKeyFromBase64(String base64) {
    return SimplePublicKey(
      base64Decode(base64),
      type: KeyPairType.x25519,
    );
  }

  /// Encripta un mensaje usando el secreto compartido generado, garantizando Forward Secrecy.
  Future<Map<String, dynamic>> encryptMessage(String text, SecretKey sharedSecret) async {
    final clearTextBytes = utf8.encode(text);
    final secretBox = await _algorithm.encrypt(
      clearTextBytes,
      secretKey: sharedSecret,
    );
    
    return {
      'encrypted_content': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  /// Desencripta un cipherText proveniente de Supabase usando el secreto local
  Future<String> decryptMessage(
    String cipherTextBase64, 
    String nonceBase64, 
    String macBase64, 
    SecretKey sharedSecret
  ) async {
    final secretBox = SecretBox(
      base64Decode(cipherTextBase64),
      nonce: base64Decode(nonceBase64),
      mac: Mac(base64Decode(macBase64)),
    );

    final clearTextBytes = await _algorithm.decrypt(
      secretBox,
      secretKey: sharedSecret,
    );

    return utf8.decode(clearTextBytes);
  }
}
