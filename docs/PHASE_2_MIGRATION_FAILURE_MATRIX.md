# PHASE 2.0.2 — Migration Failure Matrix (MIGRATION_FAILURE_MATRIX_V1)

> **Tipo:** Matriz formal de escenarios de fallo de migración — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** RESOLVED — CTO PROPOSED (pendiente firma humana)
> **Resuelve:** R-015 (C4) · OPEN-012
> **Afecta:** `PHASE_2_MIGRATION_PLAN.md` §4/§6 (se integrará como sección "Seguridad de migración")
> **Invariantes:** I-010, I-019 (revisados) · I-028 (relacionado)

---

## 1. Principios operativos de la migración

1. **Versión por fila:** el footer de versión en `encrypted_content` y los campos de estado
   de identidad (`mode`, `identity_key_version`, `key_version`) son la *source of truth*;
   ninguna herramienta infiere versión de heurísticas.
2. **Idempotencia:** toda DDL usa `IF NOT EXISTS`; toda fase es re-ejecutable sin efecto
   lateral (I-019).
3. **Transaccionalidad por fase:** tabla/DDL en una transacción; fallo ⇒ estado previo.
4. **Rollback por feature flag:** cada fase se activa con flag; revertir el flag no destruye
   datos (las columnas extras quedan, sin usarse).
5. **Requisito de versión de cliente:** el servidor declara `min_app_version` por fase y
   rechaza operaciones de identidad de clientes antiguos con error claro (no silencioso).
6. **Nunca lockout sin ruta:** LEGACY_ACCESS_POLICY REGL-1 (sección I-028).

## 2. Matriz de escenarios

Columnas: **SCENARIO · PRECONDITION · STATE BEFORE · OPERATION · FAILURE POINT ·
STATE AFTER · DETECTION · RECOVERY · ROLLBACK · DATA LOSS · LOCKOUT RISK ·
SECURITY IMPACT · AUDIT EVENT**.

| # | Escenario | Precondición | Estado antes | Operación | Punto de fallo | Estado después | Detección | Recuperación | Rollback | Pérdida de datos | Riesgo lockout | Impacto seguridad | Audit event |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **Cierre a mitad** | App cerrada durante `bootstrap_account`/`confirm_bootstrap` | `account_identity` sin crear o `bootstrap_attempt` emitido | Flujo bootstrap M1 | Entre request_challenge y confirm | `bootstrap_attempt` pendiente o confirm no enviado | Audit `bootstrap_code_issued` sin `confirm_success` + TTL | Reintento: solicitar nuevo código (invalida anterior) y confirmar | Cancelar intento (`bootstrap_cancel`); nada se crea definitivamente | Ninguna (aún no se crean datos) | Bajo | Ninguno (PENDING sin derechos) | `bootstrap_cancelled`/`bootstrap_code_expired` |
| 2 | **Pérdida de red** | Red caída durante fase M2 (envío de mensaje con footer v3) | Mensaje en outbox | Encriptación v3 + envío | Antes de persistir/entregar | Outbox retiene ciphertext v3; peers legados lo rechazan si no soportan v3 | Error de envío + retry | Reintento; downgrade explícito a v1 si el par no soporta v3 (MIGRATION M2) | El retry re-empaqueta o degrada | Ninguna (outbox conserva la cola) | Bajo | Linaje: nunca enviar v3 a par solo-v1 | `msg_send_retry` / `msg_downgrade_v3_to_v1` |
| 3 | **Supabase no disponible** | Fase M1 DDL de nuevas tablas | `users` intacto (v1) | `CREATE TABLE IF NOT EXISTS` + RPCs | Transacción de creación de tablas | DDL atómica: o todas las tablas existen o ninguna | Error 5xx + retry backoff | Reintento de la fase M1 (idempotente) | Flag M1 off; tablas vacías sin uso | Ninguna | Bajo | Ninguno (nada se expone antes de RLS) | `m1_ddl_retry` |
| 4 | **Ejecución duplicada** | Bug de scheduler ejecuta M1 dos veces | Tablas M1 ya creadas | `CREATE TABLE IF NOT EXISTS` / backfill | No falla por idempotencia | Estado idéntico (IF NOT EXISTS) | Flag `migrations` + checksum de versión | Verificar checksum; sin acción | N/A | Ninguna | Bajo | Ninguno | `m1_rereun_noop` |
| 5 | **Dos dispositivos simultáneos** | A1 y A2 migrate/n el mismo account a la vez | `account_identity` UNIQUE(zone_id) | bootstrap/register concurrente | Contraseña `UNIQUE(zone_id)` o challenge single-use | Solo uno gana el enroll/la rotación; el otro recibe 409 | Constraint + challenge `used_at` | El perdedor reintenta con nuevo challenge (BOOTSTRAP_POLICY I-027) | Cancelar intento perdedor | Ninguna | Bajo | Ninguno (single-use + UNIQUE) | `bootstrap_concurrent_denied` |
| 6 | **App eliminada durante migración** | Usuario borra la app entre M1 inicio y confirm | `bootstrap_attempt` emitido | (interrupción) | — | `bootstrap_attempt` expira (TTL) | Inducción audit TTL | Reinstalar → retomar (claim acotado o recovery si ya existe) | Cancelar intento | Ninguna | Bajo (política legacy) | Ninguno (PENDING sin derechos) | `bootstrap_code_expired` |
| 7 | **Reinstalación durante migración** | Persiste `mode=legacy` + attempt pendiente | Cuenta sin devices | bootstrap + reinstall | — | El nuevo install reanuda vía claim acotado + bootstrap (OPEN-011) | Audit `legacy_claim_accepted` | LEGACY_ACCESS_POLICY §3 | N/A | Ninguna | **Sin lockout** (ruta documentada) | Ninguno (claim acotado auditado) | `legacy_claim_accepted` |
| 8 | **Rollback parcial** | Flag de M1 apagado tras crear tablas | Tablas M1 creadas; cuentas upgraded | (rollback manual) | — | Tablas presentes sin uso; cuenta en `transition` mantiene mode | Comparación flag vs tablas | Re-aplicar M1 o limpiar tablas vacías (nunca borrar datos de cuentas) | Desactivar flag; tablas pueden quedar inertes | Ninguna | Bajo | Ninguno (RLS solo-RPC ya aplicada) | `m1_flag_disabled` |
| 9 | **Migration marker incorrecto** | Checksum de versión corrupto | Footer v3 escrito como v1 (o viceversa) | Lectura de versión | En descifrado | Mensaje marcado con versión errónea | Test de compat v1↔v3 / mensaje ilegible | Registrar `marker_error`; si v1→v3 erróneo, intentar ambas derivaciones (fallback local) | N/A | Ninguna | Bajo (un mensaje), medio si persistente | Header/versión autenticado en M4 (ratchet); para v3 el footer es parte del ciphertext (no se puede escalar por terceros sin claves) | `marker_error_unknown_version` |
| 10 | **Cliente antiguo vs servidor nuevo** | App pre-M1 contra servidor pos-M1 | RPCs M1 nuevas | Cliente viejo llama a `claim_zone_id` | — | El claim acotado responde OK solo para legacy sin devices; para upgraded devuelve error claro | `legacy_claim_denied_secure` / min_version | Upgrade de app requerido (mensaje) | Flag claim legacy on | Ninguna | Bajo | El claim queda acotado (no puerta trasera) — mejora | `legacy_claim_denied_secure` |
| 11 | **Cliente nuevo vs servidor parcialmente migrado** | App M1 contra servidor sin M1 | Fase M1 no desplegada | Cliente llama a RPC `bootstrap_account` | RPC inexistente | 404/423 con mensaje "versión de servidor insuficiente" | Error RPC | Reintento tras deploy / no invocar RPC de identidad hasta detectar feature | Flag cliente detecta capability | Ninguna | Bajo | Ninguno (fail-closed: no degrada a claim para cuentas sin devices) | `m1_server_not_ready` |
| 12 | **Migración ejecutada pero cliente no confirmado** | `bootstrap_account` OK, `confirm_bootstrap` nunca llega | device_1 PENDING | confirm | Timeout/cierre | device_1 permanece PENDING (sin derechos); reintento posible (BOOTSTRAP_POLICY §2/§4) | Audit timeout | Solicitar nuevo código y confirmar; o `bootstrap_cancel` | Ninguna | Bajo (política legacy) | Ninguno (PENDING sin derechos — I-013) | `bootstrap_code_expired` / `bootstrap_confirm_fail_lock` |

## 3. Reglas de oro derivadas

1. **Sin lockout no documentado:** todo escenario que deja una cuenta "atascada" tiene una
   vía de reentrada (recuperación/claim acotado/cancel) — I-028.
2. **Nunca se borra contenido de mensajes** para "deshacer" una migración (I-010/I-019).
3. **Ninguna ruta legacy permite plaintext de mensajes** (I-005): los fallos de migración
   degradan a v1 **con wrap E2EE** (ciphertext sigue cifrado) o a v3, nunca a claro.
4. Reinstalaciones, cierres, red y retry son cubiertos por idempotencia + flags + audit.

## 4. Integración

La sección "Seguridad de migración" de `PHASE_2_MIGRATION_PLAN.md` adoptará esta matriz como
contrato de FASE 2.0.2 (OPEN-012) — solo documentación.