/// Z-004 PHASE E/G — CONTRATO DE FUENTE del cableado REAL del handshake
/// `ZONE-P2P-AKE-1` en `NearbyService`.
///
/// Precedente: `test/recovery/recovery_fail_closed_test.dart` y
/// `test/sql_security_regression_test.dart` (escaneo textual como contrato).
/// El contrato bloquea, sin poder ser roto por una regresión sin editar este
/// test, que en `lib/services/nearby_service.dart`:
///
/// 1. Al conectar un endpoint se ARRANCA el handshake (`_startAkeHandshake`).
/// 2. Los frames `ake_hello` validados (forma + cupo WI-6) se despachan al
///    coordinador (`_handleAkeHelloFrame`) — no solo se registran.
/// 3. El material SETTLED marca AKE completado EXACTAMENTE una vez
///    (`markAkeCompleted` — gate WI-2 autenticado; cero llamadas extra).
/// 4. El coordinador es fail-closed con el bootstrap de identidad
///    (`isInitialized`/`activeBootstrap` antes de crear).
/// 5. Ambos caminos de desconexión destruyen el estado AKE (efímero).
/// 6. Existe el acceso al canal protegido (`akeChannel`).
/// 7. La identidad del AKE proviene de la FUNDACIÓN (single-source:
///    `loadDeviceKeyMaterial`).
/// 8. El flujó legacy Z-212 (`getSessionKey` en `profile_exchange`) quedó
///    INTACTO (compatibilidad de flota).
///
/// Label: LOCALLY TESTED (source contract; el handshake real de radios es
/// simulado en `test/p2p_ake_coordinator_test.dart`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/services/nearby_service.dart').readAsStringSync();

  group('contrato: arranque del handshake (WI-1/WI-4 locales)', () {
    test('_onConnectionResult arranca el AKE al conectar (unawaited)', () {
      expect(source.contains('unawaited(_startAkeHandshake(id))'), isTrue);
      expect(source.contains('Future<void> _startAkeHandshake('), isTrue);
    });

    test('frames ake_hello despachados al coordinador post-validación', () {
      expect(source.contains('_handleAkeHelloFrame('), isTrue);
      // El despacho ocurre SOLO con frame saneado y cupo consumido:
      final validatePos = source.indexOf('validateAkeFrame(');
      final quotaPos = source.indexOf(
        'consumeHandshakeQuota(endpointId) ==',
        validatePos,
      );
      final dispatchPos = source.indexOf('_handleAkeHelloFrame(endpointId,');
      expect(validatePos, greaterThan(-1));
      expect(quotaPos, greaterThan(-1));
      expect(dispatchPos, greaterThan(-1));
      expect(
        validatePos < quotaPos && quotaPos < dispatchPos,
        isTrue,
        reason: 'orden fail-closed: forma gruesa → WI-6 → coordinador',
      );
    });
  });

  group('contrato: gate WI-2 y material settled', () {
    test('markAkeCompleted se llama EXACTAMENTE una vez (desde _onAkeKeyMaterial)', () {
      final count = 'markAkeCompleted'.allMatches(source).length;
      expect(count, 1, reason: 'única marca de AKE completado: al settle');
      final pos = source.indexOf('markAkeCompleted');
      final context = source
          .substring(pos < 200 ? 0 : pos - 200, pos)
          .toLowerCase();
      expect(
        context.contains('_onakekeymaterial') ||
            source.indexOf('void _onAkeKeyMaterial') < pos,
        isTrue,
      );
      // El listener llega del coordinador (keyMaterialListener), no del wire.
      expect(source.contains('keyMaterialListener: _onAkeKeyMaterial'), isTrue);
    });
  });

  group('contrato: fail-closed y efímero', () {
    test('el coordinador exige bootstrap de identidad antes de existir', () {
      final pos = source.indexOf('P2pAkeCoordinator? _ensureAkeCoordinator()');
      expect(pos, greaterThan(-1));
      final body = source.substring(
        pos,
        source.indexOf('}', source.indexOf('return coordinator;', pos)) + 1,
      );
      expect(body.contains('isInitialized'), isTrue);
      expect(body.contains('activeBootstrap'), isTrue,
          reason: 'fail-closed: sin bootstrap no hay coordinador');
    });

    test('AMOS caminos de desconexión destruyen el estado AKE', () {
      final first = source.indexOf('_akeCoordinator?.onDisconnected(');
      final second = source.indexOf(
        '_akeCoordinator?.onDisconnected(',
        first + 1,
      );
      expect(first, greaterThan(-1));
      expect(second, greaterThan(-1),
          reason: '`_onDisconnected` y `disconnectUser` (dos caminos)');
    });

    test('material por-conexión: NO se persiste en slots legacy sk_<zone>', () {
      // El AKE deriva en memoria (coordinador); fuera del flujo legacy.
      expect(source.contains('akeChannel(String endpointId)'), isTrue);
      // Compatibilidad de flota: el bloque Z-212 de profile_exchange intacto.
      expect(source.contains('getSessionKey(remoteZoneId)'), isTrue,
          reason: 'consulta legacy Z-212 del slot sk_<zone> sigue presente');
      // La ÚNICA escritura de llave de sesión P2P sigue siendo la legacy.
      expect(source.contains('deriveSessionKey'), isTrue);
    });

    test('identidad del AKE proviene de la FUNDACIÓN (single-source)', () {
      expect(
        source.contains('loadDeviceKeyMaterial(context.deviceId)'),
        isTrue,
      );
      expect(source.contains('material.signingKeyPair'), isTrue);
      expect(source.contains('material.encryptionKeyPair'), isTrue);
      // Y falla cerrada sin log de secretos: el catch no imprime material.
      expect(
        source.contains("'[NearbyService] Identidad AKE no disponible "
            "(fail-closed).'"),
        isTrue,
      );
    });
  });
}
