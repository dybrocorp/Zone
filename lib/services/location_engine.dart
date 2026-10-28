import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';

import '../config/discovery_config.dart';
import 'logger_service.dart';

/// Localización híbrida GPS + proveedores de red (fused Android).
///
/// Diseño: docs/redesign/ZONE_FREEMIUM_ARCHITECTURE.md §2.1 (decisión D1):
/// el SO combina fuentes (GPS / Wi-Fi / red móvil vía FusedLocationProvider);
/// esta capa CONSUME la lectura disponible y VALIDA su calidad (precisión y
/// antigüedad). No intenta "elegir Wi-Fi vs GPS" (equivocación de concepto).
///
/// La fuente se abstrae ([PositionSource]) para poder testear la lógica con
/// fixes sintéticos y sin red (misma tradición que `match_outbox_test`).

/// Lectura de ubicación normalizada del app.
class GeoFix {
  const GeoFix({
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.accuracyMeters,
    this.source = GeoSource.hybrid,
  });

  final double lat;
  final double lng;
  final DateTime timestamp;

  /// Precisión declarada en metros (null = desconocida).
  final double? accuracyMeters;
  final GeoSource source;

  bool isStale({required Duration maxAge, DateTime? now}) =>
      (now ?? DateTime.now()).difference(timestamp) > maxAge;
}

enum GeoSource { hybrid, gps, network }

/// Fallo tipado de ubicación (sin coordenadas, seguro para UI/logs).
enum GeoErrorCode {
  serviceDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  noFixUnusable, // precisión insuficiente o demasiado antiguo
  timeout,
  unknown,
}

class GeoException implements Exception {
  const GeoException(this.code, [this.detail = '']);

  final GeoErrorCode code;
  final String detail;

  @override
  String toString() => 'GeoException(${code.name})';
}

/// Contrato inyectable del proveedor de posición (test doubles incluidos).
abstract class PositionSource {
  Future<bool> isServiceEnabled();
  Future<GeoFix> getCurrentPosition({Duration timeout});
}

/// Implementación producción con `geolocator`
/// (decisión D1: FusedLocationProvider android = GPS+red combinadas).
class GeolocatorPositionSource implements PositionSource {
  const GeolocatorPositionSource();

  @override
  Future<bool> isServiceEnabled() => geo.Geolocator.isLocationServiceEnabled();

  @override
  Future<GeoFix> getCurrentPosition({Duration timeout = const Duration(seconds: 15)}) async {
    // `geolocator` exige pedir permiso por su API; usamos su permiso
    // equivalente y devolvemos un fallo tipado si no está concedido.
    final permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      final requested = await geo.Geolocator.requestPermission();
      if (requested == geo.LocationPermission.denied ||
          requested == geo.LocationPermission.deniedForever) {
        throw const GeoException(GeoErrorCode.permissionDenied);
      }
    } else if (permission == geo.LocationPermission.deniedForever) {
      throw const GeoException(GeoErrorCode.permissionPermanentlyDenied);
    }

    final position = await geo.Geolocator.getCurrentPosition(
      locationSettings: geo.LocationSettings(
        accuracy: geo.LocationAccuracy.best, // consume GPS+red combinados
        timeLimit: timeout,
      ),
    );

    return GeoFix(
      lat: position.latitude,
      lng: position.longitude,
      timestamp: position.timestamp,
      accuracyMeters: position.accuracy,
      // El motor fused del SO no distingue la fuente exacta de cada fix;
      // `gps` solo si se declara, si no network/híbrido.
      source: renderSource(position.isMocked),
    );
  }

  static GeoSource renderSource(bool mocked) =>
      mocked ? GeoSource.network : GeoSource.hybrid;
}

/// Motor del descubrimiento geográfico. Valida calidad de fix contra
/// `DiscoveryConfig` antes de exponer el dato al proveedor de red.
class LocationEngine {
  LocationEngine({PositionSource? source, PermissionChecker? permissions})
      : _source = source ?? const GeolocatorPositionSource(),
        _permissions = permissions ?? const PermissionHandlerChecker();

  final PositionSource _source;
  final PermissionChecker _permissions;
  final LoggerService _logger = LoggerService();

  GeoFix? _lastFix;

  /// Último fix válido en memoria (estado para la UI, nunca se congela).
  GeoFix? get lastValidFix {
    final fix = _lastFix;
    if (fix == null) return null;
    if (fix.isStale(maxAge: DiscoveryConfig.maxFixAge)) return null;
    return fix;
  }

  /// Obtiene un fix NUEVO y lo valida. Nunca inventa coordenadas.
  Future<GeoFix> acquireFix({bool allowRevalidation = true}) async {
    // 0) Estado del servicio de ubicación del SO.
    final serviceOn = await _source.isServiceEnabled();
    if (!serviceOn) {
      throw const GeoException(GeoErrorCode.serviceDisabled);
    }

    // 1) Permiso when-in-use.
    final status = await _permissions.status();
    if (status == PermissionStatus.denied) {
      final requested = await _permissions.request();
      if (requested != PermissionStatus.granted) {
        throw const GeoException(GeoErrorCode.permissionDenied);
      }
    } else if (status == PermissionStatus.permanentlyDenied ||
        status == PermissionStatus.restricted) {
      throw const GeoException(GeoErrorCode.permissionPermanentlyDenied);
    }

    // 2) Lectura.
    final GeoFix fix;
    try {
      fix = await _source.getCurrentPosition(
        timeout: const Duration(seconds: 15),
      );
    } on GeoException {
      rethrow;
    } catch (e) {
      _logger.debug('[LocationEngine] getCurrentPosition falló: $e');
      throw GeoException(GeoErrorCode.unknown, e.toString());
    }

    // 3) Calidad: precisión aceptable y antigüedad ≤ máx.
    final usable = DiscoveryConfig.isFixUsable(
      accuracyMeters: fix.accuracyMeters,
      timestamp: fix.timestamp,
      now: DateTime.now(),
    );
    // Fix del pasado: geolocator puede devolver timestamps con reloj de
    // plataforma distinto; validamos anti-futuro también.
    if (!usable) {
      _logger.debug('[LocationEngine] fix no usable (accuracy=${fix.accuracyMeters}, age ok)');
      throw const GeoException(GeoErrorCode.noFixUnusable);
    }

    _lastFix = fix;
    return fix;
  }

  /// Clamp al radio elegible (UI) — el servidor re-clampa su propio límite.
  double clampRadius(double meters) =>
      DiscoveryConfig.nearestAllowedRadius(meters);
}

/// Contrato de permisos (permission_handler en prod; fake en tests).
abstract class PermissionChecker {
  Future<PermissionStatus> status();
  Future<PermissionStatus> request();
}

class PermissionHandlerChecker implements PermissionChecker {
  const PermissionHandlerChecker();

  @override
  Future<PermissionStatus> status() => Permission.locationWhenInUse.status;

  @override
  Future<PermissionStatus> request() => Permission.locationWhenInUse.request();
}

/// Mensajes de usuario por tipo de fallo geo (capa UI los muestra tal cual).
extension GeoErrorMessages on GeoErrorCode {
  String get message {
    switch (this) {
      case GeoErrorCode.serviceDisabled:
        return 'Activa el servicio de ubicación del dispositivo para buscar gente cerca.';
      case GeoErrorCode.permissionDenied:
        return 'Zone necesita permiso de ubicación para el descubrimiento por GPS.';
      case GeoErrorCode.permissionPermanentlyDenied:
        return 'Permiso de ubicación bloqueado permanentemente. Ábrelo en Ajustes.';
      case GeoErrorCode.noFixUnusable:
        return 'Señal de ubicación débil. Inténtalo de nuevo o amplía el radio.';
      case GeoErrorCode.timeout:
        return 'La ubicación tardó demasiado en responder. Inténtalo otra vez.';
      case GeoErrorCode.unknown:
        return 'No se pudo obtener tu ubicación. Revisa la conexión e inténtalo de nuevo.';
    }
  }
}
