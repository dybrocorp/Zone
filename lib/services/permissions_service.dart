import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  /// Solicita los permisos necesarios para Nearby Connections y BLE.
  static Future<bool> requestAllPermissions() async {
    final corePermissions = [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ];

    Map<Permission, PermissionStatus> statuses = await corePermissions.request();

    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        print('Permiso fuertemente denegado en SO: $permission');
        allGranted = false;
      }
    });

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
