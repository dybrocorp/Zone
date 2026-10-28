import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'logger_service.dart';
import 'zone_id_service.dart';

/// Fuente de verdad de Premium: backend verificado, nunca un flag local.
///
/// Diseño y matriz de estados: docs/redesign/ZONE_PREMIUM_BILLING.md §4-§6.
/// Schema backend: supabase_migrations/z215_user_entitlements.sql
/// (`get_my_entitlements()` RPC — única fuente autorizada).
///
/// Reglas no negociables:
///  1. Un `PurchaseStatus.purchased` del cliente NUNCA concede Premium.
///  2. Los fallos de red NO conceden acceso permanente: grace ≤ 24 h
///     solamente si hubo un entitlement verificado previo y aún no expirado
///     con ≥ 24 h hasta `expires_at`. Si faltan < 24 h → sin grace
///     (fail-closed).
///  3. Cualquier error de la RPC → `unknown` → radar BT BLOQUEADO.
///
/// **Transición (documentada, temporal):** si la RPC `get_my_entitlements`
/// no existe aún en el backend remoto (z215 sin aplicar por el owner con su
/// autorización), se usa el flag legacy `users.is_premium`
/// (`verifiedSource == 'transitional_legacy_is_premium'`). Es continuidad del
/// comportamiento actual, NO una verificación de compra: cuando z215 exista
/// en remoto, los entitlements verificados mandan y este fallback muere.

/// Estados posibles del entitlement Premium.
enum PremiumState {
  /// Sin entitlement.
  free,

  /// Compra registrada en Play, backend aún no confirmó (UI de compra).
  /// `EntitlementService` no lo produce: lo muestra `PlayBillingService`.
  verifying,

  /// Entitlement verificado con `expires_at` futura.
  active,

  /// Verificación temporalmente imposible y dentro de grace (≤ 24 h,
  /// con entitlement previo no expirado). PERMITIDO para BT.
  grace,

  /// Renovación cancelada pero sigue activo hasta expirar. PERMITIDO.
  canceledRenewal,

  /// Pasado `expires_at`, sin renovación. BLOQUEADO.
  expired,

  /// Play revocó/refundó. BLOQUEADO.
  refundedRevoked,

  /// RPC falló (falta backend, error de red sin grace, etc.). BLOQUEADO.
  unknown,
}

/// Snapshot inmutable del estado Premium leído del backend.
@immutable
class PremiumSnapshot {
  const PremiumSnapshot({
    required this.state,
    this.expiresAt,
    this.verifiedAt,
    required this.verifiedSource,
    this.fetchedAt,
  });

  final PremiumState state;

  /// Vigencia del entitlement (null si no aplica).
  final DateTime? expiresAt;

  /// Última verificación valedera del backend (`last_verified_at`).
  final DateTime? verifiedAt;

  /// Origen del dato: `'z215'` (RPC verificada) o
  /// `'transitional_legacy_is_premium'` (flag legacy del perfil server).
  final String verifiedSource;

  final DateTime? fetchedAt;

  /// ¿Puede usar el radar Bluetooth? Solo active/grace/canceledRenewal.
  bool get allowsBluetooth =>
      state == PremiumState.active ||
      state == PremiumState.grace ||
      state == PremiumState.canceledRenewal;
}

/// Contrato inyectable de la RPC de entitlements (prod: Supabase; tests: fake).
typedef EntitlementRpc = Future<dynamic> Function(String functionName);

/// Contrato inyectable del fallback legacy transicional (tests: fake).
typedef LegacyPremiumReader = Future<bool> Function();

/// Contrato inyectable de sesión (prod: Supabase.auth; tests: valor fijo).
typedef SessionChecker = bool Function();

typedef ClockFn = DateTime Function();

class EntitlementService {
  EntitlementService({
    EntitlementRpc? rpc,
    LegacyPremiumReader? legacyReader,
    ClockFn? clock,
    Duration? cacheTtl,
    SessionChecker? session,
  })  : _rpcOrNull = rpc,
        _legacyReader = legacyReader ?? _defaultLegacyReader,
        _clock = clock ?? DateTime.now,
        _session = session ?? _defaultHasSession,
        cacheTtl = cacheTtl ?? const Duration(minutes: 5);

  static final EntitlementService instance = EntitlementService();

  final EntitlementRpc? _rpcOrNull;
  final LegacyPremiumReader _legacyReader;
  final ClockFn _clock;
  final SessionChecker _session;

  static final LoggerService _logger = LoggerService();

  /// TTL de caché en sesión (diseño §6: 5 min).
  final Duration cacheTtl;

  PremiumSnapshot? _cache;
  Future<PremiumSnapshot>? _inFlight;

  EntitlementRpc get _rpc => _rpcOrNull ?? _defaultRpc;

  static Future<dynamic> _defaultRpc(String function) {
    return Supabase.instance.client.rpc(function);
  }

  static Future<bool> _defaultLegacyReader() async {
    final profile = await ZoneIdService().getMyProfile();
    return profile?['is_premium'] == true;
  }

  bool get _hasSession => _session();

  static bool _defaultHasSession() {
    try {
      return Supabase.instance.client.auth.currentUser?.id != null;
    } catch (_) {
      return false;
    }
  }

  /// Último snapshot conocido (sin red). null si nunca se cargó.
  PremiumSnapshot? get lastSnapshot => _cache;

  /// ¿Radar BT permitido según el último snapshot? (fail-closed: sin
  /// snapshot → false). NO refresca; los entrypoints llaman [load]/[loadForce].
  bool get allowsBluetooth {
    final snap = _cache;
    if (snap == null) return false;
    return snap.allowsBluetooth;
  }

  /// Lectura con caché (TTL [cacheTtl]). Coalescea llamadas concurrentes.
  Future<PremiumSnapshot> load() {
    final now = _clock();
    final snap = _cache;
    if (snap != null && snap.fetchedAt != null) {
      if (now.difference(snap.fetchedAt!) < cacheTtl) {
        return Future.value(snap);
      }
    }
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final op = _loadRaw();
    _inFlight = op;
    return op.whenComplete(() => _inFlight = null);
  }

  /// Revalida SIEMPRE contra el backend (cada intento de entrar al radar BT).
  Future<PremiumSnapshot> loadForce() => _loadRaw();

  Future<PremiumSnapshot> _loadRaw() async {
    if (!_hasSession) {
      _cache = snapshotForState(PremiumState.free, now: _clock());
      return _cache!;
    }
    final now = _clock();
    try {
      final raw = await _rpc('get_my_entitlements');
      final snap = _snapshotFromRpc(raw, now);
      _cache = snap;
      return snap;
    } on Exception catch (e) {
      // Transición: si la z215 aún no está aplicada en remoto, la RPC no
      // existe. Fallback legacy al flag server (nunca a flag local).
      if (_looksLikeMissingRpc(e)) {
        try {
          final legacy = await _legacyReader();
          final snap = PremiumSnapshot(
            state: legacy ? PremiumState.active : PremiumState.free,
            verifiedSource: 'transitional_legacy_is_premium',
            fetchedAt: now,
          );
          _cache = snap;
          return snap;
        } on Exception catch (legacyError) {
          _logger
              .debug('[EntitlementService] fallback legacy falló: $legacyError');
          final snap =
              snapshotForState(PremiumState.unknown, now: _clock(), error: e);
          _cache = snap;
          return snap;
        }
      }
      // Red/5xx/rpc-error: intento de grace SOLO con snapshot previo
      // verificado (z215) válido; si no hay → unknown (fail-closed).
      final snap = _graceFromPrevious(now, e);
      _cache = snap;
      return snap;
    } catch (e) {
      // Error inesperado (no Exception): fail-closed.
      _logger.debug('[EntitlementService] error inesperado: $e');
      final snap = snapshotForState(PremiumState.unknown, now: _clock());
      _cache = snap;
      return snap;
    }
  }

  /// Grace ≤ 24 h: requiere snapshot previo VERIFICADO (z215) con
  /// `expires_at` futura Y ≥ 24 h hasta vencer. Si faltan < 24 h → sin
  /// grace (fail-closed → expired). Nunca con fallback legacy previo.
  PremiumSnapshot _graceFromPrevious(DateTime now, Exception e) {
    final prev = _cache;
    if (prev == null ||
        prev.verifiedSource != 'z215' ||
        prev.expiresAt == null ||
        !prev.expiresAt!.isAfter(now)) {
      return snapshotForState(PremiumState.unknown, now: now, error: e);
    }
    final remaining = prev.expiresAt!.difference(now);
    if (remaining < const Duration(hours: 24)) {
      return PremiumSnapshot(
        state: PremiumState.expired,
        expiresAt: prev.expiresAt,
        verifiedAt: prev.verifiedAt,
        verifiedSource: 'z215',
        fetchedAt: now,
      );
    }
    return PremiumSnapshot(
      state: PremiumState.grace,
      expiresAt: prev.expiresAt,
      verifiedAt: prev.verifiedAt,
      verifiedSource: 'z215',
      fetchedAt: now,
    );
  }

  /// Clasifica la respuesta de `get_my_entitlements`:
  /// `{"entitlements": [ {product, verified, expires_at, renewal_state, ...} ]}`.
  PremiumSnapshot _snapshotFromRpc(dynamic raw, DateTime now) {
    if (raw is! Map) {
      throw const _ShapeException('respuesta sin forma de objeto');
    }
    final Object? rows = raw['entitlements'];
    if (rows is! List) {
      throw const _ShapeException('entitlements no es un array');
    }

    PremiumSnapshot? best;
    bool sawRefunded = false;

    for (final row in rows) {
      if (row is! Map) continue;
      if (row['verified'] != true) continue;
      final renewalState = (row['renewal_state'] as String?) ?? 'unknown';
      final expiresAt = _parseTimestamp(row['expires_at']);

      if (renewalState == 'refunded' || renewalState == 'expired') {
        sawRefunded = true;
        continue;
      }
      if (expiresAt == null || !expiresAt.isAfter(now)) {
        continue; // fila vencida
      }
      final snap = PremiumSnapshot(
        state: switch (renewalState) {
          'canceled' => PremiumState.canceledRenewal,
          'grace' => PremiumState.grace,
          _ => PremiumState.active,
        },
        expiresAt: expiresAt,
        verifiedAt: _parseTimestamp(row['last_verified_at']),
        verifiedSource: 'z215',
        fetchedAt: now,
      );
      if (best == null || (best.expiresAt?.isBefore(expiresAt) ?? true)) {
        best = snap;
      }
    }

    if (best != null) return best;
    if (sawRefunded) {
      return PremiumSnapshot(
        state: PremiumState.refundedRevoked,
        verifiedSource: 'z215',
        fetchedAt: now,
      );
    }
    // Filas verificadas todas vencidas → expired; array vacío → free.
    return snapshotForState(
      rows.isEmpty ? PremiumState.free : PremiumState.expired,
      now: now,
    );
  }

  /// Snapshot estándar para estados sin metadatos (fail-closed por defecto).
  static PremiumSnapshot snapshotForState(
    PremiumState state, {
    DateTime? now,
    Exception? error,
  }) {
    if (error != null) {
      _logger.debug('[EntitlementService] snapshot $state por error: $error');
    }
    return PremiumSnapshot(
      state: state,
      verifiedSource: 'z215',
      fetchedAt: now,
    );
  }

  DateTime? _parseTimestamp(Object? iso) {
    if (iso is! String) return null;
    return DateTime.tryParse(iso)?.toUtc();
  }

  static bool _looksLikeMissingRpc(Exception e) {
    // PostgREST: función inexistente → HTTP 404 con código PG 42883
    // (undefined_function); algunas versiones marc 'P404'. Detección amplia
    // y verificable por texto (sin red en tests: fakes inyectan error).
    if (e is PostgrestException) {
      final code = e.code;
      if (code == '404' || code == '42883' || code == 'P404') return true;
    }
    final msg = e.toString().toLowerCase();
    return msg.contains('could not find the function') ||
        (msg.contains('get_my_entitlements') &&
            (msg.contains('does not exist') ||
                msg.contains('not found') ||
                msg.contains('404')));
  }
}

class _ShapeException implements Exception {
  const _ShapeException(this.detail);

  final String detail;

  @override
  String toString() => 'EntitlementService shape error: $detail';
}

/// Mensajes de usuario por estado (capa UI los muestra tal cual).
extension PremiumStateMessages on PremiumState {
  String get message {
    switch (this) {
      case PremiumState.free:
        return 'El radar Bluetooth es parte de Zone Premium.';
      case PremiumState.verifying:
        return 'Verificando tu compra…';
      case PremiumState.active:
        return 'Eres Premium.';
      case PremiumState.grace:
        return 'Repasando tu suscripción… seguimos activos mientras tanto.';
      case PremiumState.canceledRenewal:
        return 'Premium sigue activo hasta la fecha de expiración.';
      case PremiumState.expired:
        return 'Tu Premium caducó. Renuévalo para usar el radar Bluetooth.';
      case PremiumState.refundedRevoked:
        return 'Tu compra fue reembolsada o revocada.';
      case PremiumState.unknown:
        return 'No pudimos verificar tu suscripción. Inténtalo de nuevo.';
    }
  }
}

/// Shorthands mínimos para la UI (semántica fail-closed intacta).
extension PremiumSnapshotX on PremiumSnapshot {
  bool get isUnknownState => state == PremiumState.unknown;
  bool get isFreeState => state == PremiumState.free;
}
