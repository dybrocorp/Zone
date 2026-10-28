/// Z-213 PHASE F/G — Tests de la máquina de estados de TRANSFERENCIA entre
/// dispositivos (`lib/migration/device_transfer_state_machine.dart`).
///
/// Los 10 escenarios exigidos por el master prompt DYBROCORP (FASE F §3),
/// más el flujo feliz completo (caminar `idle → … → idle` con revocación
/// confirmada). Máquina PURA: no hay I/O ni dobles — cada transición es un
/// snapshot nuevo inmutable.
///
/// Contrato verificado (invariantes 1–8 del encabezado del módulo):
/// - revocación del device viejo SOLO post-`completed` (invariante 1);
/// - revocación fallida ⇒ vuelve a `completed` con intento+motivo
///   auditable (invariante 2);
/// - fallo NO contamina el device viejo (invariante 3);
/// - chunks idempotentes, manifest completo exigido (invariante 4);
/// - serialización JSON round-trip con el MISMO id (invariante 8).
///
/// Label: LOCALLY TESTED (fuera de radio/backend; nothing remote).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zone/identity/identity_errors.dart';
import 'package:zone/migration/device_transfer_state_machine.dart';

const String _account = '11111111-1111-4111-8111-111111111111';
const String _oldFp = 'ZFP2:OLD-DEVICE-FINGERPRINT';
const String _oldDeviceId = '33333333-3333-4333-8333-333333333333';

DeviceTransferStateMachine _fresh({String plan = 'replace_device'}) =>
    DeviceTransferStateMachine(
      DeviceTransferSnapshot.initial(
        accountId: _account,
        deviceFingerprint: _oldFp,
        plan: plan,
      ),
    );

/// Avanza el flujo de solicitud/prueba hasta `authorized`.
DeviceTransferStateMachine _toAuthorized(DeviceTransferStateMachine m) {
  var cur = m
      .transition(const RequestMigration(_account, _oldFp, 'replace_device'))
      .transition(const ProofChallengeIssued())
      .transition(const ProofVerified(_account, 'proof-hash-b64'));
  expect(cur.snapshot.state, DeviceTransferState.authorized);
  return cur;
}

/// Avanza hasta `transferring` con `totalChunks` chunk declarados.
DeviceTransferStateMachine _toTransferring(
  DeviceTransferStateMachine m,
  int totalChunks,
) {
  final cur = _toAuthorized(m)
      .transition(TransferStarted(totalChunks: totalChunks));
  expect(cur.snapshot.state, DeviceTransferState.transferring);
  return cur;
}

/// Completa todos los chunks y entra a `verifying` (éxito de verificación).
DeviceTransferStateMachine _toVerifyingComplete(
  DeviceTransferStateMachine m,
  int totalChunks,
) {
  var cur = _toTransferring(m, totalChunks);
  for (var i = 0; i < totalChunks; i++) {
    cur = cur.transition(ChunkStored(i));
  }
  final verifying = cur.transition(const TransferCompleted());
  expect(verifying.snapshot.state, DeviceTransferState.verifying);
  expect(verifying.snapshot.completedChunks.length, totalChunks);
  return verifying;
}

void main() {
  group('flujo feliz completo (datos por canal AKE, SIN claves privadas)', () {
    test('idle → … → completed → revocationPending → idle', () {
      var m = _fresh();
      m = _toVerifyingComplete(m, 4);
      final completed = m.transition(const VerificationSucceeded());
      expect(completed.snapshot.state, DeviceTransferState.completed);

      // RestoreConfirmed es idempotente (no cambia estado).
      final restored = completed.transition(const RestoreConfirmed());
      expect(restored.snapshot.state, DeviceTransferState.completed);

      // Invariante 1: revocación SOLO post-completed — aquí SÍ.
      expect(restored.accepts(RevocationRequested(_oldDeviceId)), isTrue);
      final pending = restored.transition(RevocationRequested(_oldDeviceId));
      expect(pending.snapshot.state, DeviceTransferState.revocationPending);

      final done = pending.transition(const RevocationSucceeded());
      expect(done.snapshot.state, DeviceTransferState.idle);
      expect(done.snapshot.isActive, isFalse);
      // Auditoría: la etiqueta de revocación está en el trail.
      expect(
        done.snapshot.auditTrail.any((e) => e['note']!.contains('revocationSucceeded')),
        isTrue,
      );
    });

    test('chunks idempotentes: reenvío de un índice no duplica ni avanza', () {
      var m = _toTransferring(_fresh(), 4);
      m = m.transition(const ChunkStored(1));
      final before = m.snapshot.completedChunks.length;
      final again = m.transition(const ChunkStored(1));
      expect(again.snapshot.completedChunks.length, before);
      expect(again.snapshot.updatedAt, m.snapshot.updatedAt); // sin spam
      // Chunk fuera de rango ⇒ error tipado (fail-closed).
      expect(
        () => m.transition(const ChunkStored(7)),
        throwsA(isA<InvalidMigrationStateTransitionError>()),
      );
    });
  });

  // ────────────────────────── 10 escenarios exigidos ──────────────────────

  group('ESCENARIO 1 — transferencia interrumpida a mitad', () {
    test('TransferInterrupted en transferring ⇒ failed_recoverable con '
        'chunks preservados y device viejo intacto', () {
      final m = _toTransferring(_fresh(), 4);
      final partial = m.transition(const ChunkStored(0)).transition(
        const ChunkStored(1),
      );
      expect(partial.snapshot.nextMissingChunk(), 2);

      final interrupted = partial.transition(
        const TransferInterrupted('radio_lost mid-transfer'),
      );
      expect(interrupted.snapshot.state, DeviceTransferState.failedRecoverable);
      expect(interrupted.snapshot.completedChunks.length, 2);
      expect(interrupted.snapshot.totalChunks, 4);
      // Invariante 3: no hay camino a revocación desde el fallo.
      expect(
        interrupted.accepts(RevocationRequested(_oldDeviceId)),
        isFalse,
        reason: 'revocación desde fallo prohibida (invariante 1)',
      );
    });
  });

  group('ESCENARIO 2 — reintento segura (resume)', () {
    test('resume desde failed_recoverable ⇒ transferring conservando chunks',
        () {
      final m = _toTransferring(_fresh(), 3);
      final interrupted = m
          .transition(const ChunkStored(0))
          .transition(const TransferInterrupted('ble disconnect'));
      final resumed = interrupted.transition(const ResumeRequested());
      expect(resumed.snapshot.state, DeviceTransferState.transferring);
      expect(resumed.snapshot.completedChunks, {0});
      // Y el flujo sigue normal hasta completed:
      final done = resumed
          .transition(const ChunkStored(1))
          .transition(const ChunkStored(2))
          .transition(const TransferCompleted())
          .transition(const VerificationSucceeded());
      expect(done.snapshot.state, DeviceTransferState.completed);
    });

    test('resume con manifest YA completo ⇒ directo a verifying', () {
      final m = _toVerifyingComplete(_fresh(), 2)
          .transition(const VerificationFailed('checksum mismatch'));
      final resumed = m.transition(const ResumeRequested());
      expect(resumed.snapshot.state, DeviceTransferState.verifying);
    });
  });

  group('ESCENARIO 3 — solicitud concurrente', () {
    test('RequestMigration sobre estado activo ⇒ error tipado (no silencio)',
        () {
      final m = _toAuthorized(_fresh());
      expect(
        () => m.transition(
          const RequestMigration(_account, _oldFp, 'recover_account'),
        ),
        throwsA(
          isA<InvalidMigrationStateTransitionError>().having(
            (e) => e.toString(),
            'message',
            contains('requestMigration'),
          ),
        ),
      );
      // El snapshot NO cambió (el flujo autorizado sigue vivo).
      expect(m.snapshot.state, DeviceTransferState.authorized);
    });
  });

  group('ESCENARIO 4 — dispositivo no autorizado (binding de cuenta)', () {
    test('ProofVerified de OTRA cuenta ⇒ error; snapshot sin cambios', () {
      final m = _fresh()
          .transition(const RequestMigration(_account, _oldFp, 'replace_device'))
          .transition(const ProofChallengeIssued());
      const strangerAccount = '22222222-2222-4222-8222-222222222222';
      expect(
        () => m.transition(const ProofVerified(strangerAccount, 'evil-proof')),
        throwsA(isA<InvalidMigrationStateTransitionError>()),
      );
      expect(m.snapshot.state, DeviceTransferState.awaitingProof);
    });
  });

  group('ESCENARIO 5 — prueba incorrecta repetida', () {
    test('3 rechazos ⇒ failed_recoverable; el 4º rechazo ⇒ error', () {
      final m = _fresh()
          .transition(const RequestMigration(_account, _oldFp, 'add_device'))
          .transition(const ProofChallengeIssued());

      var cur = m;
      for (var i = 1; i <= 3; i++) {
        cur = cur.transition(ProofRejected('cert invalid #$i'));
        if (i < 3) {
          expect(cur.snapshot.state, DeviceTransferState.awaitingProof);
        }
      }
      // Al reaching el tope (3): fail-closed, device viejo INTACTO.
      expect(cur.snapshot.state, DeviceTransferState.failedRecoverable);
      expect(cur.snapshot.proofAttempts, 3);
      expect(cur.accepts(RevocationRequested(_oldDeviceId)), isFalse);

      // POST-tope: ningún rechazo adicional muta el estado.
      expect(
        () => cur.transition(const ProofRejected('more evil')),
        throwsA(isA<InvalidMigrationStateTransitionError>()),
      );
      // El dueño REAL con prueba VÁLIDA aún se recupera (la barrera es la
      // prueba criptográfica, no el estado).
      final ownerRecovers = cur
          .transition(const ProofVerified(_account, 'good-proof-late'))
          .transition(TransferStarted(totalChunks: 1))
          .transition(const ChunkStored(0))
          .transition(const TransferCompleted())
          .transition(const VerificationSucceeded());
      expect(ownerRecovers.snapshot.state, DeviceTransferState.completed);
    });
  });

  group('ESCENARIO 6 — datos corruptos en verificación', () {
    test('VerificationFailed ⇒ failed_recoverable; device NUNCA revocado',
        () {
      final m = _toVerifyingComplete(_fresh(), 3).transition(
        const VerificationFailed('chunk 2 checksum mismatch (corrupt)'),
      );
      expect(m.snapshot.state, DeviceTransferState.failedRecoverable);
      expect(m.snapshot.completedChunks.length, 3);
      expect(
        m.accepts(RevocationRequested(_oldDeviceId)),
        isFalse,
        reason: 'device viejo NUNCA se revoca desde un fallo (invariante 1)',
      );
      // Reanudar: checking de nuevo (manifest completo) ⇒ verifying.
      final recheck = m.transition(const ResumeRequested());
      expect(recheck.snapshot.state, DeviceTransferState.verifying);
    });
  });

  group('ESCENARIO 7 — device viejo offline durante la negociación', () {
    test('interrupción temprana ⇒ failed_recoverable sin dejar el state '
        'antiguo comprometido', () {
      final m = _fresh()
          .transition(const RequestMigration(_account, _oldFp, 'replace_device'));
      final stale = m.transition(
        const TransferInterrupted('old device went offline at requested'),
      );
      expect(stale.snapshot.state, DeviceTransferState.failedRecoverable);
      expect(stale.snapshot.proofAttempts, 0);
      // Sin autorización NO existe camino a revocación (invariante 1+3).
      expect(stale.accepts(RevocationRequested(_oldDeviceId)), isFalse);
      expect(stale.accepts(TransferStarted(totalChunks: 1)), isFalse);
      // El usuario puede cancelar y empezar de cero más tarde.
      final cancelled = stale.transition(const CancelRequested('give up now'));
      expect(cancelled.snapshot.state, DeviceTransferState.cancelled);
      // Cancelado NO es activo: un request nuevo arranca un transferir nuevo.
      expect(
        cancelled.snapshot.isActive,
        isFalse,
        reason: 'cancelado libera el snapshot para una solicitud nueva',
      );
      final freshRun = cancelled
          .transition(const RequestMigration(_account, _oldFp, 'replace_device'));
      expect(freshRun.snapshot.state, DeviceTransferState.requested);
      expect(freshRun.snapshot.id, cancelled.snapshot.id,
          reason: 'el mismo snapshot puede arrancar un nuevo plan');
    });
  });

  group('ESCENARIO 8 — restauración incompleta', () {
    test('TransferCompleted con chunks faltantes ⇒ error SIEMPRE', () {
      final m = _toTransferring(_fresh(), 5);
      final partial = m.transition(const ChunkStored(3));
      expect(partial.snapshot.completedChunks.length, 1);
      expect(
        () => partial.transition(const TransferCompleted()),
        throwsA(
          isA<InvalidMigrationStateTransitionError>().having(
            (e) => e.toString(),
            'message',
            contains('incompleta'),
          ),
        ),
      );
      // Y tras Recuperarse (completar los chunks) el flow continúa:
      var fixed = partial;
      for (var i = 0; i < 5; i++) {
        fixed = fixed.transition(ChunkStored(i));
      }
      final ok = fixed.transition(const TransferCompleted());
      expect(ok.snapshot.state, DeviceTransferState.verifying);
    });
  });

  group('ESCENARIO 9 — revocación fallida (recuperable y auditable)', () {
    test('RevocationFailed ⇒ vuelve a completed con contador+motivo; el '
        'intento posterior SÍ termina', () {
      final m = _toVerifyingComplete(_fresh(), 2)
          .transition(const VerificationSucceeded())
          .transition(RevocationRequested(_oldDeviceId));

      final failed = m.transition(
        const RevocationFailed('backend staging unavailable (BLOCKED)'),
      );
      // INVIOLABLE (invariante 2): regresa a completed, NO queda colgado.
      expect(failed.snapshot.state, DeviceTransferState.completed);
      expect(failed.snapshot.revocationAttempts, 1);
      expect(failed.snapshot.lastRevocationReason, contains('BLOCKED'));
      expect(failed.snapshot.auditTrail.any((e) => e['note']!.contains('revocationFailed')), isTrue);

      // Reintento autorizado: completed → pending → success → idle.
      final retried = failed
          .transition(RevocationRequested(_oldDeviceId))
          .transition(const RevocationFailed('still offline'))
          .transition(RevocationRequested(_oldDeviceId))
          .transition(const RevocationSucceeded());
      expect(retried.snapshot.state, DeviceTransferState.idle);
      expect(retried.snapshot.revocationAttempts, 2);
    });
  });

  group('ESCENARIO 10 — reanudar tras reinicio (JSON round-trip)', () {
    test('toJson/fromJson conserva id/estado/chunks; resume sigue el flujo',
        () {
      final m = _toTransferring(_fresh(), 6)
          .transition(const ChunkStored(0))
          .transition(const ChunkStored(5))
          .transition(const TransferInterrupted('app killed / device reboot'));

      // "Reinicio": persistir y recargar.
      final restored = DeviceTransferSnapshot.fromJson(m.snapshot.toJson());
      expect(restored.id, m.snapshot.id);
      expect(restored.state, DeviceTransferState.failedRecoverable);
      expect(restored.completedChunks, {0, 5});
      expect(restored.totalChunks, 6);
      expect(restored.plan, 'replace_device');
      expect(restored.deviceFingerprint, _oldFp);
      expect(restored.proofAttempts, 0,
          reason: 'sin ProofRejected en este flujo');

      // Y el flujo continúa EXACTAMENTE donde quedó.
      final continued =
          DeviceTransferStateMachine(restored).transition(const ResumeRequested());
      expect(continued.snapshot.state, DeviceTransferState.transferring);
      expect(continued.snapshot.nextMissingChunk(), 1);

      // JSON corrupto ⇒ error tipado, NUNCA snapshot inventado (fail-closed).
      expect(
        () => DeviceTransferSnapshot.fromJson(<String, Object?>{
          'id': 'x', // sin 'state'
        }),
        throwsA(isA<MigrationRecordCorruptError>()),
      );
      expect(
        () => DeviceTransferSnapshot.fromJson(<String, Object?>{
          'state': 'unknown_state_xyz',
        }),
        throwsA(isA<MigrationRecordCorruptError>()),
      );
    });
  });

  group('guardas adicionales de la máquina', () {
    test('cancel después de completed ⇒ error (invariante 1/2)', () {
      final completed = _toVerifyingComplete(_fresh(), 1)
          .transition(const VerificationSucceeded());
      expect(
        () => completed.transition(CancelRequested('too late')),
        throwsA(isA<InvalidMigrationStateTransitionError>()),
      );
    });

    test('después de revocation_pending regresar a completed directamente '
        'NO existe (solo vía RevocationFailed/success)', () {
      final pending = _toVerifyingComplete(_fresh(), 1)
          .transition(const VerificationSucceeded())
          .transition(RevocationRequested(_oldDeviceId));
      expect(
        pending.accepts(ResumeRequested()),
        isFalse,
        reason: 'resume no aplica en revocation_pending',
      );
      expect(
        pending.accepts(const ChunkStored(0)),
        isFalse,
        reason: 'chunks no aplican en revocation_pending',
      );
    });
  });
}
