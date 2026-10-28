import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/discovery_config.dart';
import 'location_engine.dart';

/// Proveedor de descubrimiento por Internet (HTTPS vía RPCs de Supabase).
///
/// Diseño: docs/redesign/ZONE_FREEMIUM_ARCHITECTURE.md §2.2.
/// Contratos backend: `upsert_discovery_presence`, `discover_nearby_users`,
/// `set_discovery_preference`, `get_discovery_preferences`,
/// `expire_my_presence` (supabase_migrations/z214_discovery_geo.sql).
///
/// Garantías:
///  - nunca llama sin sesión autenticada (sin sesión → `DiscoveryAuthException`)
///  - nunca devuelve coordenadas de otros usuarios (el backend no las envía;
///    el modelo de fila aquí tampoco las contiene)
///  - distancia APROXIMADA calculada por el servidor (grid de 10 m)

/// Perfil visible recibido del backend (SIN coordenadas, por diseño).
class NearbyGeoUser {
  const NearbyGeoUser({
    required this.id,
    required this.zoneId,
    this.displayName,
    this.avatarUrl,
    this.publicKey,
    this.distanceMeters,
  });

  final String id;
  final String zoneId;
  final String? displayName;
  final String? avatarUrl;
  final String? publicKey;

  /// Distancia aproximada server-side (grid de 10 m); null si no llega.
  final double? distanceMeters;

  /// Label de distancia en el formato del repo (RadarConfig.formatDistance).
  String get distanceLabel {
    final d = distanceMeters;
    if (d == null) return '';
    if (d < 1) return '<1 m';
    if (d < 10) return '${d.toStringAsFixed(1)} m';
    return '${d.round()} m';
  }
}

class DiscoveryAuthException implements Exception {
  const DiscoveryAuthException();
  @override
  String toString() => 'Sesión requerida: el descubrimiento necesita autenticación.';
}

class DiscoveryServerException implements Exception {
  const DiscoveryServerException(this.detail);

  final String detail;

  @override
  String toString() => 'DiscoveryServerException: $detail';
}

/// Contrato inyectable de RPC (prod: Supabase; tests: fake sin red).
typedef DiscoveryRpc = Future<dynamic> Function(
  String functionName,
  Map<String, dynamic> params,
);

/// Contrato inyectable de sesión (prod: Supabase.auth; tests: valor fijo).
typedef SessionChecker = bool Function();

DiscoveryRpc defaultDiscoveryRpc() {
  return (function, params) async {
    return Supabase.instance.client.rpc(function, params: params);
  };
}

bool defaultHasSession() {
  try {
    return Supabase.instance.client.auth.currentUser?.id != null;
  } catch (_) {
    return false;
  }
}

class InternetDiscoveryProvider {
  InternetDiscoveryProvider({
    DiscoveryRpc? rpc,
    SessionChecker? session,
  })  : _rpc = rpc ?? defaultDiscoveryRpc(),
        _session = session ?? defaultHasSession;

  final DiscoveryRpc _rpc;
  final SessionChecker _session;

  /// Guard: ¿existe sesión autenticada?
  bool get hasSession => _session();

  /// Publica la presencia con el fix dado. El servidor valida consentimiento,
  /// visibilidad, cadencia (≥15 s) y TTL (30 min). Devuelve true si la aceptó.
  Future<bool> publishPresence(GeoFix fix, {required double radiusMeters}) async {
    _requireSession();
    try {
      await _rpc('upsert_discovery_presence', {
        'p_lat': fix.lat,
        'p_lng': fix.lng,
        'p_accuracy_m': (fix.accuracyMeters?.round() ?? 1000),
        'p_source': _sourceLabel(fix.source),
        'p_radius_m': radiusMeters.round(),
      });
      return true;
    } on Exception catch (e) {
      // Errores reales de red/permisos se elevan tipados; el servidor hace
      // no-op silencioso en pings demasiado pronto (no es excepción).
      throw DiscoveryServerException(e.toString());
    }
  }

  /// Busca usuarios autorizados alrededor de la posición dada.
  ///
  /// La RPC `discover_nearby_users` (RETURNS TABLE vía PostgREST) devuelve un
  /// ARRAY JSON de filas; cada fila contiene id/zone_id/display_name/
  /// avatar_url (solo si es pública)/public_key/distance_m. Nunca lat/lng.
  Future<List<NearbyGeoUser>> discover({
    required double lat,
    required double lng,
    required double radiusMeters,
  }) async {
    _requireSession();
    final dynamic raw;
    try {
      raw = await _rpc('discover_nearby_users', {
        'p_lat': lat,
        'p_lng': lng,
        'p_radius_m': radiusMeters.round(),
        'p_limit': DiscoveryConfig.defaultQueryLimit,
      });
    } on Exception catch (e) {
      throw DiscoveryServerException(e.toString());
    }
    return parseUserList(raw);
  }

  /// Guarda/actualiza preferencias (canal único seguro — NUNCA la tabla
  /// directa). Si se revoca el consentimiento el servidor borra la presencia.
  Future<void> savePreferences({
    required bool discoveryEnabled,
    required bool locationSharingEnabled,
    required double radiusMeters,
  }) async {
    _requireSession();
    // Clamp local al conjunto elegible; el servidor aplica el suyo igual.
    final radius = DiscoveryConfig.nearestAllowedRadius(radiusMeters);
    try {
      await _rpc('set_discovery_preference', {
        'p_enabled': discoveryEnabled,
        'p_location_consent': locationSharingEnabled,
        'p_radius_m': radius.round(),
      });
    } on Exception catch (e) {
      throw DiscoveryServerException(e.toString());
    }
  }

  /// Lee las preferencias server-side (bool por defecto FALSE).
  ///
  /// `get_discovery_preferences` RETURNS jsonb → llega un objeto JSON único
  /// (no array). Se valida el shape antes de leer claves (fail-closed).
  Future<DiscoveryPrefs> loadPreferences() async {
    _requireSession();
    final dynamic raw;
    try {
      raw = await _rpc('get_discovery_preferences', const <String, dynamic>{});
    } on Exception catch (e) {
      throw DiscoveryServerException(e.toString());
    }
    if (raw is! Map) {
      throw const DiscoveryServerException(
          'get_discovery_preferences devolvió una forma inesperada');
    }
    final map = raw;
    return DiscoveryPrefs(
      discoveryEnabled: map['discovery_enabled'] == true,
      locationSharingEnabled: map['location_sharing_enabled'] == true,
      radiusMeters: map['radius_m'] is num
          ? DiscoveryConfig.nearestAllowedRadius(
              (map['radius_m'] as num).toDouble())
          : DiscoveryConfig.defaultRadiusMeters,
    );
  }

  /// Borra la presencia en el servidor (ocultarse inmediato).
  Future<void> expirePresence() async {
    _requireSession();
    try {
      await _rpc('expire_my_presence', const <String, dynamic>{});
    } on Exception catch (e) {
      throw DiscoveryServerException(e.toString());
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────

  void _requireSession() {
    if (!hasSession) throw const DiscoveryAuthException();
  }

  String _sourceLabel(GeoSource s) {
    switch (s) {
      case GeoSource.gps:
        return 'gps';
      case GeoSource.network:
      case GeoSource.hybrid:
        return 'network';
    }
  }

  /// Parser único de filas de la RPC de descubrimiento. Acepta un array JSON
  /// de objetos (forma real de RETURNS TABLE por PostgREST) y descarta
  /// silenciosamente cualquier fila con forma inesperada (fail-closed).
  static List<NearbyGeoUser> parseUserList(dynamic raw) {
    if (raw is List) {
      final out = <NearbyGeoUser>[];
      for (final row in raw) {
        if (row is Map) {
          final map = Map<String, dynamic>.from(row);
          out.add(NearbyGeoUser(
            id: map['id'] as String? ?? '',
            zoneId: map['zone_id'] as String? ?? '',
            displayName: map['display_name'] as String?,
            avatarUrl: map['avatar_url'] as String?,
            publicKey: map['public_key'] as String?,
            distanceMeters:
                map['distance_m'] is num ? (map['distance_m'] as num).toDouble() : null,
          ));
        }
      }
      return out;
    }
    return const [];
  }
}

class DiscoveryPrefs {
  const DiscoveryPrefs({
    required this.discoveryEnabled,
    required this.locationSharingEnabled,
    required this.radiusMeters,
  });

  final bool discoveryEnabled;
  final bool locationSharingEnabled;
  final double radiusMeters;
}

/// Extensión de lista para usuarios geo (UI-friendly).
extension NearbyGeoUserList on List<NearbyGeoUser> {
  void sortByDistance() {
    sort((a, b) => (a.distanceMeters ?? double.infinity)
        .compareTo(b.distanceMeters ?? double.infinity));
  }
}
