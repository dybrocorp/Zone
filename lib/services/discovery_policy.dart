/// PHASE 2.2.6 — Discovery/ranging production-path contract (pure logic).
///
/// PRODUCTION TRANSPORT: Google Nearby Connections 4.3.0 (`P2P_CLUSTER`,
/// serviceId = applicationId `com.dybrocorp.zone`, endpoint name = ephemeral
/// token). BLE central scanning is LEGACY/UNUSED (see [requiresBle]).
///
/// Contract (transport ≠ identity):
/// ```
/// Nearby endpoint ID  → transport handle ONLY (ephemeral, per-session)
///     ↓ secure/profile exchange (validated payload, §6)
/// authoritative Zone identity (ZONE-XXXXXXXX / users.id, server-anchored)
///     ↓ EncounterKey (Phase 2.2.3, fail-closed)
/// encounter → USER ACTION → match (2.2.4/2.2.5)
/// ```
/// The endpoint ID must NEVER become: Zone ID, account ID, Supabase user ID,
/// match identity or encounter identity. [EndpointSessions.bindIdentity]
/// enforces this by accepting ONLY canonical `ZONE-XXXXXXXX` handles.
///
/// No radio code here: lifecycle/session/payload rules are pure and pinned
/// by tests; `NearbyService` wires them to the real plugin API.
library;

import 'package:permission_handler/permission_handler.dart';

import 'zone_id_service.dart';

/// PHASE 2.2.6 verdict: BLE central scanning is LEGACY/UNUSED. The production
/// path (Nearby Connections) never needs it: the RSSI gate is vacuous
/// (no GATT peripheral role, name-match never fires, `distanceMeters` is
/// never assigned). Pinned so no future change silently re-couples discovery
/// to BLE without a new architecture decision.
const bool requiresBle = false;

/// Structured discovery failure categories (§13). No secrets, tokens or key
/// material ever travel in these errors — endpoint IDs are truncated for logs.
enum DiscoveryError {
  permissionsDenied,
  permissionsPermanentlyDenied,
  bluetoothUnavailable,
  nearbyUnavailable,
  advertiseFailed,
  discoveryFailed,
  connectionFailed,
  connectionTimeout,
  invalidEndpointPayload,
  invalidZoneIdentity,
  handshakeFailed,
  endpointDisconnected,
}

/// Typed discovery failure (category + safe detail only).
class DiscoveryException implements Exception {
  const DiscoveryException(this.error, [this.detail = '']);

  final DiscoveryError error;
  final String detail;

  /// Endpoint IDs are ephemeral transport handles; log at most a short
  /// suffix so logs can never accumulate linkable identifiers.
  static String sanitizeEndpoint(String endpointId) {
    final id = endpointId.trim();
    if (id.length <= 8) return id;
    return '…${id.substring(id.length - 8)}';
  }

  @override
  String toString() =>
      'DiscoveryException: ${error.name}${detail.isEmpty ? '' : ' ($detail)'}';
}

/// Fail-closed identity/payload error (malformed handle or payload).
class InvalidDiscoveryIdentityError implements Exception {
  const InvalidDiscoveryIdentityError(this.cause);

  final String cause;

  @override
  String toString() => 'InvalidDiscoveryIdentityError: $cause';
}

/// Explicit service lifecycle (§3). Normal bilateral state is [ready]
/// (advertising + discovering, no endpoints yet); [connected] means ≥1 live
/// endpoint. [error] records terminal start failure (surfaced, never silent).
enum DiscoveryState {
  stopped,
  starting,
  advertising,
  discovering,
  ready,
  connected,
  stopping,
  error,
}

/// Pure lifecycle machine (idempotent start/stop; testable without radio).
class DiscoveryLifecycle {
  bool _advertising = false;
  bool _discovering = false;
  int _connected = 0;
  bool _starting = false;
  bool _stopping = false;
  DiscoveryError? _error;

  /// Guard against concurrent `startRadar` invocations (double-tap races).
  bool get canStart => !_starting && !_stopping;

  bool get acceptsCallbacks => !_stopping && _error == null;

  void beginStart() {
    if (_stopping) return;
    _starting = true;
    _error = null;
  }

  void transportUp({required bool advertising, required bool discovering}) {
    _starting = false;
    if (advertising) _advertising = true;
    if (discovering) _discovering = true;
  }

  void transportFailed(DiscoveryError error) {
    _starting = false;
    _error = error;
  }

  void endpointConnected() {
    _connected++;
  }

  void endpointDisconnected(int remaining) {
    _connected = remaining < 0 ? 0 : remaining;
  }

  void beginStop() {
    _stopping = true;
    _starting = false;
  }

  void stopped() {
    _advertising = false;
    _discovering = false;
    _connected = 0;
    _stopping = false;
    _starting = false;
    _error = null;
  }

  DiscoveryState get state {
    if (_error != null) return DiscoveryState.error;
    if (_stopping) return DiscoveryState.stopping;
    if (_starting) return DiscoveryState.starting;
    if (_connected > 0) return DiscoveryState.connected;
    if (_advertising && _discovering) return DiscoveryState.ready;
    if (_advertising) return DiscoveryState.advertising;
    if (_discovering) return DiscoveryState.discovering;
    return DiscoveryState.stopped;
  }

  DiscoveryError? get lastError => _error;
}

/// Ephemeral endpoint/session bookkeeping (§4–§5, §7 pure rules).
///
/// - Same endpoint rediscovered → resolve again ONLY if its token changed
///   (token rotation every 5 min re-advertises; blind re-resolve = radio churn).
/// - Connection attempt per endpoint is single-flight (CASE A/B).
/// - Fail/disconnect/lost drop ephemeral state; future rediscovery works
///   (CASE C/D). Nothing here is persisted: restart-safe by reconstruction.
/// - Identity binding accepts ONLY canonical ZONE handles (CASE E + §2).
class EndpointSessions {
  final Map<String, String> _lastToken = {};
  final Set<String> _attempts = {};
  final Set<String> _connected = {};
  final Map<String, String> _identity = {};

  /// True when this sighting needs (re-)resolution.
  bool noteFound(String endpointId, String token) {
    final prev = _lastToken[endpointId];
    _lastToken[endpointId] = token;
    return prev == null || prev != token;
  }

  /// Single-flight connection attempts. False = already connected/attempting.
  bool noteConnectionAttempt(String endpointId) {
    if (_connected.contains(endpointId) || _attempts.contains(endpointId)) {
      return false;
    }
    _attempts.add(endpointId);
    return true;
  }

  void noteConnected(String endpointId) {
    _attempts.remove(endpointId);
    _connected.add(endpointId);
  }

  void noteConnectionFailed(String endpointId) {
    _attempts.remove(endpointId);
  }

  void noteDisconnected(String endpointId) {
    _attempts.remove(endpointId);
    _connected.remove(endpointId);
    _lastToken.remove(endpointId);
    _identity.remove(endpointId);
  }

  void noteLost(String endpointId) {
    _attempts.remove(endpointId);
    _lastToken.remove(endpointId);
    _identity.remove(endpointId);
  }

  /// Binds a transport endpoint to its authoritative Zone identity.
  /// Fail-closed: anything that is not a canonical `ZONE-XXXXXXXX` handle
  /// (raw tokens, endpoint IDs, empty) throws — the endpoint ID must NEVER
  /// become identity. Two endpoints sharing one Zone ID are both recorded
  /// (the identity layer decides; discovery manufactures no semantics).
  void bindIdentity(String endpointId, String zoneId) {
    final z = zoneId.trim().toUpperCase();
    if (!ZoneIdService.isValidZoneIdFormat(z)) {
      throw InvalidDiscoveryIdentityError(
        'endpoint identity must be a ZONE-XXXXXXXX handle',
      );
    }
    _identity[endpointId] = z;
  }

  String? zoneFor(String endpointId) => _identity[endpointId];

  bool isConnected(String endpointId) => _connected.contains(endpointId);

  int get connectedCount => _connected.length;

  void clear() {
    _lastToken.clear();
    _attempts.clear();
    _connected.clear();
    _identity.clear();
  }
}

/// Payload rules (§6): minimal profile exchange, zero secrets.
class DiscoveryPayload {
  DiscoveryPayload._();

  /// Keys that must NEVER cross the radio (nor land in state/logs).
  static const forbiddenKeys = {
    'private_key',
    'privatekey',
    'privateKey',
    'seed',
    'secret',
    'token',
    'access_token',
    'accesstoken',
    'refresh_token',
    'password',
    'credential',
    'auth',
  };

  /// Validates an incoming `profile_exchange` data map. Returns the same map
  /// on success; throws fail-closed on malformed identity or secrets.
  /// `id` (users.id) may be absent offline — `zone_id` is mandatory.
  static Map<String, dynamic> validateProfileExchange(dynamic data) {
    if (data is! Map) {
      throw const InvalidDiscoveryIdentityError('profile payload not a map');
    }
    final map = Map<String, dynamic>.from(data);
    for (final key in map.keys) {
      final k = key.toString().toLowerCase().replaceAll('_', '');
      if (forbiddenKeys.contains(key.toString().toLowerCase()) ||
          forbiddenKeys.contains(k)) {
        throw const InvalidDiscoveryIdentityError(
          'profile payload carries forbidden key',
        );
      }
    }
    final zone = (map['zone_id'] as String?) ?? '';
    if (!ZoneIdService.isValidZoneIdFormat(zone.trim().toUpperCase())) {
      throw const InvalidDiscoveryIdentityError(
        'profile payload has invalid zone_id',
      );
    }
    return map;
  }

  /// Upstream encounter rule (§11): an encounter may be created ONLY from a
  /// bound authoritative Zone identity — never from a raw endpoint/token.
  static bool canCreateEncounter(String? boundZoneId) {
    if (boundZoneId == null || boundZoneId.isEmpty) return false;
    return ZoneIdService.isValidZoneIdFormat(boundZoneId.trim().toUpperCase());
  }
}

/// Permission classification (§8): minimum set for Nearby Connections 4.3.0
/// on current target SDK = location + bluetoothScan + bluetoothAdvertise +
/// bluetoothConnect + nearbyWifiDevices. Denial (incl. permanent) fails
/// gracefully — no radio, explicit error, no crash.
class DiscoveryPermissions {
  DiscoveryPermissions._();

  static DiscoveryError? classify(Map<Permission, PermissionStatus> statuses) {
    if (statuses.isEmpty) return DiscoveryError.permissionsDenied;
    var denied = false;
    for (final entry in statuses.entries) {
      if (!entry.value.isGranted) {
        if (entry.value.isPermanentlyDenied) {
          return DiscoveryError.permissionsPermanentlyDenied;
        }
        denied = true;
      }
    }
    return denied ? DiscoveryError.permissionsDenied : null;
  }
}
