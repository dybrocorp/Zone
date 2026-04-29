import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  /// Solicita los permisos necesarios para que el radar y el BLE funcionen correctamente en iOS y Android.
  static Future<bool> requestBlePermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();

    bool allGranted = true;
    for (var status in statuses.values) {
      if (!status.isGranted) {
        allGranted = false;
      }
    }
    return allGranted;
  }
}
