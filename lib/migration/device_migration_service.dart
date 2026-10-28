/// Z-213 PHASE F/G — Servicio de migración de dispositivo.
///
/// Estado: DISEÑADO + IMPLEMENTADO (unidades PROBADAS LOCALMENTE).
/// El adapter remoto es **fail-closed**: `requestBinding` lanza
/// [BackendNotProvisionedError] hasta que el dueño autorice staging/exec
/// (Z-212 §0 unmet). La migración A/B/C/D REAL requiere el backend.
///
/// Orquesta la máquina de estados (`device_migration_state.dart`) sobre una
/// [DeviceMigrationPersistence] y un [DeviceMigrationBackend]:
///
/// ```text
/// A(add)     : begin → markRequested → backend → (approved) → activate
/// B(replace) : begin(oldActive) → markRequested → backend → (approved)
///              → confirmAndActivate ⇒ UNIQUEMENTE aquí se revoca el
///                dispositivo previo (reason 'replaced') y se intercambia
///                el activo. Antes de confirm: NADA se destruye.
/// C(recover) : igual que A (semánticamente, en este cut local).
/// D(revoke)  : revokeActive(deviceId, confirm) — acción directa (sin
///              pendiente), exige razón de confirmación EXPLÍCITA.
/// ```
///
/// Garantías verificables en test:
/// - Idempotencia de begin/confirm (mismo intento, sin duplicados).
/// - NO-destroy-before-confirm (denied/expired/fallo RPC ⇒ activo intacto).
/// - Fail-closed en transición ilegal (typed error, cero mutación).
/// - El backend NO provisionado JAMÁS se interpreta como negación.
library;

import 'device_migration_state.dart';

/// Error del backend: el adapter remoto NO está provisionado (staging no
/// autorizado). El servicio NO lo interpreta como denied (no destruye).
class BackendNotProvisionedError implements Exception {
  const BackendNotProvisionedError(this.detail);

  final String detail;

  @override
  String toString() =>
      'BackendNotProvisionedError: el backend remoto de migración no está '
      'provisionado (Z-212 §0 sin cumplir) $detail';
}

/// Veredicto del backend para un pendiente.
enum DeviceMigrationBackendOutcome {
  approved,
  denied,
  expired,
}

/// Backend ABSTRACTO de migración. Única responsabilidad exponerse con el
/// contrato server-side de z213. UNA sola llamada por versión de pendiente.
abstract class DeviceMigrationBackend {
  const DeviceMigrationBackend();

  /// Envía/actualiza la solicitud y devuelve el VEREDICTO.
  /// El adapter remoto (instalado por la app real) lanza excepciones
  /// transitorias/`BackendNotProvisionedError`; el servicio las propaga
  /// SIN cambiar estado destructivo alguno.
  Future<DeviceMigrationBackendOutcome> requestDeviceBinding(
    DeviceMigrationPending pending,
  );
}

/// Adapter remoto de esta fase: fail-closed SIEMPRE (el deploy/exec de z213
/// NO está autorizado). Documentado en §12 del runbook: solo diseño local.
class RemoteDeviceMigrationBackend implements DeviceMigrationBackend {
  const RemoteDeviceMigrationBackend();

  @override
  Future<DeviceMigrationBackendOutcome> requestDeviceBinding(
    DeviceMigrationPending pending,
  ) async {
    throw const BackendNotProvisionedError(
      '(request_device_binding no exige firma server-side aún).',
    );
  }
}

/// Persistencia del estado de migración local (secure storage en producción;
/// in-memory para tests). NADA aquí toca Supabase.
abstract class DeviceMigrationPersistence {
  const DeviceMigrationPersistence();

  /// Todos los pendientes conocidos (cualquier fase).
  Future<List<DeviceMigrationPending>> loadPendings();

  /// Upsert del pendiente (idempotente por id).
  Future<void> savePending(DeviceMigrationPending pending);

  /// Id del dispositivo actualmente ACTIVO en esta cuenta local
  /// (null ⇒ sin dispositivo activo).
  Future<String?> loadActiveDeviceId();

  Future<void> saveActiveDeviceId(String? deviceId);

  /// Ledger LOCAL de revocaciones (espejo del server + revokes locales).
  /// Ítem: device_id + reason.
  Future<List<({String deviceId, String reason})>> loadRevocations();

  Future<void> appendRevocation(String deviceId, String reason);
}

/// Implementación in-memory (tests / proceso). Persistencia REAL la aporta
/// el puente de identidad (`device_identity_bridge.dart`) vía esta interfaz.
class InMemoryDeviceMigrationPersistence extends DeviceMigrationPersistence {
  final List<DeviceMigrationPending> _pendings = <DeviceMigrationPending>[];
  String? _activeDeviceId;
  final List<({String deviceId, String reason})> _revocations =
      <({String deviceId, String reason})>[];

  @override
  Future<List<DeviceMigrationPending>> loadPendings() async =>
      List.unmodifiable(_pendings);

  @override
  Future<void> savePending(DeviceMigrationPending pending) async {
    final idx = _pendings.indexWhere((p) => p.id == pending.id);
    if (idx == -1) {
      _pendings.add(pending);
    } else {
      _pendings[idx] = pending;
    }
  }

  @override
  Future<String?> loadActiveDeviceId() async => _activeDeviceId;

  @override
  Future<void> saveActiveDeviceId(String? deviceId) async {
    _activeDeviceId = deviceId;
  }

  @override
  Future<List<({String deviceId, String reason})>> loadRevocations() async =>
      List.unmodifiable(_revocations);

  @override
  Future<void> appendRevocation(String deviceId, String reason) async {
    _revocations.add((deviceId: deviceId, reason: reason));
  }
}

/// Servicio de migración: orquestación única sobre la máquina de estados.
class DeviceMigrationService {
  DeviceMigrationService({
    required DeviceMigrationPersistence persistence,
    DeviceMigrationBackend? backend,
  })  : _persistence = persistence,
        _backend = backend ?? const RemoteDeviceMigrationBackend();

  final DeviceMigrationPersistence _persistence;
  final DeviceMigrationBackend _backend;

  // ─────────────────────────────────────────────────────────────
  // B E G I N — creación/idempotencia del pendiente (IDs estables)
  // ─────────────────────────────────────────────────────────────

  /// Crea (o REUTILIZA, idempotente) el pendiente del intento.
  /// - MISMO (plan, deviceFingerprint) no terminal ⇒ MISMO id.
  /// - Pendiente previo terminal ⇒ intento NUEVO con id NUEVO.
  /// - plan == replace exige [oldActiveDeviceId] (regla de la máquina).
  Future<DeviceMigrationPending> beginMigration({
    required DeviceMigrationPlan plan,
    required String deviceFingerprint,
    String? oldActiveDeviceId,
    DateTime? now,
  }) async {
    final existing = await _persistence.loadPendings();
    for (final p in existing) {
      final matches =
          p.plan == plan &&
              p.deviceFingerprint == deviceFingerprint &&
              !p.isTerminal;
      if (matches) {
        return p; // IDEMPOTENTE: no muta, no duplica, mismo id.
      }
    }
    final fresh = newDeviceMigrationPending(
      plan: plan,
      deviceFingerprint: deviceFingerprint,
      oldActiveDeviceId: oldActiveDeviceId,
      now: now,
    );
    await _persistence.savePending(fresh);
    return fresh;
  }

  // ─────────────────────────────────────────────────────────────
  // P R O G R E S S — transiciones forward-only (fail-closed)
  // ─────────────────────────────────────────────────────────────

  /// draft → requested (se va a llamar al backend).
  Future<DeviceMigrationPending> markRequested(String pendingId) async {
    return _advance(
      pendingId,
      DeviceMigrationPhase.requested,
    );
  }

  /// requested → approved | denied | expired (veredicto backend).
  Future<DeviceMigrationPending> markBackendVerdict({
    required String pendingId,
    required DeviceMigrationBackendOutcome outcome,
  }) async {
    const phaseByOutcome = <DeviceMigrationBackendOutcome,
        DeviceMigrationPhase>{
      DeviceMigrationBackendOutcome.approved: DeviceMigrationPhase.approved,
      DeviceMigrationBackendOutcome.denied: DeviceMigrationPhase.denied,
      DeviceMigrationBackendOutcome.expired: DeviceMigrationPhase.expired,
    };
    return _advance(pendingId, phaseByOutcome[outcome]!);
  }

  Future<DeviceMigrationPending> _advance(
    String pendingId,
    DeviceMigrationPhase to,
  ) async {
    final pending = await _requirePending(pendingId);
    // Fail-closed: la regla vive en la máquina (única verdad); una transición
    // ilegal NO muta la persistencia.
    if (!isLegalDeviceMigrationTransition(pending.phase, to)) {
      throw MigrationStateError(
        'illegal_transition',
        'no existe ${to.wireValue} desde ${pending.phase.wireValue} '
        '(id=$pendingId, plan=${pending.plan.wireValue})',
      );
    }
    final next = pending.copyWith(phase: to);
    await _persistence.savePending(next);
    return next;
  }

  /// Ejecuta la llamada al backend y graba el veredicto.
  ///
  /// Garantía CRÍTICA (no-destroy): si el backend LANZA cualquier excepción
  /// (transitorio, no provisionado), se PROPAGA sin cambios — el activo
  /// previo y el pendiente quedan EXACTAMENTE como estaban.
  Future<DeviceMigrationPending> awaitBackendDecision(String pendingId) async {
    final pending = await _requirePending(pendingId);
    if (pending.phase != DeviceMigrationPhase.requested) {
      throw MigrationStateError(
        'preconditions',
        'awaitBackendDecision exige fase requested '
        '(actual: ${pending.phase.wireValue})',
      );
    }
    final verdict = await _backend.requestDeviceBinding(pending);
    return markBackendVerdict(pendingId: pendingId, outcome: verdict);
  }

  // ─────────────────────────────────────────────────────────────
  // C O N F I R M + activate — ÚNICO punto de destrucción de B
  // ─────────────────────────────────────────────────────────────

  /// approved → activated: intercambia el activo y (en replace) revoca el
  /// dispositivo previo con reason 'replaced' — SOLO aquí, nunca antes.
  /// Idempotente: pendiente ya `activated` ⇒ no-op (consistente).
  Future<DeviceMigrationPending> confirmAndActivate({
    required String pendingId,
    required String newDeviceId,
    List<int>? newDeviceX25519PublicKeyBytes,
  }) async {
    final pending = await _requirePending(pendingId);
    if (pending.phase == DeviceMigrationPhase.activated) {
      return pending; // idempotence (no-op, no double revocation).
    }
    // Transición legal única de la máquina.
    if (!isLegalDeviceMigrationTransition(
      DeviceMigrationPhase.approved,
      DeviceMigrationPhase.activated,
    ) ||
        pending.phase != DeviceMigrationPhase.approved) {
      throw MigrationStateError(
        'preconditions',
        'confirmAndActivate exige fase approved '
        '(actual: ${pending.phase.wireValue})',
      );
    }
    // B(replace): destrucción del activo previo EXCLUSIVAMENTE aquí.
    if (pending.isReplace) {
      final oldId = pending.oldActiveDeviceId;
      if (oldId == null || oldId.isEmpty) {
        throw const MigrationStateError(
          'preconditions',
          'replace plan requires old_active_device_id',
        );
      }
      await _persistence.appendRevocation(oldId, 'replaced');
    }
    await _persistence.saveActiveDeviceId(newDeviceId);
    return _advance(pendingId, DeviceMigrationPhase.activated);
  }

  // ─────────────────────────────────────────────────────────────
  // D (revoke) — acción directa con confirmación explícita
  // ─────────────────────────────────────────────────────────────

  /// Revoca el activo local. Destructor DIRECTO: exige [confirmReason]
  /// explícita ('user_initiated'|'lost'|'cleanup' — 'replaced' es SOLO
  /// del pipeline B automático). Sin ella ⇒ error, nada cambia.
  Future<void> revokeActive({
    required String deviceId,
    required String confirmReason,
  }) async {
    if (!const <String>['user_initiated', 'lost', 'cleanup']
        .contains(confirmReason)) {
      throw const MigrationStateError(
        'preconditions',
        'reason de revocación inválida (replaced reservada al pipeline B)',
      );
    }
    final active = await _persistence.loadActiveDeviceId();
    if (active == null || active != deviceId) {
      throw MigrationStateError(
        'preconditions',
        'el dispositivo $deviceId no es el activo (active: $active)',
      );
    }
    await _persistence.appendRevocation(deviceId, confirmReason);
    await _persistence.saveActiveDeviceId(null);
  }

  // ─────────────────────────────────────────────────────────────
  // R E A D — observadores (UI wiring)
  // ─────────────────────────────────────────────────────────────

  Future<DeviceMigrationPending?> pending(String pendingId) async {
    try {
      return await _requirePending(pendingId);
    } on MigrationStateError {
      return null;
    }
  }

  Future<DeviceMigrationPending> _requirePending(String pendingId) async {
    final all = await _persistence.loadPendings();
    for (final p in all) {
      if (p.id == pendingId) return p;
    }
    throw MigrationStateError('missing', 'pendiente inexistente: $pendingId');
  }

  Future<String?> activeDeviceId() => _persistence.loadActiveDeviceId();
}
