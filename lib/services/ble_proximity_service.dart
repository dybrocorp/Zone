import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../config/radar_config.dart';

/// Escaneo BLE auxiliar para estimar distancia por RSSI.
/// Enlaza el token Nearby (nombre del endpoint) con la señal Bluetooth.
class BleProximityService {
  static final BleProximityService _instance = BleProximityService._internal();
  factory BleProximityService() => _instance;
  BleProximityService._internal();

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSub;

  final Map<String, int> _tokenRssi = {};
  final Map<String, double> _tokenDistance = {};
  final Map<String, DateTime> _tokenUpdated = {};

  static const Duration _staleAfter = Duration(seconds: 25);

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
        print('[BleProximity] Error escaneo: $e');
      },
    );
  }

  void _recordDevice(DiscoveredDevice device) {
    final rssi = device.rssi;
    final distance = RadarConfig.distanceFromRssi(rssi);
    final keys = <String>{device.id};
    final name = device.name.trim();
    if (name.isNotEmpty) {
      keys.add(name);
    }

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
