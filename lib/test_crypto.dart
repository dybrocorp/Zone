import 'package:cryptography/cryptography.dart';
import 'dart:convert';

void main() async {
  final _x25519 = X25519();
  final _algorithm = Chacha20.poly1305Aead();

  try {
    // 1. Setup Alice
    final aliceKeyPair = await _x25519.newKeyPair();
    final alicePubKey = await aliceKeyPair.extractPublicKey();

    // 2. Setup Bob
    final bobKeyPair = await _x25519.newKeyPair();
    final bobPubKey = await bobKeyPair.extractPublicKey();

    // 3. Compute Shared Secrets
    final aliceSharedSecret = await _x25519.sharedSecretKey(keyPair: aliceKeyPair, remotePublicKey: bobPubKey);
    final bobSharedSecret = await _x25519.sharedSecretKey(keyPair: bobKeyPair, remotePublicKey: alicePubKey);

    print("Shared secrets computed.");

    // 4. Alice Encrypts
    final clearTextBytes = utf8.encode("Hello Bob, this is a secret message!");
    final secretBox = await _algorithm.encrypt(
      clearTextBytes,
      secretKey: aliceSharedSecret,
    );

    final cipherTextBase64 = base64Encode(secretBox.cipherText);
    final nonceBase64 = base64Encode(secretBox.nonce);
    final macBase64 = base64Encode(secretBox.mac.bytes);
    
    print("Alice encrypted message.");

    // 5. Bob Decrypts
    final bobSecretBox = SecretBox(
      base64Decode(cipherTextBase64),
      nonce: base64Decode(nonceBase64),
      mac: Mac(base64Decode(macBase64)),
    );

    final decryptedBytes = await _algorithm.decrypt(
      bobSecretBox,
      secretKey: bobSharedSecret,
    );

    final decryptedText = utf8.decode(decryptedBytes);
    print("Bob decrypted successfully: $decryptedText");
    
  } catch (e) {
    print("ERROR DURING ROUNDTRIP: $e");
  }
}
