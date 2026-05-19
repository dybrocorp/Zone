import 'package:shared_preferences/shared_preferences.dart';
import 'zone_id_service.dart';

/// Acceso Zone Premium (compra / flag en perfil).
class PremiumService {
  PremiumService._();
  static final PremiumService instance = PremiumService._();

  static const String _prefsPremiumKey = 'zone_is_premium';

  bool _cachedPremium = false;
  bool _loaded = false;

  bool get isPremium => _cachedPremium;

  Future<bool> loadPremiumStatus() async {
    final prefs = await SharedPreferences.getInstance();
    var premium = prefs.getBool(_prefsPremiumKey) ?? false;

    try {
      final profile = await ZoneIdService().getMyProfile();
      if (profile?['is_premium'] == true) {
        premium = true;
      }
    } catch (_) {
      // Columna is_premium puede no existir aún en Supabase.
    }

    _cachedPremium = premium;
    _loaded = true;
    return premium;
  }

  Future<void> setPremium(bool value) async {
    _cachedPremium = value;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsPremiumKey, value);
  }

  Future<bool> ensureLoaded() async {
    if (_loaded) return _cachedPremium;
    return loadPremiumStatus();
  }
}
