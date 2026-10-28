// Tests del DiscoveryCoordinator (docs/redesign/ZONE_ACCEPTANCE_TESTS.md
// §1 L-08/L-09 y §2 D-06, D-07, D-09 + máquina de estados).
//
// Sin red real: RPC fake con log de llamadas (verifica guards anti-abuso y
// de sesión), PositionSource/PermissionChecker fakes, reloj inyectable.
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zone/services/discovery_coordinator.dart';
import 'package:zone/services/internet_discovery_provider.dart';
import 'package:zone/services/location_engine.dart';

/// RPC fake que registra cada llamada (los tests afirman sobre el log).
class _FakeRpc {
  _FakeRpc({this.session = true, this.responder});

  bool session;
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> presenceParams = <Map<String, dynamic>>[];
  Object? Function(String name, Map<String, dynamic> params)? responder;

  DiscoveryRpc get fn => (name, params) async {
        calls.add(name);
        if (name == 'upsert_discovery_presence') {
          presenceParams.add(params);
        }
        final r = responder;
        if (r != null) return r(name, params);
        switch (name) {
          case 'discover_nearby_users':
            return <dynamic>[
              <String, dynamic>{
                'id': 'u-2',
                'zone_id': 'ZONE-BBBBBBBB',
                'display_name': 'Lejos',
                'avatar_url': null,
                'public_key': 'k2',
                'distance_m': 800,
              },
              <String, dynamic>{
                'id': 'u-1',
                'zone_id': 'ZONE-AAAAAAAA',
                'display_name': 'Cerca',
                'avatar_url': null,
                'public_key': 'k1',
                'distance_m': 120,
              },
            ];
          case 'get_discovery_preferences':
            return <String, dynamic>{
              'discovery_enabled': true,
              'location_sharing_enabled': true,
              'radius_m': 500,
            };
          case 'set_discovery_preference':
          case 'expire_my_presence':
          case 'upsert_discovery_presence':
            return null;
          default:
            throw StateError('RPC inesperada en fake: $name');
        }
      };

  int count(String name) =>
      calls.where((c) => c == name).length;
}

class _FakeSource implements PositionSource {
  _FakeSource({this.throwOnPosition});

  Object? throwOnPosition;

  @override
  Future<bool> isServiceEnabled() async => true;

  @override
  Future<GeoFix> getCurrentPosition({Duration timeout = const Duration(seconds: 15)}) async {
    final thrown = throwOnPosition;
    if (thrown != null) throw thrown;
    return GeoFix(
      lat: 4.6097,
      lng: -74.0817,
      timestamp: DateTime.now(),
      accuracyMeters: 10,
      source: GeoSource.gps,
    );
  }
}

class _FakePermissions implements PermissionChecker {
  @override
  Future<PermissionStatus> status() async => PermissionStatus.granted;

  @override
  Future<PermissionStatus> request() async => PermissionStatus.granted;
}

void main() {
  DiscoveryCoordinator buildCoordinator({
    required _FakeRpc rpc,
    required bool online,
    DateTime Function()? clock,
    Object? engineThrow,
  }) {
    return DiscoveryCoordinator(
      engine: LocationEngine(
        source: _FakeSource(throwOnPosition: engineThrow),
        permissions: _FakePermissions(),
      ),
      provider: InternetDiscoveryProvider(
        rpc: rpc.fn,
        session: () => rpc.session,
      ),
      online: () => online,
      clock: clock ?? DateTime.now,
      // Un tick por hora: los tests conducen [tickOnce] a mano (determinismo).
      tickInterval: const Duration(hours: 1),
    );
  }

  test('D-06: sin sesión → requiresAuth y CERO llamadas RPC', () async {
    final rpc = _FakeRpc(session: false);
    final c = buildCoordinator(rpc: rpc, online: true);
    await c.setVisibility(visible: true);
    expect(c.ui.value.status, GeoStatus.requiresAuth);
    expect(rpc.calls, isEmpty,
        reason: 'el guard de sesión debe frenar ANTES de cualquier RPC');
    c.dispose();
  });

  test('L-08: sin internet real → offline y sin llamadas de presencia/búsqueda',
      () async {
    final rpc = _FakeRpc();
    final c = buildCoordinator(rpc: rpc, online: false);
    await c.setVisibility(visible: true);
    expect(rpc.count('set_discovery_preference'), 1,
        reason: 'la preferencia sí se guarda (canal único seguro)');
    await c.tickOnce();
    expect(c.ui.value.status, GeoStatus.offline);
    expect(rpc.count('upsert_discovery_presence'), 0);
    expect(rpc.count('discover_nearby_users'), 0);
    c.dispose();
  });

  test('flujo feliz: visible → live con peers ordenados por distancia', () async {
    final rpc = _FakeRpc();
    final c = buildCoordinator(rpc: rpc, online: true);
    await c.setVisibility(visible: true);
    await c.tickOnce();
    final state = c.ui.value;
    expect(state.status, GeoStatus.live);
    expect(state.visibilityIntended, isTrue);
    expect(state.peers.length, 2);
    expect(state.peers.first.zoneId, 'ZONE-AAAAAAAA',
        reason: '120 m antes que 800 m');
    expect(state.peers.first.distanceLabel, '120 m');
    expect(rpc.count('upsert_discovery_presence'), 1);
    expect(rpc.count('discover_nearby_users'), 1);
    // El ping lleva la fuente y el radio al servidor.
    expect(rpc.presenceParams.single['p_source'], 'gps');
    expect(rpc.presenceParams.single['p_radius_m'], 500);
    c.dispose();
  });

  test('D-07: cadencia client-side — re-tick pronto NO re-publica presencia',
      () async {
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    final rpc = _FakeRpc();
    final c = buildCoordinator(rpc: rpc, online: true, clock: () => now);
    await c.setVisibility(visible: true);
    await c.tickOnce();
    expect(rpc.count('upsert_discovery_presence'), 1);
    now = now.add(const Duration(seconds: 5));
    await c.tickOnce();
    expect(rpc.count('upsert_discovery_presence'), 1,
        reason: 'el servidor deduplica < 15 s; el cliente ni siquiera insiste');
    now = now.add(const Duration(seconds: 40));
    await c.tickOnce();
    expect(rpc.count('upsert_discovery_presence'), 2,
        reason: 'pasada la cadencia (30 s) sí se re-publica');
    c.dispose();
  });

  test('D-09: ocultarse llama expire_my_presence y limpia peers', () async {
    final rpc = _FakeRpc();
    final c = buildCoordinator(rpc: rpc, online: true);
    await c.setVisibility(visible: true);
    await c.tickOnce();
    expect(c.ui.value.peers, isNotEmpty);
    await c.hideNow();
    expect(rpc.count('expire_my_presence'), 1);
    expect(c.ui.value.status, GeoStatus.hidden);
    expect(c.ui.value.peers, isEmpty);
    expect(c.ui.value.visibilityIntended, isFalse);
    // Tras ocultarse, un tick no publica ni busca nada.
    final before = rpc.calls.length;
    await c.tickOnce();
    expect(rpc.calls.length, before,
        reason: 'sin intención de visibilidad el bucle no habla con el server');
    c.dispose();
  });

  test('error del servidor → serverError (estado tipado, sin crash)', () async {
    final rpc = _FakeRpc(
      responder: (name, params) {
        if (name == 'discover_nearby_users') {
          throw Exception('postgrest down');
        }
        return null;
      },
    );
    final c = buildCoordinator(rpc: rpc, online: true);
    await c.setVisibility(visible: true);
    await c.tickOnce();
    expect(c.ui.value.status, GeoStatus.serverError);
    expect(c.ui.value.lastErrorText, isNotNull);
    c.dispose();
  });

  test('permiso denegado en el motor → permissionBlocked', () async {
    final rpc = _FakeRpc();
    final c = buildCoordinator(
      rpc: rpc,
      online: true,
      engineThrow: const GeoException(GeoErrorCode.permissionDenied),
    );
    await c.setVisibility(visible: true);
    await c.tickOnce();
    expect(c.ui.value.status, GeoStatus.permissionBlocked);
    expect(c.ui.value.message, isNotNull);
    c.dispose();
  });

  test('D-02: setRadius clampea al conjunto elegible y persiste en el server',
      () async {
    final rpc = _FakeRpc();
    final c = buildCoordinator(rpc: rpc, online: true);
    await c.setVisibility(visible: true);
    await c.setRadius(300);
    expect(c.ui.value.radiusMeters, 250,
        reason: '300 → el elegible más cercano es 250');
    final prefCalls = rpc.calls
        .where((call) => call == 'set_discovery_preference')
        .length;
    expect(prefCalls, greaterThanOrEqualTo(2));
    c.dispose();
  });

  test('consent revocado en el servidor → hidden y presencia borrada', () async {
    var prefsEnabled = true;
    final rpc = _FakeRpc(
      responder: (name, params) {
        if (name == 'get_discovery_preferences') {
          return <String, dynamic>{
            'discovery_enabled': prefsEnabled,
            'location_sharing_enabled': true,
            'radius_m': 500,
          };
        }
        if (name == 'discover_nearby_users') {
          return <dynamic>[]; // forma válida (array); peers vacíos
        }
        return null; // mutaciones (upsert/expire/set) → sin cuerpo
      },
    );
    // Reloj controlable: el segundo tick debe superar `searchInterval`
    // (20 s) para que el coordinador re-verifique las preferencias.
    var now = DateTime.utc(2026, 10, 28, 12);
    final c = buildCoordinator(rpc: rpc, online: true, clock: () => now);
    await c.setVisibility(visible: true);
    await c.tickOnce();
    expect(c.ui.value.status, GeoStatus.live);
    // El server revoca (otro dispositivo/cierre de consent).
    prefsEnabled = false;
    now = now.add(const Duration(seconds: 21));
    await c.tickOnce();
    expect(c.ui.value.status, GeoStatus.hidden);
    expect(rpc.count('expire_my_presence'), greaterThanOrEqualTo(1));
    c.dispose();
  });

  test('revocar consent de ubicación borra presencia y limpia estado', () async {
    final rpc = _FakeRpc();
    final c = buildCoordinator(rpc: rpc, online: true);
    await c.setVisibility(visible: true);
    await c.tickOnce();
    await c.setVisibility(visible: false);
    expect(rpc.count('expire_my_presence'), 1);
    expect(c.ui.value.status, GeoStatus.hidden);
    c.dispose();
  });
}
