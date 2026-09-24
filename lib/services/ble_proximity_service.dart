import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../config/radar_config.dart';
import 'logger_service.dart';

/// Escaneo BLE auxiliar para estimar distancia por RSSI.
/// Enlaza el token Nearby (nombre del endpoint) con la señal Bluetooth.
class BleProximityService {
  static final BleProximityService _instance = BleProximityService._internal();
  factory BleProximityService() => _instance;
  BleProximityService._internal();

  final _logger = LoggerService();

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSub;

  final Map<String, int> _tokenRssi = {};
  final Map<String, double> _tokenDistance = {};
  final Map<String, DateTime> _tokenUpdated = {};

  static const Duration _staleAfter = Duration(seconds: 25);

  // Z-204 (FASE 1.7): filtro del escaneo. Los únicos dispositivos que el radar
  // debe procesar son los que llevan el nombre del token Nearby de la app:
  //   • token online  → UUID v4 (generado con _uuid.v4() en generateBtToken)
  //   • token offline → 'OFFLINE:' + pseudónimo base64url (nearby_service)
  // Cualquier otro dispositivo BLE del entorno (beacons, audífonos, otros
  // teléfonos) se descarta ANTES de registrar RSSI → menos batería y ruido.
  static final RegExp _appTokenNamePattern = RegExp(
    r'^(?:OFFLINE:[A-Za-z0-9_\-]{32}|'
    r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$',
    caseSensitive: false,
  );

  static bool _isAppTokenName(String name) =>
      _appTokenNamePattern.hasMatch(name);

  bool get isScanning => _scanSub != null;

  Future<void> startScanning() async {
    if (_scanSub != null) return;
    _tokenRssi.clear();
    _tokenDistance.clear();
    _tokenUpdated.clear();

    _scanSub = _ble
        .scanForDevices(
          withServices: [],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
      (device) {
        _recordDevice(device);
      },
      onError: (Object e) {
        _logger.debug('[BleProximity] Error escaneo: $e');
      },
    );
  }

  void _recordDevice(DiscoveredDevice device) {
    // Z-204: descartar dispositivos ajenos (no llevan el token Nearby de la app).
    final name = device.name.trim();
    if (name.isEmpty || !_isAppTokenName(name)) {
      return;
    }

    final rssi = device.rssi;
    final distance = RadarConfig.distanceFromRssi(rssi);
    final keys = <String>{device.id, name};

    for (final key in keys) {
      final prev = _tokenRssi[key];
      if (prev == null || rssi > prev) {
        _tokenRssi[key] = rssi;
        _tokenDistance[key] = distance;
        _tokenUpdated[key] = DateTime.now();
      }
    }
  }

  void stopScanning() {
    _scanSub?.cancel();
    _scanSub = null;
  }

  void _purgeStale() {
    final cutoff = DateTime.now().subtract(_staleAfter);
    final stale = _tokenUpdated.entries
        .where((e) => e.value.isBefore(cutoff))
        .map((e) => e.key)
        .toList();
    for (final k in stale) {
      _tokenRssi.remove(k);
      _tokenDistance.remove(k);
      _tokenUpdated.remove(k);
    }
  }

  int? rssiForToken(String token) {
    _purgeStale();
    return _tokenRssi[token];
  }

  double? distanceForToken(String token) {
    _purgeStale();
    return _tokenDistance[token];
  }

  /// Si no hay RSSI para el token, devuelve null (no filtrar — Nearby ya lo vio).
  bool isTokenWithinRadius(String token, double radiusMeters) {
    final rssi = rssiForToken(token);
    if (rssi == null) return true;
    return RadarConfig.isRssiWithinRadius(rssi, radiusMeters);
  }

  double? distanceMetersForToken(String token) => distanceForToken(token);
}
