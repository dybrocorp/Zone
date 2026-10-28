import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'entitlement_service.dart';

/// Acceso Zone Premium (API de compatibilidad sobre `EntitlementService`).
///
/// **Refactor freemium:** la verdad de Premium ya NO es esta clase ni un
/// flag local: delega en `EntitlementService` (backend verificado, z215,
/// fail-closed · docs/redesign/ZONE_PREMIUM_BILLING.md §4-§6).
///
/// Mantenida por compatibilidad con los call-sites existentes (radar,
/// settings, pantalla de compra) antes de su re-paginación; los nuevos
/// entrypoints (gate BT) usan `EntitlementService` directamente.
///
/// `setPremium` se conserva por firma pero ya NO concede acceso: ningún
/// flujo del cliente habilita Premium por su cuenta. `donations_screen`
/// dejará de usarla para "comprar"; la compra real vive en
/// `PlayBillingService` + verificación backend.
class PremiumService {
  PremiumService._();

  static final PremiumService instance = PremiumService._();

  static const String _prefsPremiumKey = 'zone_is_premium';

  /// Estado derivado del último snapshot verificado (sin red nueva).
  /// Fail-closed: sin snapshot cargado → false.
  bool get isPremium => EntitlementService.instance.allowsBluetooth;

  /// Lee el estado Premium desde el backend (con caché TTL 5 min).
  Future<bool> loadPremiumStatus() async {
    final snapshot = await EntitlementService.instance.load();
    debugPrint(
        '[PremiumService] estado=${snapshot.state.name} '
        'source=${snapshot.verifiedSource}');
    return snapshot.allowsBluetooth;
  }

  /// Firma legacy usada por la compra simulada antigua. Ya NO concede
  /// acceso: solo persiste un marcador local de UI (inerte ante el gate;
  /// el gate nunca lee esta clave). La compra real la gestiona
  /// `PlayBillingService` con verificación backend.
  Future<void> setPremium(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsPremiumKey, value);
  }

  /// Limpia el marcador local inerte (higiene tras el refactor; el backend
  /// no se toca).
  Future<void> clearLocalMarker() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsPremiumKey);
  }

  /// Alias de [loadPremiumStatus] (compat: call-sites antiguos).
  Future<bool> ensureLoaded() => loadPremiumStatus();

  /// Sello de fuente para UI/reportes ('z215' o 'transitional_legacy_is_premium').
  Future<String> verifiedSource() async {
    final snap = EntitlementService.instance.lastSnapshot;
    return snap?.verifiedSource ?? 'z215';
  }
}
