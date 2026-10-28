import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'entitlement_service.dart';
import 'logger_service.dart';

/// Facturación real de Google Play (`in_app_purchase`).
///
/// Diseño: docs/redesign/ZONE_FREEMIUM_ARCHITECTURE.md §2.5 y
/// docs/redesign/ZONE_PREMIUM_BILLING.md §3-§4.
///
/// Invariante no negociable: **el éxito de Play NO activa Premium.**
/// `PurchaseStatus.purchased` solo marca compra registrada → verificación
/// backend (`verify-play-purchase`, edge function del owner). El acceso se
/// activa solo cuando `EntitlementService` revalida contra z215. Fail-closed:
/// mientras el backend no verifique, el radar BT queda bloqueado y la UI
/// muestra "verificando…" (honesto, sin flag mágico).
///
/// Productos de suscripción (sin precios quemados: los precios llegan de
/// `ProductDetails` reales de Play; hasta entonces la UI desactiva compra):
/// `zone_premium_monthly`, `zone_premium_annual`.

/// Product IDs en Play Console (creados por el owner; placeholder documentado).
class ZoneBillingProducts {
  ZoneBillingProducts._();

  static const String monthly = 'zone_premium_monthly';
  static const String annual = 'zone_premium_annual';

  static const Set<String> all = {monthly, annual};
}

/// Estados expuestos del flujo de facturación (§2.5).
enum BillingState {
  /// Consultando disponibilidad/productos de Play.
  querying,

  /// Play disponible y productos cargados (pueden ser 0 si no hay config).
  ready,

  /// Play no disponible en este dispositivo/build.
  unavailable,

  /// Lanzando la compra en Play.
  purchaseInProgress,

  /// Compra en estado pending de Play.
  pending,

  /// Play la registró; verificación backend aún no confirma.
  succeededUnverified,

  /// Verificación backend pendiente (edge function ausente/fallando).
  /// Estado HONESTO: el entitlement solo se activa vía `EntitlementService`.
  verificationPending,

  /// Error explícito de Play o cancelación del usuario.
  error,
}

/// Estado de UI: estado + mensaje exacto (R3/R6).
@immutable
class BillingUiState {
  const BillingUiState(this.state, [this.message]);

  final BillingState state;
  final String? message;
}

/// Contrato inyectable del gateway de Play (prod: in_app_purchase;
/// tests: fake). Aísla TODO el contacto con el plugin: los tests no tocan
/// platform channels.
abstract class BillingGateway {
  Future<bool> isAvailable();
  Stream<List<PurchaseDetails>> purchaseEvents();
  Future<List<ProductDetails>> queryProducts(Set<String> ids);
  Future<bool> buy(ProductDetails product);
  Future<void> completePurchase(PurchaseDetails purchase);
  Future<void> restorePurchases();
}

/// Verificador de compra contra el backend.
/// Devuelve true SOLO si `verify-play-purchase` confirma el entitlement.
typedef PurchaseVerifier = Future<bool> Function({
  required String productId,
  required String purchaseToken,
});

/// Gateway producción con `in_app_purchase` (v3.x).
class PlayBillingGateway implements BillingGateway {
  final InAppPurchase _iap = InAppPurchase.instance;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Stream<List<PurchaseDetails>> purchaseEvents() => _iap.purchaseStream;

  @override
  Future<List<ProductDetails>> queryProducts(Set<String> ids) async {
    final response = await _iap.queryProductDetails(ids);
    return response.productDetails;
  }

  @override
  Future<bool> buy(ProductDetails product) {
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);

  @override
  Future<void> restorePurchases() => _iap.restorePurchases();
}

/// Verificador producción: edge function `verify-play-purchase` de Supabase.
/// La función existe SOLO cuando el owner la despliegue; mientras tanto
/// cualquier fallo → false (fail-closed, nunca acceso por fallo).
Future<bool> defaultVerifyPurchase({
  required String productId,
  required String purchaseToken,
}) async {
  if (purchaseToken.isEmpty) return false;
  String packageName;
  try {
    packageName = (await PackageInfo.fromPlatform()).packageName;
  } catch (_) {
    packageName = ''; // la edge function usará su env propio
  }
  try {
    final response = await Supabase.instance.client.functions.invoke(
      'verify-play-purchase',
      body: {
        'productId': productId,
        'purchaseToken': purchaseToken,
        if (packageName.isNotEmpty) 'packageName': packageName,
      },
    );
    final data = response.data;
    return data is Map && data['verified'] == true;
  } catch (_) {
    return false;
  }
}

class PlayBillingService {
  PlayBillingService({
    BillingGateway? gateway,
    PurchaseVerifier? verifier,
    EntitlementService? entitlement,
  })  : _gatewayOrNull = gateway,
        _verifierOrNull = verifier,
        _entitlement = entitlement ?? EntitlementService.instance;

  static final PlayBillingService instance = PlayBillingService();

  final BillingGateway? _gatewayOrNull;
  final PurchaseVerifier? _verifierOrNull;
  final EntitlementService _entitlement;

  static final LoggerService _logger = LoggerService();

  BillingGateway get _gateway {
    final g = _gatewayOrNull;
    if (g != null) return g;
    return PlayBillingGateway();
  }

  PurchaseVerifier get _verifier => _verifierOrNull ?? defaultVerifyPurchase;

  final ValueNotifier<BillingUiState> uiState =
      ValueNotifier(const BillingUiState(BillingState.querying));

  /// Productos reales de Play (precios incluidos). Vacío = sin datos aún.
  final ValueNotifier<List<ProductDetails>> products =
      ValueNotifier(const []);

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _initialized = false;
  bool _verificationInFlight = false;

  bool get isInitialized => _initialized;

  /// Inicializa Play Billing: disponibilidad + escucha de compras + productos.
  /// Jamás lanza: cualquier fallo → estado honesto (`unavailable`/`error`).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    BillingGateway gateway;
    try {
      gateway = _gateway;
      final available = await gateway.isAvailable();
      if (!available) {
        uiState.value = const BillingUiState(
          BillingState.unavailable,
          'Google Play no está disponible en este dispositivo.',
        );
        _listenPurchases();
        return;
      }
      _listenPurchases();
      await _queryProducts();
    } on Exception catch (e) {
      _logger.debug('[PlayBilling] initialize falló: $e');
      uiState.value = const BillingUiState(
        BillingState.unavailable,
        'Google Play no está disponible ahora mismo.',
      );
    } catch (e) {
      _logger.debug('[PlayBilling] initialize error: $e');
      uiState.value = const BillingUiState(
        BillingState.unavailable,
        'Google Play no está disponible ahora mismo.',
      );
    }
  }

  void _listenPurchases() {
    _purchaseSub ??= _gateway.purchaseEvents().listen(
      _onPurchases,
      onError: (Object e) {
        _logger.debug('[PlayBilling] stream error: $e');
        uiState.value = const BillingUiState(
          BillingState.error,
          'Error de facturación. Inténtalo de nuevo.',
        );
      },
    );
  }

  /// Consulta los productos REALES de Play. Si aún no existen (owner pendiente),
  /// lista vacía + mensaje honesto; jamás inventa precios ni planes.
  Future<void> _queryProducts() async {
    uiState.value = const BillingUiState(
        BillingState.querying, 'Cargando planes…');
    try {
      final resp = await _gateway.queryProducts(ZoneBillingProducts.all);
      final ordered = [
        for (final id in ZoneBillingProducts.all)
          ...resp.where((p) => p.id == id),
      ];
      products.value = List.unmodifiable(ordered);
      uiState.value = const BillingUiState(BillingState.ready);
      if (ordered.isEmpty) {
        uiState.value = const BillingUiState(
          BillingState.ready,
          'Los planes Premium aún no están publicados en esta app.',
        );
      }
    } on Exception catch (e) {
      _logger.debug('[PlayBilling] queryProducts falló: $e');
      uiState.value = const BillingUiState(
        BillingState.error,
        'No se pudieron cargar los planes. Inténtalo de nuevo.',
      );
    } catch (e) {
      _logger.debug('[PlayBilling] queryProducts error: $e');
      uiState.value = const BillingUiState(
        BillingState.error,
        'No se pudieron cargar los planes. Inténtalo de nuevo.',
      );
    }
  }

  /// Inicia la compra real en Play. NO concede acceso: tras el éxito de Play
  /// el estado pasa a verificación backend.
  Future<void> buyProduct(ProductDetails product) async {
    if (uiState.value.state == BillingState.purchaseInProgress) return;
    uiState.value = const BillingUiState(
      BillingState.purchaseInProgress,
      'Abriendo la compra…',
    );
    try {
      final launched = await _gateway.buy(product);
      if (!launched) {
        uiState.value = const BillingUiState(
          BillingState.error,
          'No se pudo iniciar la compra. Inténtalo de nuevo.',
        );
      }
    } on Exception catch (e) {
      _logger.debug('[PlayBilling] buy falló: $e');
      uiState.value = const BillingUiState(
        BillingState.error,
        'No se pudo iniciar la compra. Inténtalo de nuevo.',
      );
    } catch (e) {
      _logger.debug('[PlayBilling] buy error: $e');
      uiState.value = const BillingUiState(
        BillingState.error,
        'No se pudo iniciar la compra. Inténtalo de nuevo.',
      );
    }
  }

  /// Restaurar compras: consulta Play; el entitlement backend decide el
  /// estado final (los `restored` del stream pasan por la misma verificación
  /// que `purchased`).
  Future<void> restorePurchases() async {
    uiState.value = const BillingUiState(
      BillingState.purchaseInProgress,
      'Restaurando compras…',
    );
    try {
      // Play consulta compras anteriores; los `restored` llegan por el
      // stream y pasan por la misma verificación backend que `purchased`.
      // El entitlement backend manda: revalida y muéstralo tal cual es.
      await _gateway.restorePurchases();
      final snap = await _entitlement.loadForce();
      if (snap.allowsBluetooth) {
        uiState.value = const BillingUiState(
          BillingState.ready,
          'Premium restablecido.',
        );
      } else {
        // Honesto: si nada más llega a `restored`, no hay nada que restaurar.
        uiState.value = const BillingUiState(
          BillingState.ready,
          'No encontramos compras verificadas para restaurar.',
        );
      }
    } on Exception catch (e) {
      _logger.debug('[PlayBilling] restore falló: $e');
      uiState.value = const BillingUiState(
        BillingState.error,
        'No se pudo restaurar. Inténtalo de nuevo.',
      );
    } catch (e) {
      _logger.debug('[PlayBilling] restore error: $e');
      uiState.value = const BillingUiState(
        BillingState.error,
        'No se pudo restaurar. Inténtalo de nuevo.',
      );
    }
  }

  // ── purchase stream ─────────────────────────────────────────────────

  /// Punto de entrada testeable del stream de compras (los tests llaman
  /// aquí con fakes; en producción lo invoca la escucha de `purchaseStream`).
  @visibleForTesting
  Future<void> handlePurchaseUpdates(List<PurchaseDetails> purchases) =>
      _onPurchases(purchases);

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          uiState.value = const BillingUiState(
            BillingState.succeededUnverified,
            'Compra registrada — verificando con el servidor…',
          );
          await _verify(purchase);
          break;

        case PurchaseStatus.pending:
          uiState.value = const BillingUiState(
            BillingState.pending,
            'Tu compra está pendiente de confirmación del pago.',
          );
          break;

        case PurchaseStatus.error:
          final err = purchase.error;
          final errMessage = err?.message;
          uiState.value = BillingUiState(
            BillingState.error,
            (errMessage != null && errMessage.isNotEmpty)
                ? errMessage
                : 'La compra falló. Inténtalo de nuevo.',
          );
          break;

        case PurchaseStatus.canceled:
          uiState.value = const BillingUiState(
            BillingState.error,
            'Compra cancelada.',
          );
          break;
      }
    }
  }

  /// Verificación backend de una compra (§4). Solo si el backend confirma:
  ///  - se hace `completePurchase` (ack) — si el backend no confirma NO se
  ///    completa, evitando conceder accesos no verificados;
  ///  - se revalida `EntitlementService` (z215) para fijar la verdad final.
  Future<void> _verify(PurchaseDetails purchase) async {
    if (_verificationInFlight) return;
    _verificationInFlight = true;
    try {
      final token = _extractPurchaseToken(purchase);
      final verified = await _verifier(
        productId: purchase.productID,
        purchaseToken: token,
      );
      if (verified) {
        await _safeCompletePurchase(purchase);
        final snap = await _entitlement.loadForce();
        uiState.value = BillingUiState(
          BillingState.ready,
          snap.allowsBluetooth ? 'Compra verificada. ¡Eres Premium!' : null,
        );
      } else {
        // Honesto: verificación pendiente; el radar BT sigue bloqueado.
        uiState.value = const BillingUiState(
          BillingState.verificationPending,
          'Tu compra quedó registrada. Se activará cuando el server la '
          'verifique — puede tardar unos minutos.',
        );
        // Revalidamos por si la verificación aterrizó de todos modos:
        final snap = await _entitlement.loadForce();
        if (snap.allowsBluetooth) {
          await _safeCompletePurchase(purchase);
          uiState.value = const BillingUiState(
            BillingState.ready,
            'Compra verificada. ¡Eres Premium!',
          );
        }
      }
    } finally {
      _verificationInFlight = false;
    }
  }

  /// Extrae el purchaseToken de la compra (Android Play).
  String _extractPurchaseToken(PurchaseDetails purchase) {
    final server = purchase.verificationData.serverVerificationData;
    if (server.isNotEmpty) return server;
    try {
      final localJson = purchase.verificationData.localVerificationData;
      if (localJson.isNotEmpty) {
        final map = jsonDecode(localJson);
        if (map is Map) {
          final token = map['purchaseToken'];
          if (token is String) return token;
        }
      }
    } catch (_) {
      // receipt no JSON → token vacío; el verificador lo tratará como fallo.
    }
    return '';
  }

  Future<void> _safeCompletePurchase(PurchaseDetails purchase) async {
    try {
      await _gateway.completePurchase(purchase);
    } on Exception catch (e) {
      _logger.debug('[PlayBilling] completePurchase falló: $e');
    } catch (e) {
      _logger.debug('[PlayBilling] completePurchase error: $e');
    }
  }

  /// Deep link de gestión de suscripciones (R7).
  Future<bool> openSubscriptionManagement() {
    return launchUrl(
      Uri.parse('https://play.google.com/store/account/subscriptions'),
      mode: LaunchMode.externalApplication,
    );
  }

  void dispose() {
    _purchaseSub?.cancel();
    uiState.dispose();
    products.dispose();
  }
}
