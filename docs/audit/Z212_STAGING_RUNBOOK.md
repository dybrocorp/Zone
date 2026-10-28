# Z-212 — Runbook de aplicación en STAGING (sin ejecutar)

**Fecha de preparación:** 2026-10-23
**Migración:** `supabase_migrations/z212_security_hardening.sql`
**Estado:** **PREPARADO LOCALMENTE — NO APLICADO EN REMOTO**
**Alcance:** staging exclusivamente. **Producción queda fuera de este runbook.**

> **LÍMITE DE AUTORIZACIÓN:** este documento no autoriza ninguna conexión remota.
> La ejecución requiere una autorización explícita posterior para el proyecto de
> staging concreto (§0). No se solicitan ni se imprimen credenciales; se usan los
> mecanismos seguros ya configurados.

---

## 0. Puerta de autorización del propietario (obligatoria, 2026-10-27)

**Ninguna conexión, migración o modificación se ejecuta sin la confirmación
expresa del propietario para el proyecto de staging concreto y su ventana de
mantenimiento.** La confirmación es un registro pre-ejecución, no una
generalización; si falta cualquier campo, **se detiene la ejecución**.

### 0.1 Formato de confirmación mínima (el propietario lo redacta y lo firma)

```text
AGENTE DE EJECUCIÓN Z-212 — CONFIRMACIÓN DEL PROPIETARIO
1. Entorno autorizado      : staging — project_ref: __________ (HOST/url NO imprimible)
2. Ventana de mantenimiento: fecha/hora (con zona horaria): __________
3. Alcance autorizado      : ☑ preflight (§3) ☑ backup+restauración (§4)
                             ☑ aplicación z212_security_hardening.sql (§5)
                             ☑ postflight (§5.3) ☑ matriz P-01…P-10 / N-01…N-18 (§6)
                             ☑ re-aplicación de idempotencia (§7)
4. Alcance NO autorizado   : producción / despliegues de app / cambios de datos /
                             otros proyectos
5. Backup                  : ☑ snapshot/branch creado y RESTAURACIÓN PROBADA en base desechable
6. Cliente de staging      : ☑ app desplegada usa RPC (resolve_bt_token/receipts)
                             ☑ SameAccountClaimPolicy.allowSameAccountClaim = false
7. Rol de migración        : (propietario ejecuta o aprueba quién) __________
8. Responsable de negocio  : __________        9. Ejecutor técnico: __________
Firma/registro: __________ (fecha/hora + correo/doc de referencia)
```

### 0.2 Reglas de la puerta

- La confirmación se redacta **por el propietario**, no por quien ejecuta; el
  ejecutor solo la archiva junto con la evidencia saneada.
- Un `project_ref` distinto del confirmado ⇒ **abort inmediato** (verificar con
  `select current_database(), current_user` sin imprimir credenciales, §5.1).
- Ventana vencida o interrumpida ⇒ el bloque siguiente requiere una
  confirmación nueva (no se extiende tácitamente).
- Tras la ejecución el propietario recibe el resumen de criterios §9 y decide
  si se continúa (la firma para producción está **fuera** de este runbook).

---

## 1. Resumen ejecutivo

Z-212 cierra cuatro defectos:

1. `claim_zone_id` sin prueba de posesión → **cuarentena fail-closed**.
2. `messages` con UPDATE directo → **sin policy UPDATE + trigger de inmutabilidad**.
3. `matches` sin `WITH CHECK` → **policy con `WITH CHECK` + trigger de par/estado**.
4. `bt_tokens` con SELECT amplio → **policy eliminada + RPC con sesión y visibilidad**.

La migración **no modifica datos**. Solo reemplaza funciones, elimina/crea policies y crea triggers. Es idempotente y está envuelta en `BEGIN/COMMIT`.

**Riesgo principal:** cambia el contrato de tres RPC/tablas. Clientes antiguos que
lean `bt_tokens` directamente o actualicen `messages` directamente dejarán de
funcionar; el cliente actual ya usa las RPC. El login de usuarios existentes
queda bloqueado por diseño (cuarentena), coherente con
`SameAccountClaimPolicy`.

---

## 2. Inventario de objetos afectados

| Objeto | Tipo | Acción de Z-212 | Lock / impacto |
|--------|------|-----------------|----------------|
| `public.claim_zone_id(text)` | Función `SECURITY DEFINER` | `CREATE OR REPLACE` (cuerpo en cuarentena) + `REVOKE/GRANT` | Lock de función; sin datos |
| `public.enforce_user_protected_columns()` | Función trigger | `CREATE OR REPLACE` (nueva) | Sin datos |
| `trg_users_protected_columns` | Trigger en `public.users` | `DROP IF EXISTS` + `CREATE` | `ACCESS EXCLUSIVE` breve sobre `users` |
| `public.handle_new_report()` | Función trigger `SECURITY DEFINER` | `CREATE OR REPLACE` (marca GUC de moderación) | Sin datos |
| `on_new_report` | Trigger en `public.reports` | `DROP IF EXISTS` + `CREATE` | `ACCESS EXCLUSIVE` breve sobre `reports` |
| `"Resolver token BT"` | Policy SELECT en `public.bt_tokens` | `DROP IF EXISTS` | Lock breve sobre `bt_tokens` |
| `public.resolve_bt_token(text)` | Función `SECURITY DEFINER` | `CREATE OR REPLACE` (sesión + visibilidad) + grants | Lock de función; sin datos |
| `"Aceptar o rechazar match"` | Policy UPDATE en `public.matches` | `DROP IF EXISTS` + `CREATE` con `WITH CHECK` | Lock breve sobre `matches` |
| `public.enforce_match_immutable_participants()` | Función trigger | `CREATE OR REPLACE` (nueva) | Sin datos |
| `trg_matches_immutable_participants` | Trigger en `public.matches` | `DROP IF EXISTS` + `CREATE` | `ACCESS EXCLUSIVE` breve sobre `matches` |
| `"Actualizar mensaje con match aceptado"` | Policy UPDATE en `public.messages` | `DROP IF EXISTS` | Lock breve sobre `messages` |
| `public.enforce_message_immutable_columns()` | Función trigger | `CREATE OR REPLACE` (nueva) | Sin datos |
| `trg_messages_immutable` | Trigger en `public.messages` | `DROP IF EXISTS` + `CREATE` | `ACCESS EXCLUSIVE` breve sobre `messages` |

**No toca:** `auth.users`, `storage.objects`, `encounters`, `blocked_users`, `reports` (salvo el trigger), datos de usuario, claves, ni migraciones de identidad.

---

## 3. Dependencias y precondiciones

### 3.1 Dependencias técnicas

- PostgreSQL de Supabase (15+; validado localmente en 18.4).
- `auth.uid()` disponible y estable.
- Tablas y columnas referenciadas:
  - `users`: `id`, `zone_id`, `display_name`, `avatar_url`, `avatar_is_public`, `stealth_mode`, `public_key`, `instagram_handle`, `ig_visible`, `facebook_handle`, `fb_visible`, `tiktok_handle`, `tiktok_visible`, `reports_count`, `is_shadowbanned`, `created_at`.
  - `bt_tokens`: `token`, `user_id`, `expires_at`.
  - `matches`: `id`, `requester_id`, `receiver_id`, `status`, `created_at`.
  - `messages`: `id`, `match_id`, `sender_id`, `encrypted_content`, `nonce`, `mac`, `created_at`.
  - `reports`: `reported_id` (trigger).
- Rol de migración con permisos de owner/superuser (`postgres` en Supabase) para `CREATE OR REPLACE FUNCTION`, `DROP/CREATE POLICY` y `CREATE TRIGGER`.
- `service_role` no se usa desde el cliente; su bypass de RLS depende de `auth.uid() IS NULL`.

### 3.2 Precondiciones operativas

- [ ] Proyecto de staging identificado por `project_ref` (no por credenciales).
- [ ] Ventana acordada; sin pruebas E2E ni despliegues concurrentes.
- [ ] Backup/snapshot completado y **restauración probada** en una base desechable.
- [ ] `pg_dump` o branch de staging disponible; retención definida.
- [ ] Cliente actual desplegado en staging usa RPC (`resolve_bt_token`, `mark_messages_read`, `mark_message_delivered`).
- [ ] Se conoce la versión mínima de app; clientes antiguos que lean `bt_tokens` o actualicen `messages` directamente quedarán fuera de servicio (ver §8).
- [ ] `SameAccountClaimPolicy.allowSameAccountClaim = false` en la app de staging.
- [ ] Autorización explícita recibida para **staging** (no producción).

### 3.3 Preflight SQL (ejecutar y guardar salida saneada)

```sql
-- Versión y rol
select version(), current_user, current_database();

-- RLS activo en las tablas afectadas
select c.relname, c.relrowsecurity, c.relforcerowsecurity
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('users','bt_tokens','matches','messages','reports')
order by c.relname;

-- Policies actuales (revisar cualquier policy amplia o duplicada)
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('users','bt_tokens','matches','messages','reports')
order by tablename, cmd, policyname;

-- Funciones afectadas: definición y ACL
select p.proname,
       pg_get_function_identity_arguments(p.oid) as args,
       p.prosecdef,
       p.proacl,
       pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'claim_zone_id','resolve_bt_token','verify_zone_id',
    'handle_new_report','enforce_user_protected_columns',
    'enforce_match_immutable_participants','enforce_message_immutable_columns'
  )
order by p.proname;

-- Triggers actuales
select event_object_table, trigger_name, event_manipulation, action_timing
from information_schema.triggers
where trigger_schema = 'public'
  and event_object_table in ('users','reports','matches','messages')
order by event_object_table, trigger_name;

-- Duplicados reversos de matches (Z-211; no los toca Z-212, pero afecta al staging)
select least(requester_id, receiver_id) as a,
       greatest(requester_id, receiver_id) as b,
       count(*) as n
from public.matches
group by 1,2
having count(*) > 1;

-- Cualquier policy UPDATE en messages (debe ser 0 después de Z-212)
select policyname, roles, qual
from pg_policies
where schemaname='public' and tablename='messages' and cmd='UPDATE';

-- Cualquier policy SELECT amplia en bt_tokens (debe quedar solo la self-scoped)
select policyname, roles, qual
from pg_policies
where schemaname='public' and tablename='bt_tokens' and cmd='SELECT';
```

**Criterios de preflight:**

- RLS `true` en las cinco tablas.
- `messages` UPDATE: 0 policies, o solo `"Actualizar mensaje con match aceptado"` (Z-212 la elimina).
- `bt_tokens` SELECT: solo `"Ver propio token"` o la amplia `"Resolver token BT"` (Z-212 la elimina). Cualquier otra policy SELECT amplia debe investigarse antes de aplicar.
- `matches` UPDATE: `"Aceptar o rechazar match"` o ninguna; Z-212 la reemplaza.
- `users` UPDATE: `"Actualizar propio perfil"`; el trigger protege columnas.
- No hay funciones con `proacl` que otorguen `anon`/`PUBLIC` en las RPC afectadas.
- Los duplicados de `matches` están inventariados; si existen, decidir si se aplica Z-211 antes/después y hacer backup.

---

## 4. Backup y restauración

### 4.1 Opción preferida: snapshot/branch de staging

- Crear un branch/snapshot de staging antes de la ventana.
- Verificar que el snapshot restaura en una instancia desechable.
- No usar producción para la prueba de restauración.

### 4.2 Opción alternativa: `pg_dump` lógico

```bash
# Variables de entorno ya configuradas; NO imprimir la URL.
pg_dump "$STAGING_DB_URL" \
  --schema=public \
  --format=custom \
  --file=z212_staging_pre_$(date +%Y%m%d_%H%M%S).dump
```

- Cifrar el archivo en reposo y restringir acceso.
- Probar `pg_restore --clean --if-exists` en una base desechable.
- Conservar hasta el sign-off; borrar según política de retención.

### 4.3 Qué NO es un rollback seguro

- Volver a crear `"Resolver token BT"`, `"Actualizar mensaje con match aceptado"` o el `UPDATE users SET id` **reintroduce los defectos P0/P1**. No hacerlo.
- Z-212 no modifica datos; si hay que revertir, la vía segura es **restaurar el snapshot** o aplicar un **forward-fix** revisado. No existe un “reverse SQL” que restaure el estado seguro anterior porque el estado anterior era vulnerable.
- Si se restaura el snapshot, se pierden las escrituras posteriores al backup; documentar la ventana.

---

## 5. Procedimiento de aplicación

### 5.1 Comando exacto (staging)

```bash
# 1) Confirmar que la variable apunta a STAGING (sin imprimirla)
#    Ejemplo de comprobación segura: comparar el project_ref esperado.
psql "$STAGING_DB_URL" -Atc "select current_database(), current_user;"

# 2) Timeouts para no bloquear la tabla indefinidamente
export PGOPTIONS="-c lock_timeout=5s -c statement_timeout=120s"

# 3) Aplicar la migración (el archivo ya contiene BEGIN/COMMIT)
psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase_migrations/z212_security_hardening.sql
```

En PowerShell:

```powershell
$env:PGOPTIONS = "-c lock_timeout=5s -c statement_timeout=120s"
psql $env:STAGING_DB_URL -v ON_ERROR_STOP=1 -f supabase_migrations/z212_security_hardening.sql
if ($LASTEXITCODE -ne 0) { throw "Z-212 falló; la transacción debe haber revertido" }
```

**No usar** `--single-transaction` junto al archivo (el archivo ya abre/cierra su propia transacción). **No usar** `supabase db reset`.

### 5.2 Si falla

- `ON_ERROR_STOP=1` + `BEGIN/COMMIT` → PostgreSQL revierte la transacción completa.
- Verificar que no quedaron objetos parciales:

```sql
select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and proname in ('enforce_user_protected_columns','enforce_match_immutable_participants','enforce_message_immutable_columns');
```

- No reintentar a ciegas: capturar el error, revisar locks/permisos y volver al preflight.

### 5.3 Post-aplicación inmediata

```sql
-- Policies esperadas
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public'
  and tablename in ('bt_tokens','matches','messages')
order by tablename, cmd, policyname;

-- Triggers esperados
select event_object_table, trigger_name, action_timing, event_manipulation
from information_schema.triggers
where trigger_schema='public'
  and trigger_name in ('trg_users_protected_columns','trg_matches_immutable_participants','trg_messages_immutable','on_new_report');

-- Funciones esperadas
select p.proname, p.prosecdef, p.proacl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('claim_zone_id','resolve_bt_token','enforce_user_protected_columns','enforce_match_immutable_participants','enforce_message_immutable_columns');
```

**Esperado:**

- `bt_tokens` SELECT: solo `"Ver propio token"`.
- `messages` UPDATE: 0 policies.
- `messages` DELETE: `"Eliminar mensaje con match aceptado"`.
- `matches` UPDATE: `"Aceptar o rechazar match"` con `WITH CHECK (auth.uid() = receiver_id)`.
- Triggers: los cuatro presentes.
- `claim_zone_id` y `resolve_bt_token`: `SECURITY DEFINER`, ACL solo `postgres/authenticated/service_role` (sin `anon`/`PUBLIC`).

---

## 6. Pruebas positivas y negativas con JWT/roles reales

> Usar usuarios de prueba de staging. **Nunca** pegar JWT, anon key ni service_role
> key en el informe. Guardar solo resultados y logs saneados.

### 6.1 Matriz de roles

| Rol | Cómo se obtiene | Uso |
|-----|-----------------|-----|
| `anon` | Cliente Supabase sin sesión (anon key) | Debe ser rechazado en RPC/tablas |
| `authenticated` (usuario A) | JWT de usuario de prueba A | Dueño de su fila/tokens/mensajes |
| `authenticated` (usuario B) | JWT de usuario de prueba B | Tercero / receptor de match |
| `service_role` | Solo servidor/CI, nunca cliente | Administración; no debe usarse para validar RLS de usuario |

### 6.2 Pruebas positivas

| ID | Prueba | Resultado esperado |
|----|--------|--------------------|
| P-01 | `claim_zone_id('ZONE-...')` como usuario A | Error que contiene `Z-212`; **no** mueve `users.id` |
| P-02 | `resolve_bt_token(token_de_B)` como A, token válido | Perfil con `avatar_url`/handles privados en `NULL` |
| P-03 | `select * from bt_tokens` como A | Solo tokens de A (0 o propios); nunca el mapping completo |
| P-04 | `mark_messages_read(match, A)` como A, match aceptado | `read_at` actualizado solo en mensajes de B |
| P-05 | `mark_message_delivered(msg, A)` como A, match aceptado | `delivered_at` actualizado |
| P-06 | `update matches set status='accepted'` como receiver B | Permitido; `requester_id`/`receiver_id` intactos |
| P-07 | `update users set display_name=...` como A | Permitido |
| P-08 | `insert into reports(reported_id=B)` como A (3 reporteros distintos) | `reports_count` incrementa; shadowban a los 3 |
| P-09 | `get_active_users_for_radar()` como A | Respeta `v_profile` (stealth, bloqueos, avatar privado) |
| P-10 | `verify_zone_id('ZONE-...')` como A | Devuelve `{exists, display_name, avatar_url}` sin `id`/`zone_id` |

### 6.3 Pruebas negativas

| ID | Prueba | Resultado esperado |
|----|--------|--------------------|
| N-01 | `claim_zone_id` como `anon` | `42501 permission denied` o error de sesión; nunca éxito |
| N-02 | `resolve_bt_token` como `anon` | `42501 permission denied` |
| N-03 | `resolve_bt_token` sin JWT / sesión vacía | Error `Se requiere sesión autenticada` |
| N-04 | `select * from bt_tokens` como `anon` | `42501` / 0 filas |
| N-05 | `update messages set encrypted_content=...` como A | `42501` (sin policy UPDATE) o trigger de inmutabilidad |
| N-06 | `update messages set sender_id=...` como A | Trigger: `messages: identidad y contenido son inmutables` |
| N-07 | `update messages set match_id=...` como A | Trigger de inmutabilidad |
| N-08 | `update messages set delivered_at=...` directo como A | `42501` (sin policy UPDATE); solo RPC |
| N-09 | `update matches set requester_id=...` como receiver B | Trigger: `matches: participantes e identidad son inmutables` |
| N-10 | `update matches set status='rejected'` sobre accepted | Trigger: `un match aceptado no puede degradarse` |
| N-11 | `update matches ...` como tercero C | 0 filas / `42501` |
| N-12 | `update users set is_shadowbanned=false` como A | Trigger: `users: columnas protegidas inmutables` |
| N-13 | `update users set reports_count=0` como A | Trigger de columnas protegidas |
| N-14 | `update users set id=...` o `zone_id=...` como A | Trigger de columnas protegidas |
| N-15 | `insert into users` con `id` de otro usuario | `WITH CHECK (auth.uid() = id)` / RLS |
| N-16 | `handle_new_report()` o `set_config` vía API como A | `42501` / no expuesto |
| N-17 | `get_active_users_for_radar` como `anon` | `42501` |
| N-18 | `verify_zone_id` como `anon` | `42501` |

### 6.4 Pruebas de RLS y privilegios

- Confirmar `relrowsecurity = true` en `users`, `bt_tokens`, `matches`, `messages`, `reports`.
- Confirmar que `anon` no tiene `EXECUTE` en `claim_zone_id`, `verify_zone_id`, `resolve_bt_token`, `mark_messages_read`, `mark_message_delivered`, `get_active_users_for_radar`, `get_radar_stats`.
- Confirmar que `authenticated` sí tiene `EXECUTE` en las RPC de app y **no** en `handle_new_report`.
- Confirmar que `service_role` no se filtra al cliente (revisar configuración de la app; no imprimir la clave).

### 6.5 Validación de RPC post-migración

- `pg_get_functiondef` de `claim_zone_id` contiene la excepción Z-212.
- `pg_get_functiondef` de `resolve_bt_token` contiene `auth.uid() IS NULL` y los `CASE WHEN ... _visible`.
- `pg_get_functiondef` de los tres triggers contiene las comprobaciones de columnas.
- `proacl` de las RPC no incluye `anon` ni `PUBLIC`.

---

## 7. Idempotencia y segunda ejecución

1. Aplicar Z-212 en staging (ventana principal).
2. Ejecutar de nuevo el mismo archivo en la misma ventana (o en un clone) y comprobar `exit 0`.
3. Verificar que no se duplicaron triggers/policies:

```sql
select event_object_table, trigger_name, count(*)
from information_schema.triggers
where trigger_schema='public'
  and trigger_name in ('trg_users_protected_columns','trg_matches_immutable_participants','trg_messages_immutable','on_new_report')
group by 1,2
having count(*) > 1;

select tablename, policyname, count(*)
from pg_policies
where schemaname='public'
  and policyname in ('Aceptar o rechazar match','Ver propio token','Eliminar mensaje con match aceptado')
group by 1,2
having count(*) > 1;
```

**Esperado:** 0 filas en ambas consultas.

---

## 8. Compatibilidad de clientes y plan de rollout

Z-212 cambia contratos que clientes antiguos pueden usar directamente:

| Contrato antiguo | Efecto tras Z-212 | Mitigación |
|------------------|-------------------|------------|
| `SELECT ... FROM bt_tokens` para resolver radar | La policy amplia desaparece; solo se ven tokens propios | El cliente actual usa `resolve_bt_token`; forzar versión mínima o feature flag |
| `UPDATE messages SET delivered_at/read_at` directo | Sin policy UPDATE; falla | El cliente actual usa RPC Z-007; forzar versión mínima |
| `claim_zone_id` para login de usuario existente | Siempre falla (cuarentena) | Ya bloqueado por `SameAccountClaimPolicy`; comunicar “nueva cuenta por dispositivo” |
| `UPDATE matches SET ...` como receiver | Sigue permitido, pero con `WITH CHECK` y trigger | Sin cambio funcional esperado |

**Decisión requerida antes de producción:** versión mínima de app y comunicación
a usuarios. En staging, validar con la versión exacta que se desplegará.

---

## 9. Criterios de aceptación

- [ ] Preflight completo sin hallazgos bloqueantes.
- [ ] Backup/snapshot creado y restauración probada.
- [ ] Migración aplicada con `exit 0` en una sola transacción.
- [ ] Segunda aplicación con `exit 0`.
- [ ] Policies/triggers/funciones post-estado coinciden con §5.3.
- [ ] Matriz P-01…P-10 y N-01…N-18 ejecutada con JWT reales; todos PASS.
- [ ] `anon` rechazado en todas las RPC/tablas sensibles.
- [ ] `authenticated` no puede modificar columnas protegidas ni contenido de mensajes.
- [ ] Radar/chat/receipts/perfil funcionan en la app de staging.
- [ ] No hay políticas amplias residuales en `bt_tokens`/`messages`/`matches`.
- [ ] Evidencia saneada (sin JWT, claves ni URLs) archivada.
- [ ] Rollback/restore probado y documentado.
- [ ] Sign-off del CTO para continuar a producción (fuera de este runbook).

---

## 10. Rollback / recuperación

| Escenario | Acción |
|-----------|--------|
| Falla durante la migración | La transacción revierte; no hay cambios. Corregir y reintentar. |
| Migración aplicada pero la app rompe por contrato antiguo | Detener escrituras; evaluar forward-fix o restaurar snapshot. **No** recrear policies vulnerables. |
| Datos inconsistentes | Restaurar snapshot; documentar ventana de pérdida. |
| Necesidad de revertir el claim | **No** restaurar `UPDATE users SET id`. Implementar la prueba de posesión (Fase F) o mantener la cuarentena. |
| Necesidad de revertir tokens | **No** recrear `"Resolver token BT"`. Mantener RPC + policy self-scoped. |

---

## 11. Autorización solicitada

**Actualización 2026-10-27:** la solicitud formal se pasó a ser la puerta §0
(confirmación explícita del propietario por proyecto y ventana). Los
requisitos originales de esta sección se conservan como agenda de la
confirmación:

1. **Entorno:** staging (project_ref / host), nunca producción.
2. **Ventana:** fecha y hora (zona horaria).
3. **Rol de migración:** `postgres` o equivalente con permisos de owner.
4. **Backup:** tipo (snapshot/branch o `pg_dump`) y confirmación de restauración probada.
5. **Alcance:** aplicar `z212_security_hardening.sql`, ejecutar preflight/postflight y la matriz P/N; sin cambios de datos ni despliegues de app.
6. **Responsable:** quién aprueba y quién ejecuta.

Hasta recibir esa autorización, **no se conectará ni modificará staging**. No se
solicitan credenciales en este documento; se usarán las variables/CLI seguras ya
configuradas.

---

## 12. Evidencia local ya disponible

- `supabase_migrations/tests/z212_behavioral_test.sql` → **ALL Z-212 SQL TESTS PASSED** en PostgreSQL 18.4 aislado (`PSQL_EXIT=0`), incluyendo re-aplicación de migraciones históricas.
- `test/sql_security_regression_test.dart` → **4/4 PASS**.
- Segunda aplicación de Z-212 → `RUN2_EXIT=0` (sesión previa; Z-212 no cambió en Fase A).
- Limitación: la validación local **no** habilita RLS ni usa JWT reales; por eso el runbook exige pruebas P/N en staging.
