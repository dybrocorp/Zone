/// PHASE 2.2.1 — KAT de transiciones de la máquina de migración de identidad.
///
/// NEW FOUNDATION EXTENSION — NOT YET INTEGRATED IN THE APP FLOW.
///
/// Matriz exhaustiva 9 estados × 12 eventos: para cada combinación se verifica
/// `evaluate` y `nextState` (API estricta fail-closed). Las transiciones siguen
/// `docs/migration/IDENTITY_MACHINE_STATE_MACHINE.md` §4/§5 y su actualización
/// bajo ADR-0001 (import en BRIDGED):
///
/// - sin saltos hacia delante;
/// - `FINALIZED` y `MIGRATION_FAILED` terminales;
/// - `MIGRATION_FAILED → LEGACY` es la ÚNICA transición hacia atrás;
/// - determinismo: misma (estado, evento) ⇒ mismo resultado (idempotencia de
///   revaloración).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/identity_errors.dart';
import 'package:zone/identity/migration_state_machine.dart';

/// Mapa de expectativas: estado actual → (evento → estado destino) o nulo si la
/// transición está PROHIBIDA. Fijado por la arquitectura, no por la
/// implementación.
MigrationState? _expectedTarget(MigrationState state, MigrationEvent event) {
  switch (state) {
    case MigrationState.legacy:
      return event == MigrationEvent.migrationStarted
          ? MigrationState.discovered
          : null;
    case MigrationState.discovered:
      switch (event) {
        case MigrationEvent.validationSucceeded:
          return MigrationState.validated;
        case MigrationEvent.validationFailed:
          return MigrationState.migrationFailed;
        default:
          return null;
      }
    case MigrationState.validated:
      switch (event) {
        case MigrationEvent.bridgeCompleted:
          return MigrationState.bridged;
        case MigrationEvent.bridgeFailed:
          return MigrationState.migrationFailed;
        default:
          return null;
      }
    case MigrationState.bridged:
      switch (event) {
        case MigrationEvent.bootstrapConfirmed:
          return MigrationState.authorized;
        case MigrationEvent.bootstrapFailed:
          return MigrationState.migrationFailed;
        default:
          return null;
      }
    case MigrationState.authorized:
      return event == MigrationEvent.singleWriterActivated
          ? MigrationState.migrated
          : null;
    case MigrationState.migrated:
      switch (event) {
        case MigrationEvent.verificationSucceeded:
          return MigrationState.verified;
        case MigrationEvent.verificationFailed:
          return MigrationState.migrationFailed;
        default:
          return null;
      }
    case MigrationState.verified:
      return event == MigrationEvent.finalized
          ? MigrationState.finalized
          : null;
    case MigrationState.finalized:
      return null; // Terminal: sin salida (ni rollback).
    case MigrationState.migrationFailed:
      return event == MigrationEvent.rollbackConfirmed
          ? MigrationState.legacy
          : null;
  }
}

void main() {
  group('KAT de transiciones (matriz exhaustiva)', () {
    test('todas las combinaciones (estado × evento) cumplen el mapa '
        'arquitectónico', () {
      var checked = 0;
      for (final state in MigrationState.values) {
        for (final event in MigrationEvent.values) {
          final expected = _expectedTarget(state, event);
          final result = MigrationStateMachine.evaluate(state, event);
          if (expected == null) {
            expect(
              result,
              MigrationTransitionResult.invalid,
              reason: '${state.statusId}+${event.name} debe ser inválida',
            );
            expect(
              () => MigrationStateMachine.nextState(state, event),
              throwsA(isA<InvalidMigrationStateTransitionError>()),
              reason: '${state.statusId}+${event.name} debe lanzar fail-closed',
            );
          } else {
            expect(
              result,
              MigrationTransitionResult.transitioned,
              reason: '${state.statusId}+${event.name} debe transicionar',
            );
            expect(
              MigrationStateMachine.nextState(state, event),
              expected,
              reason: '${state.statusId}+${event.name} → ${expected.statusId}',
            );
          }
          checked++;
        }
      }
      expect(checked, MigrationState.values.length * MigrationEvent.values.length);
    });

    test('determinismo: revalorar la misma combinación da el mismo resultado '
        '(idempotencia de revaloración)', () {
      for (final state in MigrationState.values) {
        for (final event in MigrationEvent.values) {
          expect(
            MigrationStateMachine.evaluate(state, event),
            MigrationStateMachine.evaluate(state, event),
          );
        }
      }
    });
  });

  group('Camino legal completo', () {
    test('LEGACY → FINALIZED paso a paso (sin saltos)', () {
      final events = <MigrationEvent>[
        MigrationEvent.migrationStarted, // → discovered
        MigrationEvent.validationSucceeded, // → validated
        MigrationEvent.bridgeCompleted, // → bridged
        MigrationEvent.bootstrapConfirmed, // → authorized
        MigrationEvent.singleWriterActivated, // → migrated
        MigrationEvent.verificationSucceeded, // → verified
        MigrationEvent.finalized, // → finalized
      ];
      final expected = <MigrationState>[
        MigrationState.discovered,
        MigrationState.validated,
        MigrationState.bridged,
        MigrationState.authorized,
        MigrationState.migrated,
        MigrationState.verified,
        MigrationState.finalized,
      ];
      var current = MigrationState.legacy;
      for (var i = 0; i < events.length; i++) {
        current = MigrationStateMachine.nextState(current, events[i]);
        expect(current, expected[i]);
      }
    });

    test('estados terminales sin salida: FINALIZED no admite nada; '
        'MIGRATION_FAILED solo rollbackConfirmed (única salida a LEGACY)',
        () {
      for (final event in MigrationEvent.values) {
        expect(
          MigrationStateMachine.evaluate(MigrationState.finalized, event),
          MigrationTransitionResult.invalid,
          reason: 'finalized es terminal; ${event.name} prohibido',
        );
      }
      for (final event in MigrationEvent.values) {
        final expected =
            event == MigrationEvent.rollbackConfirmed
            ? MigrationTransitionResult.transitioned
            : MigrationTransitionResult.invalid;
        expect(
          MigrationStateMachine.evaluate(MigrationState.migrationFailed, event),
          expected,
          reason:
              'migration_failed solo sale por rollbackConfirmed; ${event.name} '
              '→ $expected',
        );
      }
    });
  });

  group('Fail-closed y prohibiciones (§5 arquitectura)', () {
    test('sin saltos hacia delante: eventos solo válidos en su estado previo',
        () {
      // DISCOVERED → MIGRATED (salto de 4) — prohibido.
      expect(
        MigrationStateMachine.evaluate(
          MigrationState.discovered,
          MigrationEvent.singleWriterActivated,
        ),
        MigrationTransitionResult.invalid,
      );
      // LEGACY → VERIFIED sin pasar por el bridge — prohibido.
      expect(
        MigrationStateMachine.evaluate(
          MigrationState.legacy,
          MigrationEvent.verificationSucceeded,
        ),
        MigrationTransitionResult.invalid,
      );
      // VALIDATED → AUTHORIZED (salta BRIDGED) — prohibido.
      expect(
        MigrationStateMachine.evaluate(
          MigrationState.validated,
          MigrationEvent.bootstrapConfirmed,
        ),
        MigrationTransitionResult.invalid,
      );
    });

    test('MIGRATION_FAILED solo sale vía rollbackConfirmed', () {
      for (final event in MigrationEvent.values) {
        if (event == MigrationEvent.rollbackConfirmed) continue;
        expect(
          MigrationStateMachine.evaluate(MigrationState.migrationFailed, event),
          MigrationTransitionResult.invalid,
        );
      }
      expect(
        MigrationStateMachine.nextState(
          MigrationState.migrationFailed,
          MigrationEvent.rollbackConfirmed,
        ),
        MigrationState.legacy,
      );
    });

    test('no se regresa de AUTHORIZED en adelante sin pasar por '
        'MIGRATION_FAILED → rollback (protege de rollback abusivo)', () {
      expect(
        MigrationStateMachine.evaluate(
          MigrationState.authorized,
          MigrationEvent.rollbackConfirmed,
        ),
        MigrationTransitionResult.invalid,
      );
      expect(
        MigrationStateMachine.evaluate(
          MigrationState.migrated,
          MigrationEvent.rollbackConfirmed,
        ),
        MigrationTransitionResult.invalid,
      );
      expect(
        MigrationStateMachine.evaluate(
          MigrationState.verified,
          MigrationEvent.rollbackConfirmed,
        ),
        MigrationTransitionResult.invalid,
      );
    });

    test('FINALIZED no acepta ni siquiera rollbackConfirmed', () {
      expect(
        MigrationStateMachine.evaluate(
          MigrationState.finalized,
          MigrationEvent.rollbackConfirmed,
        ),
        MigrationTransitionResult.invalid,
      );
    });

    test('fromStatusId fail-closed ante estado desconocido', () {
      expect(
        () => MigrationState.fromStatusId('zombie'),
        throwsA(isA<MigrationRecordCorruptError>()),
      );
    });
  });
}