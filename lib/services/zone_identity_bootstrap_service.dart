/// SERVICIO de bootstrap de la Identity Foundation — punto ÚNICO del producto.
///
/// PRODUCT INTEGRATION SLICE (autorizado CTO 2026-09-25).
///
/// Patrón de singleton consistente con `IsarService`/`SyncService`/`P2PSecurityService`.
/// Guarda SOLO el contexto público ([IdentityContext]) y el orquestador:
/// NUNCA contiene material privado en memoria persistida (las seeds se leen del
/// almacén seguro por operación, bajo demanda).
///
/// Contrato:
/// - **SINGLE PATH**: `bootstrap()` es el único punto de inicialización de
///   identidad del runtime; repetir la llamada (p.ej. Reintentar) devuelve el
///   contexto cacheado — segundo arranque de la app ⇒ LOAD, no CREATE.
/// - **Fail-closed**: si `run()` falla, cierra la instancia Isar abierta y
///   re-lanza el error tipado (diagnosable); no queda caché parcial.
/// - **Logging seguro**: solo account_id, device_id, fingerprints y estados
///   públicos (mandato §9). Nada de seeds/claves/tokens.
library;

import 'package:flutter/foundation.dart';

import '../identity/identity_bootstrap.dart';
import '../identity/identity_context.dart';

/// Servicio singleton de bootstrap de identidad del runtime.
class ZoneIdentityBootstrapService {
  ZoneIdentityBootstrapService._({
    Future<IdentityBootstrap> Function()? bootstrapFactory,
  }) : _bootstrapFactory = bootstrapFactory ?? IdentityBootstrap.initialize;

  static final ZoneIdentityBootstrapService _instance =
      ZoneIdentityBootstrapService._();

  factory ZoneIdentityBootstrapService() => _instance;

  /// Seam de tests: permite inyectar el orquestador sin plataforma.
  @visibleForTesting
  ZoneIdentityBootstrapService.forTest({
    Future<IdentityBootstrap> Function()? bootstrapFactory,
  }) : _bootstrapFactory = bootstrapFactory ?? IdentityBootstrap.initialize;

  final Future<IdentityBootstrap> Function() _bootstrapFactory;

  IdentityBootstrap? _bootstrap;
  IdentityContext? _context;

  bool get isInitialized => _context != null;

  /// Orquestador activo (exposición para fases posteriores 2.2.3/2.2.4).
  IdentityBootstrap? get activeBootstrap => _bootstrap;

  /// Ejecuta (o reutiliza) el bootstrap de identidad. Idempotente.
  Future<IdentityContext> bootstrap() async {
    final cached = _context;
    if (cached != null) {
      return cached;
    }

    final instance = await _bootstrapFactory();
    try {
      final context = await instance.run();
      _bootstrap = instance;
      _context = context;
      _logSafe(context);
      return context;
    } on Object {
      // Fail-closed: no dejar instancias Isar abiertas tras un fallo y no
      // cachear un contexto parcial. El error tipado se re-lanza (diagnosable).
      await instance.close();
      rethrow;
    }
  }

  /// Contexto público ya inicializado (fail-closed si no se ejecutó el bootstrap).
  IdentityContext get context {
    final value = _context;
    if (value == null) {
      throw StateError('ZoneIdentityBootstrapService: identity not bootstrapped.');
    }
    return value;
  }

  /// Logging de identificadores públicos SOLO (account_id, device_id, fingerprints,
  /// estados). Nunca material privado (mandato §9).
  void _logSafe(IdentityContext context) {
    debugPrint('[IdentityBootstrap] OK '
        'account_id=${context.accountId} '
        'device_id=${context.deviceId} '
        'device_status=${context.deviceStatus} '
        'account_fingerprint=${context.accountFingerprint} '
        'device_fingerprint=${context.deviceFingerprint} '
        'migration_state=${context.migrationState} '
        'account_created=${context.accountCreated} '
        'device_created=${context.deviceCreated}');
  }
}