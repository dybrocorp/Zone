import 'package:cryptography/cryptography.dart';
import 'dart:convert';

void main() async {
  final x25519 = X25519();
  final algorithm = Chacha20.poly1305Aead();

  try {
    // 1. Setup Alice
    final aliceKeyPair = await x25519.newKeyPair();
    final alicePubKey = await aliceKeyPair.extractPublicKey();

    // 2. Setup Bob
    final bobKeyPair = await x25519.newKeyPair();
    final bobPubKey = await bobKeyPair.extractPublicKey();

    // 3. Compute Shared Secrets
    final aliceSharedSecret = await x25519.sharedSecretKey(keyPair: aliceKeyPair, remotePublicKey: bobPubKey);
    final bobSharedSecret = await x25519.sharedSecretKey(keyPair: bobKeyPair, remotePublicKey: alicePubKey);

    // 4. Alice Encrypts
    final clearTextBytes = utf8.encode("Hello Bob, this is a secret message!");
    final secretBox = await algorithm.encrypt(
      clearTextBytes,
      secretKey: aliceSharedSecret,
    );

    final cipherTextBase64 = base64Encode(secretBox.cipherText);
    final nonceBase64 = base64Encode(secretBox.nonce);
    final macBase64 = base64Encode(secretBox.mac.bytes);

    // 5. Bob Decrypts
    final bobSecretBox = SecretBox(
      base64Decode(cipherTextBase64),
      nonce: base64Decode(nonceBase64),
      mac: Mac(base64Decode(macBase64)),
    );

    final decryptedBytes = await algorithm.decrypt(
      bobSecretBox,
      secretKey: bobSharedSecret,
    );

    utf8.decode(decryptedBytes);

  } catch (e) {
    // Error handling
  }
}
