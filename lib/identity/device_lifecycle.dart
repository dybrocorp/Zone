/// FASE 2.1 — Máquina de estados del ciclo de vida de dispositivo.
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Implementa la máquina formal aprobada (invariante I-030,
/// `PHASE_2_BOOTSTRAP_POLICY.md` §4):
///
/// ```
///                  bootstrap_account          confirm_bootstrap (code + firma)
///   (ninguno) ──────────────────▶ PENDING ────────────────────────────────▶ ACTIVE
///                                     ├── timeout TTL ─▶ GONE (GC de artefactos;
///                                     │                   la cuenta legacy queda intacta)
///                                     ├── MAX_ATTEMPTS ─▶ LOCKED
///                                     └── bootstrap_cancel/cold_block ─▶ KILLED
///  ACTIVE ── revoke_device ──▶ REVOKED        ACTIVE ── compromiso ──▶ COMPROMISED
/// ```
///
/// Sin transiciones indefinidas; PENDING carece de todo derecho (I-030).
library;

import 'identity_errors.dart';
import 'keys.dart';

/// Eventos que provocan transiciones, con la nomenclatura de FASE 2.0.
enum DeviceLifecycleEvent {
  /// `bootstrap_account` crea el primer dispositivo (pending).
  bootstrapInitiated,

  /// `confirm_bootstrap` (código de 1 uso + firma) activa el dispositivo.
  bootstrapConfirmed,

  /// Timeout del TTL del código: los artefactos se recolectan (GONE).
  bootstrapExpired,

  /// MAX_ATTEMPTS de confirmación fallidos (cool-down). → LOCKED
  maxAttemptsReached,

  /// `bootstrap_cancel` / `cold_block`. → KILLED
  cancelled,

  /// `revoke_device` con firma de cuenta. → REVOKED
  deviceRevoked,

  /// Detección de compromiso. → COMPROMISED
  deviceCompromised,
}

/// Resultado de aplicar un evento a un estado.
enum DeviceLifecycleResult {
  /// Transición válida a otro estado materializado (ver [nextStatus]).
  transitioned,

  /// La máquina indica que el registro debe ser eliminado (GC tras timeout).
  gone,

  /// Transición prohibida.
  invalid,
}

/// Máquina de estados determinista del dispositivo (I-030).
///
/// Las transiciones permitidas se modelan explícitamente; cualquier otra
/// combinación devuelve [DeviceLifecycleResult.invalid] o lanza
/// [InvalidDeviceStateTransitionError] cuando se usa la API estricta.
class DeviceLifecycle {
  const DeviceLifecycle._();

  /// Estados terminales: ninguna transición sale de ellos.
  static const Set<DeviceStatus> terminalStates = {
    DeviceStatus.revoked,
    DeviceStatus.compromised,
    DeviceStatus.locked,
    DeviceStatus.killed,
  };

  /// Estados con derechos: solo ACTIVE (PENDING carece de todo derecho, I-030).
  static const Set<DeviceStatus> privilegedStates = {DeviceStatus.active};

  /// Evaluación pura del evento sobre el estado actual.
  static DeviceLifecycleResult evaluate(
    DeviceStatus current,
    DeviceLifecycleEvent event,
  ) {
    switch (current) {
      case DeviceStatus.pending:
        switch (event) {
          case DeviceLifecycleEvent.bootstrapInitiated:
            // PENDING → PENDING (re-solicitud de código rota el intento pero no
            // cambia el estado materializado del primer dispositivo).
            return DeviceLifecycleResult.transitioned;
          case DeviceLifecycleEvent.bootstrapConfirmed:
            return DeviceLifecycleResult.transitioned;
          case DeviceLifecycleEvent.bootstrapExpired:
            return DeviceLifecycleResult.gone;
          case DeviceLifecycleEvent.maxAttemptsReached:
            return DeviceLifecycleResult.transitioned;
          case DeviceLifecycleEvent.cancelled:
            return DeviceLifecycleResult.transitioned;
          case DeviceLifecycleEvent.deviceRevoked:
          case DeviceLifecycleEvent.deviceCompromised:
            return DeviceLifecycleResult.invalid;
        }
      case DeviceStatus.active:
        switch (event) {
          case DeviceLifecycleEvent.deviceRevoked:
          case DeviceLifecycleEvent.deviceCompromised:
            return DeviceLifecycleResult.transitioned;
          case DeviceLifecycleEvent.bootstrapInitiated:
          case DeviceLifecycleEvent.bootstrapConfirmed:
          case DeviceLifecycleEvent.bootstrapExpired:
          case DeviceLifecycleEvent.maxAttemptsReached:
          case DeviceLifecycleEvent.cancelled:
            return DeviceLifecycleResult.invalid;
        }
      case DeviceStatus.revoked:
      case DeviceStatus.compromised:
      case DeviceStatus.locked:
      case DeviceStatus.killed:
        // Estados terminales: sin salida.
        return DeviceLifecycleResult.invalid;
    }
  }

  /// Estado destino si [evaluate] devuelve [DeviceLifecycleResult.transitioned];
  /// [DeviceLifecycleResult.gone] devuelve null; si el evento es inválido lanza
  /// [InvalidDeviceStateTransitionError] (API estricta fail-closed).
  static DeviceStatus? nextStatus(
    DeviceStatus current,
    DeviceLifecycleEvent event,
  ) {
    final result = evaluate(current, event);
    switch (result) {
      case DeviceLifecycleResult.transitioned:
        switch (event) {
          case DeviceLifecycleEvent.bootstrapInitiated:
            return DeviceStatus.pending;
          case DeviceLifecycleEvent.bootstrapConfirmed:
            return DeviceStatus.active;
          case DeviceLifecycleEvent.maxAttemptsReached:
            return DeviceStatus.locked;
          case DeviceLifecycleEvent.cancelled:
            return DeviceStatus.killed;
          case DeviceLifecycleEvent.deviceRevoked:
            return DeviceStatus.revoked;
          case DeviceLifecycleEvent.deviceCompromised:
            return DeviceStatus.compromised;
          case DeviceLifecycleEvent.bootstrapExpired:
            return null; // GONE (GC) — no se materializa ningún estado.
        }
      case DeviceLifecycleResult.gone:
        return null;
      case DeviceLifecycleResult.invalid:
        throw InvalidDeviceStateTransitionError(current.statusId, event.name);
    }
  }
}
