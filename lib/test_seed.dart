import 'package:cryptography/cryptography.dart';

void main() async {
  final x25519 = X25519();
  
  final originalKeyPair = await x25519.newKeyPair();
  final originalPubKey = await originalKeyPair.extractPublicKey();
  
  final seedBytes = await originalKeyPair.extractPrivateKeyBytes();
  
  // Reconstruct
  final restoredKeyPair = await x25519.newKeyPairFromSeed(seedBytes);
  final restoredPubKey = await restoredKeyPair.extractPublicKey();
  
  // Key comparison
  if (originalPubKey.bytes.toString() != restoredPubKey.bytes.toString()) {
    // Error handling
  }
}
