import 'package:flutter_test/flutter_test.dart';
import 'package:zone/services/zone_id_service.dart';

/// Contrato de formato ZONE-ID compartido con el backend endurecido
/// (Z-001 Fase A: claim_zone_id / verify_zone_id validan `^ZONE-[A-Z0-9]{8}$`).
void main() {
  group('ZoneIdService.isValidZoneIdFormat (contrato Z-001)', () {
    test('acepta formato canónico', () {
      expect(ZoneIdService.isValidZoneIdFormat('ZONE-ABCD1234'), isTrue);
      expect(ZoneIdService.isValidZoneIdFormat('ZONE-00000000'), isTrue);
      expect(ZoneIdService.isValidZoneIdFormat('ZONE-ZZZZZZZZ'), isTrue);
    });

    test('rechaza null y vacío', () {
      expect(ZoneIdService.isValidZoneIdFormat(null), isFalse);
      expect(ZoneIdService.isValidZoneIdFormat(''), isFalse);
    });

    test('rechaza longitud incorrecta', () {
      expect(ZoneIdService.isValidZoneIdFormat('ZONE-ABC'), isFalse);
      expect(ZoneIdService.isValidZoneIdFormat('ZONE-ABCD12345'), isFalse);
    });

    test('rechaza minúsculas y caracteres no alfanuméricos', () {
      expect(ZoneIdService.isValidZoneIdFormat('ZONE-abcd1234'), isFalse);
      expect(ZoneIdService.isValidZoneIdFormat('ZONE-ABCD 123'), isFalse);
      expect(ZoneIdService.isValidZoneIdFormat('ZONE-ABCD_123'), isFalse);
    });
  });
}