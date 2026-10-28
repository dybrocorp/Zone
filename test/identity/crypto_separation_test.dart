/// FASE 2.1 — Separación de dominios criptográficos (Ed25519 vs X25519).
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Ancla los contratos D1/D2 y I-002 (§4.1-§4.3, CRYPTO_DECISIONS):
/// Ed25519 = identidad de firma; X25519 = device encryption (ECDH). NUNCA se
/// intercambian los roles, nunca se reutiliza material entre dominios y el
/// almacén separa el material por ámbito/propósito (namespace `zid1.*`).
library;

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/ed25519_identity_service.dart';
import 'package:zone/identity/identity_errors.dart';
import 'package:zone/identity/keys.dart';
import 'package:zone/identity/secure_key_store.dart';
import 'package:zone/identity/x25519_device_service.dart';

void main() {
  final seedA = List<int>.generate(32, (i) => i);
  final seedB = List<int>.generate(32, (i) => 255 - i);

  group('Ed25519 = firma / X25519 = ECDH (D1/D2, I-002)', () {
    test(
      'dominios distintos: mismo seed ⇒ claves de tipo y bytes distintos',
      () async {
        final ed = await Ed25519IdentityService.keyPairFromSeed(seedA);
        final x = await X25519DeviceEncryptionService.keyPairFromSeed(seedA);
        final edPub = await ed.extractPublicKey();
        final xPub = await x.extractPublicKey();
        expect(edPub.type, KeyPairType.ed25519);
        expect(xPub.type, KeyPairType.x25519);
        expect(edPub.bytes, isNot(equals(xPub.bytes)));
      },
    );

    test(
      'Ed25519 firma y verifica firmas de 64 bytes; firma adulterada ⇒ false',
      () async {
        final ed = await Ed25519IdentityService.keyPairFromSeed(seedA);
        final pubBytes = await Ed25519IdentityService.publicKeyBytes(ed);
        const message = <int>[1, 2, 3, 4, 5];
        final signature = await Ed25519IdentityService.sign(ed, message);
        expect(signature.length, kEd25519SignatureLength);
        expect(
          await Ed25519IdentityService.verify(
            publicKeyBytes: pubBytes,
            message: message,
            signatureBytes: signature,
          ),
          isTrue,
        );
        final tampered = [...signature]..[0] ^= 0xff;
        expect(
          await Ed25519IdentityService.verify(
            publicKeyBytes: pubBytes,
            message: message,
            signatureBytes: tampered,
          ),
          isFalse,
        );
      },
    );

    test('ECDH X25519 es simétrico y produce 32 bytes; X25519 no tiene API de '
        'firma (solo sharedSecret)', () async {
      final xA = await X25519DeviceEncryptionService.keyPairFromSeed(seedA);
      final xB = await X25519DeviceEncryptionService.keyPairFromSeed(seedB);
      final pubA = await xA.extractPublicKey();
      final pubB = await xB.extractPublicKey();
      final sAB = await X25519DeviceEncryptionService.sharedSecret(
        localKeyPair: xA,
        remotePublicKey: pubB,
      );
      final sBA = await X25519DeviceEncryptionService.sharedSecret(
        localKeyPair: xB,
        remotePublicKey: pubA,
      );
      expect(await sAB.extractBytes(), await sBA.extractBytes());
      expect((await sAB.extractBytes()).length, 32);
    });

    test('X25519 nunca firma: ECDH con clave pública Ed25519 ⇒ '
        'KeyPurposeMismatchError (rechazo, no coerción)', () async {
      final xA = await X25519DeviceEncryptionService.keyPairFromSeed(seedA);
      final ed = await Ed25519IdentityService.keyPairFromSeed(seedB);
      final edPub = await ed.extractPublicKey();
      expect(edPub.type, KeyPairType.ed25519);
      expect(
        () => X25519DeviceEncryptionService.sharedSecret(
          localKeyPair: xA,
          remotePublicKey: edPub,
        ),
        throwsA(isA<KeyPurposeMismatchError>()),
      );
    });

    test(
      'claves X25519 de longitud inválida se rechazan (fail-closed)',
      () async {
        final xA = await X25519DeviceEncryptionService.keyPairFromSeed(seedA);
        expect(
          () => X25519DeviceEncryptionService.publicKeyFromBytes(
            List.filled(31, 0),
          ),
          throwsA(isA<InvalidIdentityMetadataError>()),
        );
        final shortPub = SimplePublicKey(
          List.filled(31, 0),
          type: KeyPairType.x25519,
        );
        expect(
          () => X25519DeviceEncryptionService.sharedSecret(
            localKeyPair: xA,
            remotePublicKey: shortPub,
          ),
          throwsA(isA<KeyPurposeMismatchError>()),
        );
      },
    );

    test('seeds distintas producen claves fehacientemente distintas', () async {
      final edA = await Ed25519IdentityService.keyPairFromSeed(seedA);
      final edB = await Ed25519IdentityService.keyPairFromSeed(seedB);
      expect(
        await Ed25519IdentityService.publicKeyBytes(edA),
        isNot(equals(await Ed25519IdentityService.publicKeyBytes(edB))),
      );
      final xA = await X25519DeviceEncryptionService.keyPairFromSeed(seedA);
      final xB = await X25519DeviceEncryptionService.keyPairFromSeed(seedB);
      expect(
        await X25519DeviceEncryptionService.publicKeyBytes(xA),
        isNot(equals(await X25519DeviceEncryptionService.publicKeyBytes(xB))),
      );
    });

    test('namespace `zid1.*` separa el material por ámbito y propósito', () {
      final account = SecretKeyRef(
        scope: 'account',
        purpose: KeyPurpose.accountIdentitySigning,
      );
      final deviceSign = SecretKeyRef(
        scope: 'device',
        purpose: KeyPurpose.deviceIdentitySigning,
        deviceId: 'd1',
      );
      final deviceEnc = SecretKeyRef(
        scope: 'device',
        purpose: KeyPurpose.deviceEncryption,
        deviceId: 'd1',
      );
      final keys = {
        account.storageKey,
        deviceSign.storageKey,
        deviceEnc.storageKey,
      };
      expect(keys.length, 3, reason: 'refs distintos ⇒ storageKeys distintos');
      for (final key in keys) {
        expect(key, startsWith('$kSecureKeyNamespacePrefix.'));
      }
      expect(account.storageKey, 'zid1.account.accountIdentitySigning');
      expect(deviceSign.storageKey, 'zid1.device.deviceIdentitySigning.d1');
      expect(deviceEnc.storageKey, 'zid1.device.deviceEncryption.d1');
    });
  });
}
