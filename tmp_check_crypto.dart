import 'package:cryptography/cryptography.dart';
import 'dart:convert';

void main() async {
  final x25519 = X25519();
  final keyPair = await x25519.newKeyPair();
  final keyPairData = await keyPair.extract();
  print('SimpleKeyPairData members:');
  // En Dart no podemos listar miembros tan fácil sin reflect, pero podemos probar campos comunes
  try {
     print('privateKey exists: ${ (keyPairData as dynamic).privateKey != null }');
  } catch (e) {
     print('privateKey failed: $e');
  }
}
