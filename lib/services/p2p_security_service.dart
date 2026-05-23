import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'chat_e2ee_service.dart';

/// Servicio para gestionar la identidad criptográfica del dispositivo y derivación de sesión.
class P2PSecurityService {
  static final P2PSecurityService _instance = P2PSecurityService._internal();
  factory P2PSecurityService() => _instance;
  P2PSecurityService._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  final _chatE2EE = ChatE2EEService();
  
  static const _privateKeyKey = 'zone_p2p_private_key';
  
  String? _publicBase64;
  String? get publicBase64 => _publicBase64;

  /// Inicializa o recupera el par de claves del dispositivo.
  Future<void> initialize() async {
    String? storedPrivate = await _storage.read(key: _privateKeyKey);
    
    if (storedPrivate == null) {
      print('[P2PSecurityService] Generando nueva identidad criptográfica...');
      final kp = await _chatE2EE.generateKeyPair();
      final privateBytes = await kp.extractPrivateKeyBytes();
      await _storage.write(key: _privateKeyKey, value: base64Encode(privateBytes));
      storedPrivate = base64Encode(privateBytes);
    } else {
      print('[P2PSecurityService] Recuperando identidad criptográfica existente...');
      await _chatE2EE.initFromPrivateBase64(storedPrivate);
    }

    final kp = await _chatE2EE.generateKeyPair(); // Re-usa si ya está iniciada
    final pubKey = await kp.extractPublicKey();
    _publicBase64 = base64Encode(pubKey.bytes);
    print('[P2PSecurityService] Mi Clave Pública: $_publicBase64');
  }

  /// Deriva una llave de sesión (Shared Secret) a partir de una llave pública remota.
  Future<String?> deriveSessionKey(String remotePublicBase64) async {
    try {
      final remotePub = _chatE2EE.importPublicKeyFromBase64(remotePublicBase64);
      if (remotePub == null) return null;

      final sharedSecret = await _chatE2EE.computeSharedSecret(remotePub);
      final secretBytes = await sharedSecret.extractBytes();
      return base64Encode(secretBytes);
    } catch (e) {
      print('[P2PSecurityService] Error derivando session key: $e');
      return null;
    }
  }
}
