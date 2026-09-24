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

    test('Z-005: msgId es UUID v4 único (2 packets → IDs distintos)', () {
      final a = MeshPolicy.ciphertextPacket(
        source: 'S', target: 'T', encryptedContent: 'a', nonce: 'n', mac: 'm');
      final b = MeshPolicy.ciphertextPacket(
        source: 'S', target: 'T', encryptedContent: 'b', nonce: 'n', mac: 'm');

      final idA = a['msgId'] as String;
      final idB = b['msgId'] as String;

      expect(idA, isNotEmpty);
      expect(idA, isNot(idB));
      // Formato UUID v4 (36 chars, 5 grupos).
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(idA),
        isTrue,
      );
    });
  });

  group('MeshDedup (Z-005: LRU con TTL, sin clear() global)', () {
    test('mismo msgId dentro de la ventana → duplicado', () {
      final dedup = MeshDedup();
      expect(dedup.register('id-1'), isTrue); // primera vez → se registra
      expect(dedup.register('id-1'), isFalse); // segunda vez → duplicado
    });

    test('msgIds distintos en el mismo instante → ambos se registran', () {
      final dedup = MeshDedup();
      expect(dedup.register('a'), isTrue);
      expect(dedup.register('b'), isTrue);
      expect(dedup.length, 2);
    });

    test('TTL: entrada expirada se olvida (ventana deslizante)', () {
      final dedup = MeshDedup(ttl: const Duration(milliseconds: 10));
      expect(dedup.register('old'), isTrue);
      // Simular paso del tiempo: el reloj del test avanza en ms reales.
      return Future<void>.delayed(const Duration(milliseconds: 60), () {
        expect(dedup.register('old'), isTrue);
      });
    });

    test('LRU: al superar maxEntries solo se evicta la más antigua', () {
      final dedup = MeshDedup(maxEntries: 3);
      expect(dedup.register('a'), isTrue);
      expect(dedup.register('b'), isTrue);
      expect(dedup.register('c'), isTrue);
      expect(dedup.length, 3);

      // Dedup vivo dentro de la ventana (sin eviction por repetición).
      expect(dedup.register('c'), isFalse);
      expect(dedup.length, 3);

      // Nueva entrada empuja fuera SOLO a la primera ('a'), nunca toda la tabla.
      expect(dedup.register('d'), isTrue);
      expect(dedup.length, 3);

      // Las otras siguen en la ventana → dedup activo (b, c, d).
      expect(dedup.register('d'), isFalse);
      expect(dedup.register('c'), isFalse);
      expect(dedup.register('b'), isFalse);

      // 'a' ya fue evictada → vuelve a registrarse (replay NO queda bloqueado
      // eternamente por la tabla llena; solo por TTL).
      expect(dedup.register('a'), isTrue);
      expect(dedup.length, 3);
    });

    test('register() con la misma id tras TTL acepta de nuevo (no replay eterno)',
        () {
      final dedup = MeshDedup(ttl: const Duration(milliseconds: 10));
      dedup.register('replay');
      return Future<void>.delayed(const Duration(milliseconds: 60), () {
        expect(dedup.register('replay'), isTrue);
      });
    });
  });
}