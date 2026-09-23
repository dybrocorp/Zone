import 'package:flutter_test/flutter_test.dart';
import 'package:zone/services/mesh_policy.dart';

/// Contrato fail-closed del mesh (Z-003 FASE 1.4, decisión CTO 2026-09-23):
///  - Emisor: sin llave o cifrado fallido → NUNCA se envía en claro (cola).
///  - Relay/receptor: `isEncrypted != true` → se descarta.
void main() {
  group('MeshPolicy.decideSend (fail-closed del emisor)', () {
    test('con llave y cifrado OK → encryptAndSend', () {
      expect(
        MeshPolicy.decideSend(hasSessionKey: true, encryptOk: true),
        MeshSendDecision.encryptAndSend,
      );
    });

    test('sin llave → queueForKey (nunca enviar en claro)', () {
      expect(
        MeshPolicy.decideSend(hasSessionKey: false, encryptOk: false),
        MeshSendDecision.queueForKey,
      );
    });

    test('sin llave (invariante: encryptOk=true es imposible) → queueForKey',
        () {
      expect(
        MeshPolicy.decideSend(hasSessionKey: false, encryptOk: true),
        MeshSendDecision.queueForKey,
      );
    });

    test('llave presente pero cifrado falla → queueForKey', () {
      expect(
        MeshPolicy.decideSend(hasSessionKey: true, encryptOk: false),
        MeshSendDecision.queueForKey,
      );
    });
  });

  group('MeshPolicy.decideRelay (relay descarta no-cifrado)', () {
    test('isEncrypted true → relay', () {
      expect(
        MeshPolicy.decideRelay(isEncrypted: true),
        MeshRelayDecision.relay,
      );
    });

    test('isEncrypted false → dropPlaintext', () {
      expect(
        MeshPolicy.decideRelay(isEncrypted: false),
        MeshRelayDecision.dropPlaintext,
      );
    });
  });

  group('MeshPolicy.ciphertextPacket', () {
    test('marca isEncrypted=true y no acepta texto en claro', () {
      final packet = MeshPolicy.ciphertextPacket(
        source: 'ZONE-SOURCE',
        target: 'ZONE-TARGET',
        encryptedContent: 'cifrado',
        nonce: 'nonce',
        mac: 'mac',
      );

      expect(packet['type'], 'mesh_msg');
      expect(packet['isEncrypted'], true);
      expect(packet['text'], 'cifrado');
      expect(packet['nonce'], 'nonce');
      expect(packet['mac'], 'mac');
      expect(packet['source'], 'ZONE-SOURCE');
      expect(packet['target'], 'ZONE-TARGET');
    });
  });
}