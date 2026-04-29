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

  /// Solicita los permisos para la cámara y galería de fotos.
  static Future<bool> requestCameraAndGalleryPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.photos, // Se encarga de READ_MEDIA_IMAGES en Android 13+
    ].request();

    return statuses[Permission.camera]!.isGranted && 
           statuses[Permission.photos]!.isGranted;
  }

  /// Método legacy de compatibilidad
  static Future<bool> requestBlePermissions() => requestAllPermissions();
}
