/// Z-213 PHASE F/G — Máquina de estados de migración de dispositivo (pura).
///
/// Estado: DISEÑADO + IMPLEMENTADO (unidades PROBADAS LOCALMENTE; backend
/// remoto NO autorizado — ver `device_migration_service.dart`).
///
/// Mapea 1:1 los `request_type`/`status` SERVER-SIDE de
/// `supabase_migrations/z213_account_device_identity.sql`:
///
/// ```text
/// plan      : add_device | replace_device | recover_account   (A/B/C)
/// fase local: draft → requested → approved | denied | expired
///             approved → activated  (terminal local)
/// plan D    : revoke — acción directa con confirm explícito (sin pendiente)
/// ```
///
/// Reglas INVARIOLÓGICAS (contrato que los test de regresión no deben poder
/// romperse sin cambiar este archivo):
///
/// 1. **IDs estables del pendiente**: cada solicitud de migración obtiene un
///    id UUIDv4 generado UNA VEZ; persistencia y UI siempre refieren al MISMO
///    intento. Un intento nuevo (pendiente terminal) crea un id NUEVO —
///    nunca se recicla el id de un intento terminal (auditoría limpia).
/// 2. **Idempotencia**: re-crear un pendiente NO terminal con el MISMO
///    (plan, deviceFingerprint) devuelve el pendiente existente SIN mutarlo
///    ni duplicarlo. Re-confirmar un pendiente `activated` es no-op.
/// 3. **NO destruir antes de confirmar**: en B(replace), el dispositivo
///    activo previo NO cambia de estado hasta `confirmAndActivate` (tras
///    veredicto `approved` del backend). Denied/expired/fallo RPC ⇒ el
///    activo previo queda intacto, SIEMPRE.
/// 4. **Fail-closed ante transición inválida**: el orden es solo adelante
///    (no salto de fase); un salto o retroceso lanza error tipado y NO
///    muta ningún registro.
/// 5. **Serializable**: toda la entidad es JSON-compatible para persistir
///    en secure storage (el puente serializa vía `toJson/fromJson`).
library;

import 'package:uuid/uuid.dart';

/// Tipos de plan — coinciden con `request_type` del backend (z213).
enum DeviceMigrationPlan {
  /// A — nuevo dispositivo en cuenta SIN activo (o D post-revoke).
  addDevice('add_device'),

  /// B — reemplazo: requiere dispositivo activo previo en la cuenta.
  replaceDevice('replace_device'),

  /// C — recuperación de cuenta (dispositivo sin backend activo).
  recoverAccount('recover_account');

  const DeviceMigrationPlan(this.wireValue);

  final String wireValue;

  static DeviceMigrationPlan? fromWire(String? value) {
    for (final p in DeviceMigrationPlan.values) {
      if (p.wireValue == value) return p;
    }
    return null;
  }
}

/// Fases locales del pendiente — coinciden con `status` del backend extendido
/// con `draft` (antes del RPC) y `activated` (commit local final).
enum DeviceMigrationPhase {
  draft('draft'),
  requested('pending'), // estado wire del backend: pending
  approved('approved'),
  denied('denied'),
  expired('expired'),
  activated('activated');

  const DeviceMigrationPhase(this.wireValue);

  final String wireValue;
}

/// Pendiente de migración (entidad persistida del intento).
class DeviceMigrationPending {
  DeviceMigrationPending({
    required this.id,
    required this.plan,
    required this.deviceFingerprint,
    required this.phase,
    required this.createdAt,
    required this.updatedAt,
    this.oldActiveDeviceId,
  });

  final String id;
  final DeviceMigrationPlan plan;
  final String deviceFingerprint;
  final DeviceMigrationPhase phase;
  final DateTime createdAt;

  final DateTime updatedAt;

  /// SOLO para plan == replaceDevice: id del dispositivo activo a destruir.
  final String? oldActiveDeviceId;

  bool get isReplace => plan == DeviceMigrationPlan.replaceDevice;
  bool get requiresOldDevice => isReplace;

  bool get isTerminal =>
      phase == DeviceMigrationPhase.activated ||
      phase == DeviceMigrationPhase.denied ||
      phase == DeviceMigrationPhase.expired;

  DeviceMigrationPending copyWith({DeviceMigrationPhase? phase}) {
    return DeviceMigrationPending(
      id: id,
      plan: plan,
      deviceFingerprint: deviceFingerprint,
      phase: phase ?? this.phase,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
      oldActiveDeviceId: oldActiveDeviceId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'plan': plan.wireValue,
        'device_fingerprint': deviceFingerprint,
        'phase': phase.wireValue,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (oldActiveDeviceId != null)
          'old_active_device_id': oldActiveDeviceId,
      };

  static DeviceMigrationPending? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['id'] as String?;
    final planWire = json['plan'] as String?;
    final phaseWire = json['phase'] as String?;
    if (id == null || planWire == null || phaseWire == null) return null;
    final plan = DeviceMigrationPlan.fromWire(planWire);
    if (plan == null) return null;
    DeviceMigrationPhase? phase;
    for (final p in DeviceMigrationPhase.values) {
      if (p.wireValue == phaseWire) phase = p;
    }
    if (phase == null) return null;
    return DeviceMigrationPending(
      id: id,
      plan: plan,
      deviceFingerprint: (json['device_fingerprint'] as String?) ?? '',
      phase: phase,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      oldActiveDeviceId: json['old_active_device_id'] as String?,
    );
  }
}

/// Error tipado del estado (fail-closed, mensaje UI-safe — sin material).
class MigrationStateError implements Exception {
  const MigrationStateError(this.reason, this.detail);

  final String reason;
  final String detail;

  @override
  String toString() => 'MigrationStateError($reason: $detail)';
}

/// Transición legal forward-only (tabla única de la máquina).
const Map<DeviceMigrationPhase, Set<DeviceMigrationPhase>>
    kDeviceMigrationTransitions = <DeviceMigrationPhase,
        Set<DeviceMigrationPhase>>{
  DeviceMigrationPhase.draft: {DeviceMigrationPhase.requested},
  DeviceMigrationPhase.requested: {
    DeviceMigrationPhase.approved,
    DeviceMigrationPhase.denied,
    DeviceMigrationPhase.expired,
  },
  DeviceMigrationPhase.approved: {DeviceMigrationPhase.activated},
  // Terminales (final): solo un intento NUEVO (id nuevo) los reemplaza.
  DeviceMigrationPhase.denied: {},
  DeviceMigrationPhase.expired: {},
  DeviceMigrationPhase.activated: {},
};

/// Regla: ¿puede el pendiente avanzar de [from] a [to]?
/// La lógica central vive aquí (única verdad); el servicio NO la recodifica.
bool isLegalDeviceMigrationTransition(
  DeviceMigrationPhase from,
  DeviceMigrationPhase to,
) =>
    kDeviceMigrationTransitions[from]?.contains(to) ?? false;

/// Crea una entity pendiente NUEVA con id UUIDv4 (una sola vez por intento).
/// [now] inyectable para tests determinísticos.
DeviceMigrationPending newDeviceMigrationPending({
  required DeviceMigrationPlan plan,
  required String deviceFingerprint,
  String? oldActiveDeviceId,
  DateTime? now,
  Uuid Function() uuidFactory = _defaultUuid,
}) {
  if (plan == DeviceMigrationPlan.replaceDevice &&
      (oldActiveDeviceId == null || oldActiveDeviceId.isEmpty)) {
    throw const MigrationStateError(
      'preconditions',
      'replace plan requires old_active_device_id',
    );
  }
  final stamp = (now ?? DateTime.now().toUtc());
  return DeviceMigrationPending(
    id: uuidFactory().v4(),
    plan: plan,
    deviceFingerprint: deviceFingerprint,
    phase: DeviceMigrationPhase.draft,
    createdAt: stamp,
    updatedAt: stamp,
    oldActiveDeviceId: oldActiveDeviceId,
  );
}

Uuid _defaultUuid() => const Uuid();
