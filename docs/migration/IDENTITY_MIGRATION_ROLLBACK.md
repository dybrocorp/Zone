# IDENTITY MIGRATION ROLLBACK

> FASE 2.1.1 — Integration Readiness & Migration Bridge Design.
> READ-ONLY. Estrategia de fallo y rollback seguro. Nunca destruir información válida.

## 1. Principio

**Rollback seguro = el sistema puede volver a `LEGACY` íntegro en cualquier punto anterior a
`FINALIZED`, porque los datos legacy nunca se destruyen antes de la verificación final.**

Orden de destrucción en la migración (de lo más fácilmente recreable a lo único):
1. (primero) metadatos nuevos en `zone_identity` → borrables;
2. (luego) seeds `zid1.*` → borrables del almacén seguro;
3. (último, solo FINALIZED) claves legacy `private_key`/`public_key`/`zone_id`/`supabase_uid`/
   `sk_*`/`pseudo_*` → archivables antes de eliminar.

## 2. Análisis de fallos

| Escenario | Dónde puede ocurrir | Comportamiento deseado |
| --- | --- | --- |
| Crash durante DISCOVERED/VALIDATED | sin writes nuevos | idempotente: re-discover (las lecturas son no destructivas) |
| Crash durante BRIDGED | escritura parcial en `zone_identity` | reinicio desde DISCOVERED; `putBy*` con índice replace (idempotente); la falta de marca ⇒ estado `BRIDGED-incompleto`; se revalida coherencia seed↔metadata |
| App kill / process termination | cualquier punto | igual que crash: la máquina es persistente (estado + marca en `zone_identity`), reanuda o revierte |
| Corrupción de BD | Isar `zone_identity` o legacy | fallo cerrado (`IdentityPersistenceError`); **no** regenerar identidad; `MIGRATION_FAILED → LEGACY` |
| Identidad inválida | validación de bridge | aborto en VALIDATED, sin escribir nada nuevo |
| Identidad duplicada | `DuplicateIdentityRecordError` | aborto; inspección manual (nunca auto-resolver borrando) |
| Identidad ausente | sin `AccountIdentityDbo` | primer arranque = creación limpia (autorizado), o `LEGACY` si hay restos |
| Persistencia parcial | mezcla legacy+nueva | detectada por marca de estado; rollback a LEGACY deja artifacts nuevos en `zone_identity` que se marcan `rollebacked` y se reconcilian |
| Fallo de red | RPCs/claims | no bloquea la migración local; el single-writer switch espera conectividad; los claims se reintentan idempotentemente |
| Fallo de autorización | confirm_bootstrap (código I-030) | device_1 queda `pending`/`locked`; la cuenta queda `BRIDGED`; reintento con cool-down (MAX_ATTEMPTS, `device_lifecycle.dart:95-96,139-140`) |
| Rollback abusivo | intento de volver tras FINALIZED | prohibido: maquina terminal (`IDENTITY_MIGRATION_STATE_MACHINE.md` §5) |

## 3. Precondiciones del rollback total (LEGACY restaurado)

1. No se han borrado keys legacy (si se borraron ⇒ **sin rollback**, migración irrevocable).
2. La fecha/hora y cause del rollback quedan registradas (observabilidad, sin secretos).
3. La marca de migración se revierte a `legacy` y los artefacts de `zone_identity` se
   archivan (no se eliminan silenciosamente — permite forense posterior).

## 4. Estrategia: backup y snapshot

- Antes del primer write del bridge: **snapshot** (checksums de: valores legacy en secure
  storage; fila `users` remota `id, zone_id, public_key, updated_at`; perfiles Isar con
  userId/zoneId). Sin copiar secretos fuera del almacén seguro (solo checksums, p.ej.
  `sha256(private_key)`).
- Los checksums permiten: (a) detectar mutación externa durante la ventana; (b) validar que
  el rollback restaura exactamente el estado previo.
- No se guarda la clave privada en ningún log/backup plano (I-004; `identity_errors.dart:5-8`).

## 5. Matriz rollback por estado de la máquina

| Estado | Rollback posible | Qué se revierte | Qué queda |
| --- | --- | --- | --- |
| LEGACY / DISCOVERED / VALIDATED | Total, trivially (sin writes) | nada | sin cambios |
| BRIDGED | Total | borrar account/device de `zone_identity` + seeds `zid1.*` (desechable) | legacy intacto |
| AUTHORIZED | Total | demote device_1 (no se puede desactivar por máquina I-030 desde active⇒? — transición prohibida) ⇒ por eso el rollback desde AUTHORIZED **requiere** emitir `MIGRATION_FAILED` ANTES de activar; si ya activo, se revoca por `revoke_device` firmado | legacy intacto, traza de revocación |
| MIGRATED | Parcial | volver escritores a legacy (flag single-writer off) | ambas stores consistentes (`zone_identity` + legacy) |
| VERIFIED | No recomendado (E2EE ya validado); técnicamente reversible si legacy intacto | — | se prefiere continuar a FINALIZED |
| FINALIZED | **No** | — | terminal |

## 6. NUNCA hacer en rollback

- NO borrar claves legacy antes de FINALIZED.
- NO regenerar identidad para "salir del paso" (prohibido por `InconsistentIdentityStateError`,
  `identity_registry.dart:160-164`).
- NO reasignar `account_id` a otro `zone_id` (rompería la biyección 1:1).
- NO loggear secretos/envelopes/tokens.

## 7. Condiciones de bloqueo de rollback (impiden el rollback → migración irrevocable)

- Las seeds `zid1.*` se perdieron (no se puede volver a la identidad legada).
- Los datos legacy fueron borrados por la app o el usuario (p.ej. `deleteAccount` cumplido,
  `zone_id_service.dart:571-615`).
- La fila `users` remota fue reclamada por otro UID (`claim_zone_id`, `supabase_schema.sql:673`)
  durante la ventana → estado indeliberado documentado como `UNKNOWN` antes de decidir.

## 8. Observabilidad del rollback (sin secretos)

Equivalente a la del bridge (`IDENTITY_MIGRATION_BRIDGE.md` §9): eventos
`migration_state`, `rollback_cause` (enum tipado), `rollback_at`, checksums previos — jamás
material privado. Cumple I-004 y el mandato §18 de la FASE 2.1.