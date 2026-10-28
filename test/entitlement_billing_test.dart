// Tests de Premium: EntitlementService + PlayBillingService + gate BT.
// (docs/redesign/ZONE_ACCEPTANCE_TESTS.md §3, P-01..P-12)
//
// Sin red real y sin platform channels: RPC/gateway/verificador son fakes.
// Regla de oro verificada aquí: NINGÚN éxito del cliente concede Premium;
// solo el backend verificado (z215) lo hace. Fail-closed en todos los fallos.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zone/services/entitlement_service.dart';
import 'package:zone/services/play_billing_service.dart';
import 'package:zone/services/premium_service.dart';

/// RPC fake de `get_my_entitlements` controlable por test.
class _FakeEntitlementRpc {
  _FakeEntitlementRpc();

  /// Filas que devolverá la próxima llamada (forma z215: jsonb con lista).
  List<Map<String, dynamic>> rows = [];

  /// Si no es null, la próxima llamada lanza esto (red caída, RPC ausente…).
  Object? throwNext;

  int calls = 0;

  EntitlementRpc get fn => (_) async {
        calls++;
        final t = throwNext;
        if (t != null) throw t;
        return <String, dynamic>{'entitlements': rows};
      };
}

DateTime _inHours(double h, {required DateTime from}) =>
    from.add(Duration(milliseconds: (h * 3600 * 1000).round()));

Map<String, dynamic> _entRow({
  String product = 'zone_premium_monthly',
  bool verified = true,
  String renewalState = 'active',
  DateTime? expiresAt,
  DateTime? lastVerifiedAt,
}) {
  return <String, dynamic>{
    'product': product,
    'platform': 'android',
    'verified': verified,
    'starts_at': expiresAt?.subtract(const Duration(days: 30)).toIso8601String(),
    'expires_at': expiresAt?.toIso8601String(),
    'renewal_state': renewalState,
    'last_verified_at': lastVerifiedAt?.toIso8601String(),
  };
}

void main() {
  final base = DateTime.utc(2026, 10, 28, 12, 0, 0);

  EntitlementService svcWith(
    _FakeEntitlementRpc rpc, {
    DateTime Function()? clock,
    LegacyPremiumReader? legacyReader,
  }) {
    return EntitlementService(
      rpc: rpc.fn,
      legacyReader: legacyReader ?? (() async => false),
      clock: clock ?? (() => base),
      session: () => true, // sesión autenticada simulada (determinismo)
      cacheTtl: Duration.zero, // sin caché: determinismo total por test
    );
  }

  group('EntitlementService — matriz de estados (P-01..P-09)', () {
    test('P-01: sin entitlements → free, radar BT bloqueado', () async {
      final rpc = _FakeEntitlementRpc()..rows = [];
      final svc = svcWith(rpc);
      final snap = await svc.load();
      expect(snap.state, PremiumState.free);
      expect(snap.allowsBluetooth, isFalse);
    });

    test('P-02: verificado y vigente → active, radar BT permitido', () async {
      final rpc = _FakeEntitlementRpc()
        ..rows = [_entRow(expiresAt: _inHours(48, from: base))];
      final svc = svcWith(rpc);
      final snap = await svc.load();
      expect(snap.state, PremiumState.active);
      expect(snap.allowsBluetooth, isTrue);
      expect(snap.verifiedSource, 'z215');
    });

    test('P-04: expirada (expires_at pasada) → expired, bloqueado', () async {
      final rpc = _FakeEntitlementRpc()
        ..rows = [_entRow(expiresAt: base.subtract(const Duration(hours: 2)))];
      final svc = svcWith(rpc);
      final snap = await svc.load();
      expect(snap.state, PremiumState.expired);
      expect(snap.allowsBluetooth, isFalse);
    });

    test('P-05: renovación cancelada pero vigente → canceledRenewal, permitido',
        () async {
      final rpc = _FakeEntitlementRpc()
        ..rows = [
          _entRow(
              renewalState: 'canceled',
              expiresAt: _inHours(72, from: base)),
        ];
      final svc = svcWith(rpc);
      final snap = await svc.load();
      expect(snap.state, PremiumState.canceledRenewal);
      expect(snap.allowsBluetooth, isTrue);
    });

    test('P-06: refund/revocado → refundedRevoked, bloqueado', () async {
      final rpc = _FakeEntitlementRpc()
        ..rows = [
          _entRow(
              renewalState: 'refunded',
              expiresAt: _inHours(48, from: base)),
        ];
      final svc = svcWith(rpc);
      final snap = await svc.load();
      expect(snap.state, PremiumState.refundedRevoked);
      expect(snap.allowsBluetooth, isFalse);
    });

    test('P-07: fallo de RPC sin historial verificado → unknown, bloqueado',
        () async {
      final rpc = _FakeEntitlementRpc()..throwNext = Exception('red caída');
      final svc = svcWith(rpc);
      final snap = await svc.load();
      expect(snap.state, PremiumState.unknown);
      expect(snap.allowsBluetooth, isFalse);
    });

    test('P-08: grace — entitlement previo vigente + fallo de red → permitido ≤24h',
        () async {
      var now = base;
      final rpc = _FakeEntitlementRpc()
        ..rows = [_entRow(expiresAt: _inHours(48, from: base))];
      final svc = EntitlementService(
        rpc: rpc.fn,
        legacyReader: (() async => false),
        clock: () => now,
        session: () => true,
        cacheTtl: Duration.zero,
      );
      final first = await svc.load();
      expect(first.state, PremiumState.active);

      // Red cae (fallo genérico, NO missing-RPC).
      rpc.throwNext = Exception('socket timeout');
      final second = await svc.loadForce();
      expect(second.state, PremiumState.grace);
      expect(second.allowsBluetooth, isTrue,
          reason: 'grace ≤ 24 h con entitlement verificado previo vigente');
      now = now.add(const Duration(minutes: 5));
    });

    test('P-09: grace NO aplica si faltan <24 h para expirar → fail-closed',
        () async {
      var now = base;
      final rpc = _FakeEntitlementRpc()
        ..rows = [_entRow(expiresAt: _inHours(10, from: base))];
      final svc = EntitlementService(
        rpc: rpc.fn,
        legacyReader: (() async => false),
        clock: () => now,
        session: () => true,
        cacheTtl: Duration.zero,
      );
      final first = await svc.load();
      expect(first.state, PremiumState.active);

      rpc.throwNext = Exception('socket timeout');
      final second = await svc.loadForce();
      expect(second.state, PremiumState.expired,
          reason: 'menos de 24 h a expirar → sin grace (diseño §4.3)');
      expect(second.allowsBluetooth, isFalse);
      now = now.add(const Duration(minutes: 5));
    });

    test('P-09b: grace NO aplica si nunca hubo verificación previa', () async {
      final rpc = _FakeEntitlementRpc();
      final svc = svcWith(rpc);
      final snap = await svc.load(); // free (sin previo)
      expect(snap.state, PremiumState.free);
      rpc.throwNext = Exception('red caída');
      final after = await svc.loadForce();
      expect(after.state, PremiumState.unknown);
      expect(after.allowsBluetooth, isFalse);
    });

    test('transición documentada: RPC ausente (z215 sin aplicar) → flag legacy',
        () async {
      final rpc = _FakeEntitlementRpc()
        ..throwNext = Exception(
            'Could not find the function public.get_my_entitlements()? Hint: '
            'a la función no le concedieron permisos o no existe');
      final svc = EntitlementService(
        rpc: rpc.fn,
        legacyReader: (() async => true), // users.is_premium = true
        clock: () => base,
        session: () => true,
        cacheTtl: Duration.zero,
      );
      final snap = await svc.load();
      expect(snap.state, PremiumState.active);
      expect(snap.verifiedSource, 'transitional_legacy_is_premium');
      expect(snap.allowsBluetooth, isTrue);
    });

    test('sin sesión → free sin llamar RPC', () async {
      final rpc = _FakeEntitlementRpc();
      final svc = EntitlementService(
        rpc: rpc.fn,
        legacyReader: (() async => false),
        clock: () => base,
        session: () => false, // sin sesión autenticada
        cacheTtl: Duration.zero,
      );
      final snap = await svc.load();
      expect(snap.state, PremiumState.free);
      expect(rpc.calls, 0,
          reason: 'sin sesión no se consulta el backend (guard de sesión)');
    });

    test('caché TTL: dentro de la ventana no revalida; loadForce siempre sí',
        () async {
      final rpc = _FakeEntitlementRpc()
        ..rows = [_entRow(expiresAt: _inHours(48, from: base))];
      final svc = EntitlementService(
        rpc: rpc.fn,
        legacyReader: (() async => false),
        clock: () => base,
        session: () => true,
        cacheTtl: const Duration(minutes: 5),
      );
      await svc.load();
      await svc.load(); // segunda dentro del TTL
      expect(rpc.calls, 1);
      await svc.loadForce();
      expect(rpc.calls, 2,
          reason: 'el gate BT revalida SIEMPRE (operación sensible)');
    });
  });

  group('PlayBillingService — flujo de compra (P-03, P-10)', () {
    test('P-03: purchased sin verificación backend → verificationPending y '
        'BT bloqueado; la compra NO se completa', () async {
      final entRpc = _FakeEntitlementRpc()..rows = []; // backend: free
      final ent = svcWith(entRpc);
      final gateway = _FakeGateway();
      final verifications = <Map<String, String>>[];
      final billing = PlayBillingService(
        gateway: gateway,
        verifier: ({required productId, required purchaseToken}) async {
          verifications
              .add({'productId': productId, 'purchaseToken': purchaseToken});
          return false; // edge function aún no desplegada → no verifica
        },
        entitlement: ent,
      );

      final product = ProductDetails(
        id: ZoneBillingProducts.monthly,
        title: 'Zone Premium Mensual',
        description: 'Suscripción mensual',
        price: 'COP 15.000',
        rawPrice: 15000,
        currencyCode: 'COP',
        currencySymbol: r'$',
      );

      await billing.buyProduct(product);
      expect(billing.uiState.value.state, BillingState.purchaseInProgress);

      // Play reporta la compra exitosa…
      await billing.handlePurchaseUpdates([
        PurchaseDetails(
          purchaseID: 'order-1',
          productID: ZoneBillingProducts.monthly,
          verificationData: PurchaseVerificationData(
            localVerificationData: '{"orderId":"order-1"}',
            serverVerificationData: 'token-abc',
            source: 'google_play',
          ),
          transactionDate: '1698500000000',
          status: PurchaseStatus.purchased,
        ),
      ]);

      expect(billing.uiState.value.state, BillingState.verificationPending,
          reason: 'sin confirmación backend el estado es honesto: pendiente');
      expect(verifications.single['purchaseToken'], 'token-abc');
      expect(gateway.completed, isEmpty,
          reason: 'NO se hace ack de compras no verificadas (fail-closed)');
      expect((await ent.load()).allowsBluetooth, isFalse);
    });

    test('P-10: restored + verificación OK → completePurchase + entitlement '
        'revalidado', () async {
      final entRpc = _FakeEntitlementRpc()
        ..rows = [_entRow(expiresAt: _inHours(48, from: base))];
      final ent = svcWith(entRpc);
      final gateway = _FakeGateway();
      final billing = PlayBillingService(
        gateway: gateway,
        verifier: ({required productId, required purchaseToken}) async => true,
        entitlement: ent,
      );

      await billing.handlePurchaseUpdates([
        PurchaseDetails(
          purchaseID: 'order-2',
          productID: ZoneBillingProducts.annual,
          verificationData: PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: 'token-xyz',
            source: 'google_play',
          ),
          transactionDate: '1698500000000',
          status: PurchaseStatus.restored,
        ),
      ]);

      expect(gateway.completed, ['order-2'],
          reason: 'solo se completa (ack) cuando el backend verificó');
      expect(billing.uiState.value.state, BillingState.ready);
      expect((await ent.load()).allowsBluetooth, isTrue);
    });

    test('cancelación del usuario → mensaje exacto, sin estado premium', () async {
      final ent = svcWith(_FakeEntitlementRpc());
      final gateway = _FakeGateway();
      final billing = PlayBillingService(
        gateway: gateway,
        verifier: ({required productId, required purchaseToken}) async => false,
        entitlement: ent,
      );
      await billing.handlePurchaseUpdates([
        PurchaseDetails(
          purchaseID: 'order-3',
          productID: ZoneBillingProducts.monthly,
          verificationData: PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: '',
            source: 'google_play',
          ),
          transactionDate: '1698500000000',
          status: PurchaseStatus.canceled,
        ),
      ]);
      expect(billing.uiState.value.state, BillingState.error);
      expect(billing.uiState.value.message, 'Compra cancelada.');
      expect((await ent.load()).allowsBluetooth, isFalse);
    });

    test('sin productos de Play → ready con lista vacía (jamás precios '
        'inventados)', () async {
      final gateway = _FakeGateway();
      final billing = PlayBillingService(
        gateway: gateway,
        verifier: ({required productId, required purchaseToken}) async => false,
        entitlement: svcWith(_FakeEntitlementRpc()),
      );
      await billing.initialize();
      expect(billing.products.value, isEmpty);
      expect(billing.uiState.value.state, BillingState.ready);
    });
  });

  group('Invarianza fail-closed contra manipulación local (P-11, P-12)', () {
    test('P-11: flag local premium=true NO habilita nada sin backend', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      // Manipulación: el atacante escribe el flag local directamente.
      await PremiumService.instance.setPremium(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('zone_is_premium'), isTrue,
          reason: 'precondición: el flag local SÍ quedó manipulado');

      // El servicio delega en EntitlementService (backend verificado):
      // sin sesión en el entorno de test → free, sin importar el flag.
      final status = await PremiumService.instance.loadPremiumStatus();
      expect(status, isFalse,
          reason: 'un flag local jamás habilita Premium (diseño §6)');
      expect(EntitlementService.instance.allowsBluetooth, isFalse);
    });

    test('P-12: el gate de NearbyService.startRadar es backend, no UI', () async {
      // (a) Comportamiento del servicio de entitlement: sin verificación
      //     → el gate debe rechazar.
      final ent = svcWith(_FakeEntitlementRpc()); // backend free
      final snap = await ent.loadForce();
      expect(snap.allowsBluetooth, isFalse);

      // (b) Guard estático (patrón del repo: contratos de NearbyService se
      //     fijan por inspección de fuente, cf. p2p_nearby_service_ake_contract_test):
      //     startRadar() debe revalidar loadForce() y fallar ANTES de tocar
      //     cualquier API de radio.
      final source = await readRepoFile('lib/services/nearby_service.dart');
      final gateIdx = source.indexOf('EntitlementService.instance.loadForce()');
      final allowsIdx = source.indexOf('!entitlement.allowsBluetooth');
      final premiumErrIdx = source.indexOf('DiscoveryError.premiumRequired');
      final internalIdx = source.indexOf('_startRadarInternal()');
      expect(gateIdx, greaterThanOrEqualTo(0),
          reason: 'startRadar debe revalidar entitlement en el backend');
      expect(allowsIdx, greaterThan(gateIdx));
      expect(premiumErrIdx, greaterThan(allowsIdx));
      expect(internalIdx, greaterThan(premiumErrIdx),
          reason: 'el arranque real del radio solo ocurre DESPUÉS del gate');
      expect(source.indexOf('return false;', gateIdx),
          lessThan(internalIdx),
          reason: 'el gate devuelve false sin arrancar el radio');

      // (c) El enum del error premium existe y está documentado.
      final policy = await readRepoFile('lib/services/discovery_policy.dart');
      expect(policy.contains('premiumRequired'), isTrue);
    });
  });
}

/// Gateway fake de Play Billing: graba los acks (`completePurchase`) para
/// verificar el invariant fail-closed (P-03: sin verificación backend NO se
/// completa la compra).
class _FakeGateway implements BillingGateway {
  _FakeGateway();

  bool available = true;
  List<ProductDetails> products = const [];

  /// purchaseID de las compras completadas (ack) por el servicio.
  final List<String> completed = <String>[];

  int restoreCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Stream<List<PurchaseDetails>> purchaseEvents() => const Stream.empty();

  @override
  Future<List<ProductDetails>> queryProducts(Set<String> ids) async =>
      products.where((p) => ids.contains(p.id)).toList();

  @override
  Future<bool> buy(ProductDetails product) async => true;

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    final id = purchase.purchaseID;
    if (id != null) completed.add(id);
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls++;
  }
}

/// Lee un archivo del repo (helper para guards estáticos, igual que
/// sql_discovery_regression_test).
Future<String> readRepoFile(String relativePath) async {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    dir = dir.parent;
  }
  return File('${dir.path}/$relativePath').readAsString();
}
