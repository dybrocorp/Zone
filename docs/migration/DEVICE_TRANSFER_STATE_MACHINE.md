# DEVICE TRANSFER STATE MACHINE — Máquina de transferencia entre dispositivos (Z-213 PHASE F/G, §3)

**Estado:** DISEÑADO + IMPLEMENTADO (unidades PROBADAS LOCALMENTE 14/14 +
**421/421 PASS** suite completa, 2026-10-27).
**Back-end de revocación: NO VALIDADO** (staging BLOCKED — autorización del
propietario pendiente, Z-213 §0 sin firma). Nada de esto modifica producción
remota.

Código: `lib/migration/device_transfer_state_machine.dart` ·
Pruebas: `test/migration/device_transfer_state_machine_test.dart`.

## 1. Alcance y separación (datos vs. secretos)

Complementa a `device_migration_state.dart` (que mapea 1:1 el flip
`A/B/C/D` server-side de `z213_account_device_identity.sql`) con las fases
LOCALES de una transferencia real de datos A(viejo)→B(nuevo):

- **Qué viaja**: DATA de aplicación (perfiles, encuentros, chats locales)
  fragmentada, con manifest SHA-256 y chunks MAC-ados, por canal AKE
  autenticado (`ZONE-P2P-AKE-1`, ver `docs/audit/PHASE_E_P2P_AUTH_DESIGN.md`
  §7.8.4) o vía server (cuando staging exista).
- **Qué NUNCA viaja**: claves privadas. Ni las seeds del device viejo, ni
  las del nuevo. La autenticidad/logro de binding se exige con
  `device_certificate_v2` (firmado por la cuenta) y el handshake AKE
  (`prior` de transcript). El device nuevo genera su PROPIA identidad
  (fundación Z-213); la transferencia NO copia identidad — la reclama.

## 2. Estados

```text
idle → requested → awaiting_proof → authorized → transferring → verifying
        → completed → revocation_pending → idle (revocación confirmada)

failed_recoverable ⇄ transferring/verifying   (resume seguro, chunks intactos)
cancelled          (explícito/timeout; NUNCA desde completed)
```

Estos 10 estados (`DeviceTransferState`) son el mapa pedido; `idle` es el
estado base FILE persistible de "sin transferencia activa".

## 3. Invariantes invariológicas (verificadas por los tests)

1. **Revocación del device viejo SOLO desde `completed`** — nunca desde
   `transferring`/`verifying`/`failed_recoverable`/estados previos.
2. **Revocación fallida ⇒ vuelve a `completed`** con
   `revocationAttempts+1` y `lastRevocationReason` en audit trail
   (recoverable, device nuevo ya opera; reintento permitido).
3. **Fallo (`failed_recoverable`) NUNCA deja comprometido el device
   viejo** — no existe camino del fallo a revocación, y una interrupción
   temprana (requested/awaiting_proof) también termina en
   `failed_recoverable` sin secreto transferido.
4. **Chunks idempotentes** (`Set<int>`): reenvío no duplica; sin spam de
   audit; `TransferCompleted` exige `completedChunks.length ==
   totalChunks` (restauración incompleta ⇒ error tipado, SIEMPRE).
5. **Tope de pruebas**: ≤3 `ProofRejected` (`kMaxProofAttempts`); el 4º
   rechazo lanza `InvalidMigrationStateTransitionError`. Con el tope
   alcanzado pasa a `failed_recoverable` (device viejo intacto) — el dueño
   REAL con prueba criptográfica válida aún se recupera (la barrera es la
   prueba, no el estado).
6. **Binding inequívoco de cuenta**: `ProofVerified` con accountId
   distinto del snapshot ⇒ `InvalidMigrationStateTransitionError`
   (escenario "dispositivo no autorizado").
7. **Concurrencia**: `RequestMigration` sobre un estado activo ⇒ error
   tipado (UN plan activo por snapshot; disponibilidad de nuevo arranque
   tras `cancel`).
8. **Serializable**: `toJson/fromJson` round-trip completo (id/estados/
   chunks/audit); JSON corrupto o con estado desconocido ⇒
   `MigrationRecordCorruptError` — sin inventar estados RESTORE.

## 4. Escenarios cubiertos (1:1 con el master prompt)

| # | Escenario | Resultado verificado |
|---|---|---|
| 1 | Transferencia interrumpida | `failed_recoverable` con chunks preservados; sin camino a revocación |
| 2 | Reintento con reintegro | `ResumeRequested` ⇒ transferring con chunks; si manifest completo ⇒ verifying |
| 3 | Solicitud concurrente | error tipado; snapshot sin mutar |
| 4 | Dispositivo no autorizado | `ProofVerified` de otra cuenta ⇒ error; snapshot sin cambios |
| 5 | Prueba incorrecta triple | 3 rechazos ⇒ `failed_recoverable`; 4º ⇒ error; owner con prueba válida recupera |
| 6 | Datos corruptos | `VerificationFailed` ⇒ `failed_recoverable`; device JAMÁS revocado |
| 7 | Device viejo offline | interrupción temprana ⇒ `failed_recoverable`; cancel posible; nuevo arranque mis servidor snapshot |
| 8 | Restauración incompleta | `TransferCompleted` con chunks faltantes ⇒ error SIEMPRE |
| 9 | Revocación fallida | vuelve a `completed`, contador+motivo; reintento termina en `idle` |
| 10 | Reanudar tras reinicio | JSON round-trip con id/estado/chunks; resume continúa exacto |

+ flujo feliz completo `idle → … → completed → revocation_pending → idle`
  y guardas adicionales (cancel post-completed; transiciones inválidas en
  `revocation_pending`).

## 5. Integración pendiente (explícita, NO hecha)

1. **Host/driver**: un servicio que emita los eventos (radio AKE o REST
   server) — la máquina es pura y no conoce I/O por diseño (validada con
   `transition/accepts`).
2. **Persistencia real**: `toJson` ya definido; el almacenamiento local
   (Isar/SecureStorage) del snapshot queda ligada a un siguiente slice.
3. **Backend de revocación**: `revocation_pending → idle` exige acuse del
   servidor (Z-213 flip `revoke` + RLS); STAGING BLOCKED.
4. **UI**: pantallas A→B (QR/confirmación/fingerprint OOB) — NOT RUN.

## 6. Evidencia

- `flutter test test/migration/device_transfer_state_machine_test.dart`
  ⇒ 14/14 PASS (10 escenarios + happy path + guardas).
- `flutter test --no-pub` ⇒ 421/421 PASS (2026-10-27).
- `flutter analyze --no-pub` ⇒ No issues found.

---

*Generado por la sesión DYBROCORP/OpenCode del 2026-10-27; sin
cambios remotos (Supabase staging: NONE aplicado).*
