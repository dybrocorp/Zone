import 'package:cryptography/cryptography.dart';

void main() async {
  final _x25519 = X25519();
  
  final originalKeyPair = await _x25519.newKeyPair();
  final originalPubKey = await originalKeyPair.extractPublicKey();
  
  final seedBytes = await originalKeyPair.extractPrivateKeyBytes();
  
  // Reconstruct
  final restoredKeyPair = await _x25519.newKeyPairFromSeed(seedBytes);
  final restoredPubKey = await restoredKeyPair.extractPublicKey();
  
  print("Original Pub: ${originalPubKey.bytes}");
  print("Restored Pub: ${restoredPubKey.bytes}");
  
  if (originalPubKey.bytes.toString() != restoredPubKey.bytes.toString()) {
    print("FATAL ERROR: X25519 newKeyPairFromSeed DOES NOT RECONSTRUCT THE SAME PUBLIC KEY!");
  } else {
    print("X25519 Public Keys match perfectly.");
  }
}
