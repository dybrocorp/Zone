import 'dart:math';

/// Parámetros del radar de proximidad (Bluetooth / Nearby Connections).
///
/// Gratis: hasta 15 m. Premium: 20–100 m.
class RadarConfig {
  RadarConfig._();

  /// Distancia máxima por defecto (metros).
  static const double discoveryRadiusMeters = 15.0;

  /// Límite superior permitido con Zone Premium.
  static const double maxDiscoveryRadiusMeters = 100.0;

  /// Máximo gratis (más de 15 m requiere premium).
  static const double maxFreeDiscoveryRadiusMeters = 15.0;

  /// Distancia mínima (metros).
  static const double minDiscoveryRadiusMeters = 5.0;

  /// RSSI medido a 1 metro (calibración BLE estándar).
  static const int rssiAt1Meter = -59;

  /// Exponente de pérdida de trayectoria (2.0 = espacio libre).
  static const double pathLossExponent = 2.0;

  /// UUID de servicio BLE Zone (filtro de escaneo auxiliar).
  static const String zoneBleServiceUuid = '11111111-2222-3333-4444-555555555555';

  /// Clave SharedPreferences para radio personalizado.
  static const String prefsDiscoveryRadiusKey = 'radar_discovery_radius_meters';

  /// Radio efectivo: preferencia guardada o [discoveryRadiusMeters].
  static double effectiveRadius(double? savedMeters, {bool isPremium = false}) {
    final max = isPremium ? maxDiscoveryRadiusMeters : maxFreeDiscoveryRadiusMeters;
    if (savedMeters == null) {
      return discoveryRadiusMeters.clamp(minDiscoveryRadiusMeters, max);
    }
    return savedMeters.clamp(minDiscoveryRadiusMeters, max);
  }

  static double sliderMax({required bool isPremium}) =>
      isPremium ? maxDiscoveryRadiusMeters : maxFreeDiscoveryRadiusMeters;

  /// Estima distancia en metros a partir del RSSI (dBm).
  static double distanceFromRssi(int rssi) {
    final exponent = (rssiAt1Meter - rssi) / (10 * pathLossExponent);
    return pow(10, exponent).toDouble();
  }

  /// RSSI mínimo para estar dentro de [radiusMeters].
  static int minRssiForRadius(double radiusMeters) {
    if (radiusMeters <= 0) return 0;
    final loss = 10 * pathLossExponent * log(radiusMeters) / ln10;
    return (rssiAt1Meter - loss).round();
  }

  /// ¿El RSSI indica que el dispositivo está dentro del radio configurado?
  static bool isRssiWithinRadius(int rssi, double radiusMeters) {
    return rssi >= minRssiForRadius(radiusMeters);
  }

  /// ¿La distancia estimada está dentro del radio?
  static bool isDistanceWithinRadius(double? distanceMeters, double radiusMeters) {
    if (distanceMeters == null) return true;
    return distanceMeters <= radiusMeters;
  }

  static String formatDistance(double? meters) {
    if (meters == null) return '';
    if (meters < 1) return '<1 m';
    if (meters < 10) return '${meters.toStringAsFixed(1)} m';
    return '${meters.round()} m';
  }
}
