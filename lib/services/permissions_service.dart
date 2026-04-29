import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  /// Solicita los permisos necesarios para Nearby Connections y BLE.
  static Future<bool> requestAllPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
      Permission.storage,
    ].request();

    bool allGranted = true;
    for (var status in statuses.values) {
      if (!status.isGranted) {
        allGranted = false;
      }
    }

    return allGranted;
  }

  /// Método legacy de compatibilidad
  static Future<bool> requestBlePermissions() => requestAllPermissions();
}
