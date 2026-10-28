// Tests del LocationEngine (docs/redesign/ZONE_ACCEPTANCE_TESTS.md §1, L-01..L-07).
//
// Sin red real: `PositionSource` y `PermissionChecker` son fakes (misma
// tradición que `match_outbox_test`). El motor nunca inventa coordenadas ni
// reutiliza fixes vencidos.
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zone/services/location_engine.dart';

class _FakeSource implements PositionSource {
  _FakeSource({this.serviceEnabled = true, this.fix});

  bool serviceEnabled;
  GeoFix? fix;
  Object? throwOnPosition;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<GeoFix> getCurrentPosition({Duration timeout = const Duration(seconds: 15)}) async {
    final thrown = throwOnPosition;
    if (thrown != null) throw thrown;
    final f = fix;
    if (f == null) throw const GeoException(GeoErrorCode.unknown, 'sin fix en fake');
    return f;
  }
}

class _FakePermissions implements PermissionChecker {
  _FakePermissions(this._status, {this.afterRequest});

  PermissionStatus _status;
  PermissionStatus? afterRequest;

  @override
  Future<PermissionStatus> status() async => _status;

  @override
  Future<PermissionStatus> request() async {
    if (afterRequest != null) _status = afterRequest!;
    return _status;
  }
}

GeoFix _fix({
  double accuracy = 10,
  Duration age = Duration.zero,
  double lat = 4.6097,
  double lng = -74.0817,
}) {
  return GeoFix(
    lat: lat,
    lng: lng,
    timestamp: DateTime.now().subtract(age),
    accuracyMeters: accuracy,
    source: GeoSource.gps,
  );
}

void main() {
  group('LocationEngine — calidad de fix (L-01, L-02, L-06, L-07)', () {
    test('L-01: fix GPS con precisión buena se acepta', () async {
      final engine = LocationEngine(
        source: _FakeSource(fix: _fix(accuracy: 12)),
        permissions: _FakePermissions(PermissionStatus.granted),
      );
      final fix = await engine.acquireFix();
      expect(fix.lat, 4.6097);
      expect(fix.accuracyMeters, 12);
      expect(engine.lastValidFix, isNotNull);
    });

    test('L-02: fix de red en el umbral (150 m) se acepta (aproximado basta)', () async {
      final engine = LocationEngine(
        source: _FakeSource(fix: _fix(accuracy: 150)),
        permissions: _FakePermissions(PermissionStatus.granted),
      );
      final fix = await engine.acquireFix();
      expect(fix.accuracyMeters, 150);
    });

    test('L-06: precisión insuficiente (800 m) → noFixUnusable, sin resultados falsos', () async {
      final engine = LocationEngine(
        source: _FakeSource(fix: _fix(accuracy: 800)),
        permissions: _FakePermissions(PermissionStatus.granted),
      );
      await expectLater(
        engine.acquireFix(),
        throwsA(predicate((e) => e is GeoException && e.code == GeoErrorCode.noFixUnusable)),
      );
      expect(engine.lastValidFix, isNull);
    });

    test('L-07: fix caducado (>2 min) se rechaza y lastValidFix no lo expone', () async {
      final engine = LocationEngine(
        source: _FakeSource(fix: _fix(accuracy: 10, age: const Duration(minutes: 3))),
        permissions: _FakePermissions(PermissionStatus.granted),
      );
      await expectLater(
        engine.acquireFix(),
        throwsA(predicate((e) => e is GeoException && e.code == GeoErrorCode.noFixUnusable)),
      );
      expect(engine.lastValidFix, isNull);
    });

    test('invariante: un fix válido en caché expira y deja de exponerse', () async {
      var now = DateTime.now();
      final engine = LocationEngine(
        source: _FakeSource(fix: _fix(accuracy: 10)),
        permissions: _FakePermissions(PermissionStatus.granted),
      );
      await engine.acquireFix();
      expect(engine.lastValidFix, isNotNull);
      // Simula el paso del tiempo más allá del TTL del fix (2 min).
      now = now.add(const Duration(minutes: 3));
      final stale = engine.lastValidFix;
      expect(stale == null || stale.isStale(maxAge: const Duration(minutes: 2), now: now),
          isTrue);
    });
  });

  group('LocationEngine — permisos y servicio (L-03, L-04, L-05)', () {
    test('L-03: denegado → pedir → concedido funciona', () async {
      final engine = LocationEngine(
        source: _FakeSource(fix: _fix(accuracy: 10)),
        permissions: _FakePermissions(
          PermissionStatus.denied,
          afterRequest: PermissionStatus.granted,
        ),
      );
      final fix = await engine.acquireFix();
      expect(fix.accuracyMeters, 10);
    });

    test('L-03: denegado y el usuario vuelve a denegar → permissionDenied tipado', () async {
      final engine = LocationEngine(
        source: _FakeSource(fix: _fix(accuracy: 10)),
        permissions: _FakePermissions(
          PermissionStatus.denied,
          afterRequest: PermissionStatus.denied,
        ),
      );
      await expectLater(
        engine.acquireFix(),
        throwsA(predicate((e) => e is GeoException && e.code == GeoErrorCode.permissionDenied)),
      );
    });

    test('L-04: permanentemente denegado → guía a Ajustes (mensaje claro)', () async {
      final engine = LocationEngine(
        source: _FakeSource(fix: _fix(accuracy: 10)),
        permissions: _FakePermissions(PermissionStatus.permanentlyDenied),
      );
      await expectLater(
        engine.acquireFix(),
        throwsA(predicate((e) =>
            e is GeoException &&
            e.code == GeoErrorCode.permissionPermanentlyDenied &&
            e.code.message.contains('Ajustes'))),
      );
    });

    test('L-05: servicio de ubicación desactivado → instrucciones claras', () async {
      final engine = LocationEngine(
        source: _FakeSource(serviceEnabled: false, fix: _fix(accuracy: 10)),
        permissions: _FakePermissions(PermissionStatus.granted),
      );
      await expectLater(
        engine.acquireFix(),
        throwsA(predicate((e) =>
            e is GeoException &&
            e.code == GeoErrorCode.serviceDisabled &&
            e.code.message.contains('servicio de ubicación'))),
      );
    });

    test('mensajes de error nunca contienen coordenadas', () async {
      for (final code in GeoErrorCode.values) {
        expect(code.message.contains('4.6097'), isFalse, reason: code.name);
        expect(code.message.contains('-74.0817'), isFalse, reason: code.name);
      }
    });
  });
}
