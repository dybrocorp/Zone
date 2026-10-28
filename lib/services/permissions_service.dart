import 'package:permission_handler/permission_handler.dart';
import 'logger_service.dart';

class PermissionsService {
  static final _logger = LoggerService();

  /// Set mínimo para Nearby Connections 4.3.0 (ver `DiscoveryPermissions`).
  static List<Permission> get corePermissions => [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.nearbyWifiDevices,
      ];

  /// Solicita el set mínimo y devuelve el mapa crudo (para clasificación
  /// estructurada del rechazo: denegado vs permanente).
  static Future<Map<Permission, PermissionStatus>>
      requestCoreStatuses() async {
    try {
      // Timeout de 8 segundos para evitar bloqueos infinitos al arranque
      return await corePermissions.request().timeout(
        const Duration(seconds: 8),
        onTimeout: () => {},
      );
    } catch (e) {
      _logger.debug('[PermissionsService] Error solicitando permisos: $e');
      return {};
    }
  }

  /// Solicita los permisos necesarios para Nearby Connections y BLE.
  static Future<bool> requestAllPermissions() async {
    final statuses = await requestCoreStatuses();
    if (statuses.isEmpty) return false;

    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        _logger.debug('Permiso fuertemente denegado en SO: $permission');
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
