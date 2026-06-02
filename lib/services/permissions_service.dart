import 'package:permission_handler/permission_handler.dart';
import 'logger_service.dart';

class PermissionsService {
  static final _logger = LoggerService();
  /// Solicita los permisos necesarios para Nearby Connections y BLE.
  static Future<bool> requestAllPermissions() async {
    try {
      final corePermissions = [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.nearbyWifiDevices,
      ];

      // Timeout de 8 segundos para evitar bloqueos infinitos al arranque
      Map<Permission, PermissionStatus> statuses = await corePermissions.request().timeout(
        const Duration(seconds: 8),
        onTimeout: () => {},
      );

      if (statuses.isEmpty) return false;

      bool allGranted = true;
      statuses.forEach((permission, status) {
        if (!status.isGranted) {
          _logger.debug('Permiso fuertemente denegado en SO: $permission');
          allGranted = false;
        }
      });

      return allGranted;
    } catch (e) {
      _logger.debug('[PermissionsService] Error solicitando permisos: $e');
      return false;
    }
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
