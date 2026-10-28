# FASE 2 · Hardening de seguridad Z-212

**Proyecto:** ZONE (Flutter)
**Repositorio:** `D:\Proyectos\Zone`
**Commit base:** `7f59b776c62cc131fd05dc999e99cbb7804385e8`
**Fecha:** 2026-10-23
**Estado:** implementado y validado localmente · **NO aplicado en remoto** · **NO commiteado**

---

## 1. Resumen ejecutivo

Se implementaron controles para **cinco defectos SQL demostrables** y para un conjunto de defectos del pipeline cliente:

| # | Defecto | Control aplicado | Estado local |
|---|---|---|---|
| Z-212-01 | Account takeover vía `claim_zone_id` | Cuarentena fail-closed + guarda cliente | **VERIFIED** (SQL) |
| Z-212-02 | Exposición de `bt_tokens` y perfiles privados | Política amplia eliminada + RPC con sesión/visibilidad | **VERIFIED** (SQL) |
| Z-212-03 | Forging/tampering de mensajes | UPDATE directo eliminado + trigger de inmutabilidad | **VERIFIED** (SQL) |
| Z-212-04 | Reescritura del par de match / degradación | `WITH CHECK` + trigger de identidad/estado | **VERIFIED** (SQL) |
| Z-212-05 | Auto-modificación de moderación/identidad | Trigger de columnas protegidas + flag de moderación | **VERIFIED** (SQL) |
| Cliente | Inyección de payload en claro / spoofing | Descarte fail-closed de payloads no válidos | **VERIFIED** (código + tests) |
| Cliente | Paquetes/rutas mesh malformados | Validadores de paquete y tabla de rutas | **VERIFIED** (23 tests) |
| Cliente | Fuga de avatar/handles en P2P | Visibilidad aplicada en origen | **VERIFIED** (código) |
| Cliente | Sustitución de clave de sesión | No se reemplaza una clave existente | **VERIFIED** (código) |
| Cliente | Perfil remoto envenena Isar/LWW | Validación de id, fechas y zone_id | **VERIFIED** (código) |
| Cliente | Fallback inseguro a `bt_tokens` | Solo RPC, fail-closed | **VERIFIED** (código) |
| Cliente | Outbox borra mensajes no confirmados | IDs confirmados por el servidor | **VERIFIED** (código) |
| Cliente | Reintentos duplican mensajes/encuentros | IDs estables + upsert idempotente | **VERIFIED** (código) |
| Android | Backup/cleartext/permiso amplio | Manifest endurecido | **VERIFIED** (manifest) |

**Validación local:**

- PostgreSQL 18.4, clúster temporal aislado: **`ALL Z-212 SQL TESTS PASSED`**, `PSQL_EXIT=0`.
- `flutter analyze --no-pub`: **PASS**, `No issues found!`.
- `test/mesh_policy_test.dart`: **23/23 PASS**.
- Suite completa: **219 passed · 21 failed**, todos los fallos por `isar.dll` error 126 (entorno Windows).

**No se aplicó nada en producción, no se creó ningún commit y no se hizo push/deploy.**

---

## 2. Principios de diseño

1. **El servidor es la autoridad** de identidad, visibilidad, moderación y membresía de matches.
2. **Fail-closed:** si falta una prueba o el payload no cumple el contrato, se rechaza; nunca se degrada a texto claro o a un fallback inseguro.
3. **No inventar criptografía:** `claim_zone_id` se cuarentena en lugar de simular una “prueba de posesión” con un chequeo cosmético. Se re-habilitará solo con un challenge firmado y verificado server-side.
4. **Preservar el trabajo previo:** los cambios se limitaron a hunks concretos; no se revirtió ni borró trabajo del usuario.

---

## 3. Hardening SQL

### 3.1 Z-212-01 · `claim_zone_id` (account takeover)

**Antes (`HEAD:supabase_schema.sql:673`):**

```sql
UPDATE public.users u SET id = v_uid
WHERE u.zone_id = p_zone_id
RETURNING jsonb_build_object(...);
```

Cualquier usuario autenticado que conociera un ZONE-ID ajeno podía reescribir el `users.id` de la víctima. Las referencias FK (`matches`, `messages`, `encounters`, `bt_tokens`, etc.) apuntaban al mismo `id`, por lo que el atacante heredaba la identidad y el historial. El formato estricto y el rate-limit solo dificultaban la enumeración; **no probaban posesión de la clave**.

**Después (`supabase_schema.sql:731-761`, `z212_security_hardening.sql:25-42`):**

```sql
CREATE OR REPLACE FUNCTION public.claim_zone_id(p_zone_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Se requiere sesión autenticada';
  END IF;
  RAISE EXCEPTION
    'Reclamo de ZONE-ID deshabilitado temporalmente por seguridad (Z-212).';
END;
$$;
```

- Se conserva la firma `claim_zone_id(text)` y los grants para no romper clientes.
- `REVOKE ... FROM PUBLIC, anon`; `GRANT ... TO authenticated`.
- Se elimina la variante obsoleta `claim_zone_id(text, text)`.
- El cliente ejecuta `SameAccountClaimPolicy.ensureAllowed(zoneId)` como **primera sentencia** de `loginWithExistingID`, antes de sign-in, storage, RPC o generación de claves (`lib/services/same_account_claim_policy.dart:49-58`, `lib/services/zone_id_service.dart:129-140`).
- Regla temporal: **NEW DEVICE = NEW ACCOUNT**. El puente cuenta/dispositivo con prueba de posesión queda para una fase posterior.

**Prueba:** SQL test 1 — un usuario autenticado que intenta reclamar el ZONE-ID de otro recibe la excepción `Z-212`.

**Riesgo residual:** el login de un usuario existente en otro dispositivo queda **intencionalmente no funcional**. Es una decisión de producto pendiente; no se debe habilitar hasta implementar el challenge firmado + registro de dispositivo.

---

### 3.2 Z-212-02 · `bt_tokens` y visibilidad de perfiles

**Antes (`HEAD:supabase_schema.sql:408-410`):**

```sql
CREATE POLICY "Resolver token BT" ON public.bt_tokens
    FOR SELECT TO authenticated
    USING (auth.role() = 'authenticated' AND expires_at > now());
```

Cualquier autenticado podía leer el mapping `token → user_id` de **todos** los usuarios activos. La RPC `resolve_bt_token` devolvía `avatar_url` y handles sin aplicar los flags de visibilidad.

**Después (`supabase_schema.sql:441-456`, `811-854`; migración `100-143`):**

- Se elimina la política amplia. Solo queda `"Ver propio token"` (`auth.uid() = user_id`).
- `resolve_bt_token` exige `auth.uid()`; sin sesión lanza `Se requiere sesión autenticada`.
- Filtra `is_shadowbanned = FALSE` y `stealth_mode = FALSE`.
- Devuelve `avatar_url` solo si `avatar_is_public`; handles solo si `ig_visible` / `fb_visible` / `tiktok_visible`.
- El cliente (`lib/services/supabase_service.dart:53-67`) usa **solo** la RPC; si no está disponible, retorna `null` (fail-closed). No hay SELECT directo de respaldo.

**Prueba:** SQL test 2 — resolución con sesión devuelve el perfil y oculta avatar/handle privados; sin sesión se rechaza.

**Riesgo residual:** el token es una **capacidad bearer** que se comparte con vecinos por diseño (radar bilateral). Quien lo observe puede resolver el perfil dentro del TTL (10 min) y mientras no rote. El token **no es identidad criptográfica**; no debe usarse como prueba de posesión.

---

### 3.3 Z-212-03 · Inmutabilidad de mensajes

**Antes (`HEAD:supabase_schema.sql:472-475`):**

```sql
CREATE POLICY "Actualizar mensaje con match aceptado" ON public.messages
    FOR UPDATE TO authenticated USING (
        EXISTS (... match aceptado y participante ...)
    );
```

Un participante podía actualizar **cualquier columna**, incluidos `sender_id`, `match_id`, `encrypted_content`, `nonce`, `mac` y `created_at`. Eso permite forgery (atribuir un mensaje a la otra parte) y tampering del historial.

**Después (`supabase_schema.sql:545-572`; migración `179-201`):**

- Se elimina la política UPDATE directa.
- Trigger `trg_messages_immutable` bloquea cambios en:
  `id`, `match_id`, `sender_id`, `encrypted_content`, `nonce`, `mac`, `created_at`.
- Solo se permiten `delivered_at` y `read_at`, que son los ticks de las RPC Z-007 (`mark_message_delivered`, `mark_messages_read`), ejecutadas con `SECURITY DEFINER` y gate `auth.uid()`.
- El cliente ya no hace UPDATE directo de `messages`; solo insert/select/upsert/delete.

**Prueba:** SQL test 3 — `encrypted_content = 'tampered'` es rechazado; `delivered_at = now()` se acepta.

**Riesgo residual:** la política DELETE de mensajes sigue existiendo (derecho al borrado). El emisor puede enviar ciphertext arbitrario (comportamiento esperado); lo que ya no puede es reescribir un mensaje existente. El enforcement real de RLS no se ejercitó en los stubs.

---

### 3.4 Z-212-04 · Identidad y estado de matches

**Antes (`HEAD:supabase_schema.sql:435-437`):**

```sql
CREATE POLICY "Aceptar o rechazar match" ON public.matches
    FOR UPDATE TO authenticated USING (auth.uid() = receiver_id);
```

Sin `WITH CHECK`, el receiver podía reescribir `requester_id`/`receiver_id` (por ejemplo, ponerse como requester de un match ajeno) o degradar un match `accepted` a `rejected`/`pending`.

**Después (`supabase_schema.sql:480-517`; migración `146-174`):**

```sql
CREATE POLICY "Aceptar o rechazar match" ON public.matches
    FOR UPDATE TO authenticated
    USING (auth.uid() = receiver_id)
    WITH CHECK (auth.uid() = receiver_id);
```

Además, `trg_matches_immutable_participants` bloquea cambios en `id`, `requester_id`, `receiver_id` y `created_at`, y prohíbe que un match `accepted` deje de serlo.

**Prueba:** SQL test 4 — reescribir `requester_id` se rechaza; `accepted → rejected` se rechaza.

**Riesgo residual:** el receiver sigue pudiendo aceptar/rechazar un match `pending` (comportamiento intencional). El enforcement real de RLS no se ejercitó en los stubs.

---

### 3.5 Z-212-05 · Columnas protegidas de `users`

**Antes:** la política `"Actualizar propio perfil"` permitía al usuario actualizar **todas** sus columnas. Un usuario podía ponerse `is_shadowbanned = false`, `reports_count = 0`, o cambiar `id`/`zone_id`/`created_at`.

**Después (`supabase_schema.sql:238-269`; migración `45-98`):**

- Trigger `trg_users_protected_columns` bloquea, para usuarios autenticados, cambios en:
  `id`, `zone_id`, `reports_count`, `is_shadowbanned`, `created_at`.
- `service_role` (sin `auth.uid()`) conserva acceso administrativo.
- La función de moderación `handle_new_report` marca la transacción con `zone.allow_protected_user_write = '1'` antes de incrementar `reports_count` y aplicar shadowban a los 3 reportes. Así la moderación confiable sigue funcionando sin abrir la puerta al cliente.
- Los campos de perfil (`display_name`, `bio`, handles, flags de visibilidad, avatar) siguen siendo editables por el dueño.

**Pruebas:** SQL tests 5 y 6 — el usuario no puede cambiar `is_shadowbanned`; sí puede cambiar `display_name`; tres reportes incrementan el contador y aplican shadowban.

**Riesgo residual:** el trigger es el control, no un GRANT column-level. Cualquier función `SECURITY DEFINER` futura que escriba estas columnas debe usar el flag o ejecutarse como `service_role`.

---

### 3.6 Tabla resumen de controles SQL

| Control | `supabase_schema.sql` | `z212_security_hardening.sql` | `supabase_deploy.sql` |
|---|---|---|---|
| Cuarentena `claim_zone_id` | 731-761 | 25-42 | 183-198 |
| Trigger columnas `users` | 238-269 | 45-98 | 323-351 |
| `bt_tokens` sin policy amplia | 441-456 | 100-143 | 531-533 |
| `resolve_bt_token` con sesión/visibilidad | 808-854 | 100-143 | 252+ |
| `matches` `WITH CHECK` + trigger | 480-517 | 146-174 | 551-581 |
| `messages` sin UPDATE + trigger | 545-572 | 179-201 | 611-636 |

---

## 4. Hardening cliente

| Control | Antes | Después | Referencia |
|---|---|---|---|
| Inyección de payload | Un payload no-JSON se inyectaba como mensaje; tipos desconocidos podían fluir | Solo se aceptan `profile_exchange`, `routing_table`, `mesh_msg`; no-JSON/no-Map/desconocido se descarta | `lib/services/nearby_service.dart:1030-1073` |
| Validación de paquete mesh | `mesh_msg` se procesaba sin contrato estricto | `isEncrypted == true`, ZONE-IDs canónicos, UUID v4, ciphertext/nonce/mac acotados, `hops` 0..5; inválido → `null` | `lib/services/mesh_policy.dart:147-203` |
| Validación de rutas | Tabla de rutas aceptaba entradas malformadas o ilimitadas | ZONE-ID canónico, distancia 0..4, máximo 256 rutas por update; tabla acotada a 1024 | `lib/services/mesh_policy.dart:205-222` |
| Visibilidad P2P | Se compartían avatar/handles aunque el dueño los marcara privados | `_shareProfileP2P` envía `null` según `avatar_is_public`, `ig_visible`, `fb_visible`, `tiktok_visible` | `lib/services/nearby_service.dart:1077-1106` |
| Sustitución de clave | Un `profile_exchange` posterior podía reemplazar la clave de sesión | Si ya existe clave para el ZONE-ID, se conserva; el primer contacto sigue siendo TOFU (Z-004) | `lib/services/nearby_service.dart:1137-1154` |
| Perfil remoto → Isar | `userId` nulo o fechas inválidas podían reventar o envenenar el LWW | Exige id no vacío; parsea fechas de forma segura; normaliza timestamps >5 min en el futuro; resuelve `zone_id` sin crash | `lib/services/isar_service.dart:31-89` |
| Resolución de token | RPC + fallback a SELECT directo de `bt_tokens` | Solo RPC; error → `null` | `lib/services/supabase_service.dart:46-67` |
| Outbox de mensajes | Se asumía que los primeros N habían entrado; se borraban no confirmados | `sendMessagesBatch` devuelve `Set<String>` de IDs confirmados; el outbox borra solo esos y incrementa retry en el resto | `lib/services/supabase_service.dart:440-465`, `lib/services/sync_service.dart:147-158` |
| Idempotencia de envío | Reintento generaba UUID nuevo → duplicado remoto | `sendMessageIdempotent` usa el `messageId` estable + `upsert(onConflict: 'id', ignoreDuplicates: true)` | `lib/services/supabase_service.dart:467-499`, `lib/services/sync_service.dart:215-233` |
| Encuentros rechazados | `registerEncounter` tragaba errores y se marcaba como sincronizado | Devuelve `bool`; `_syncEncounters` lanza si es `false` y no marca el encuentro | `lib/services/supabase_service.dart:87-122`, `lib/services/sync_service.dart:163-188` |
| Reintento de chat | Generaba un UUID nuevo y perdía el ciphertext original | Reutiliza `pending.messageId`/`encryptedContent`/`nonce`/`mac`; borra el pending solo tras éxito | `lib/screens/chat_screen.dart:602-656` |
| Backup/cleartext Android | `allowBackup` por defecto, tráfico cleartext permitido, `READ_EXTERNAL_STORAGE` sin límite | `allowBackup=false`, `fullBackupContent=false`, `usesCleartextTraffic=false`, `READ_EXTERNAL_STORAGE` con `maxSdkVersion=32` | `android/app/src/main/AndroidManifest.xml:22,31-33` |

**Nota:** `usesCleartextTraffic="false"` puede romper un backend HTTP de desarrollo. No se validó en dispositivo; debe revisarse la configuración de dev/staging antes de release.

---

## 5. Validación

### 5.1 SQL — PostgreSQL 18.4 real, clúster temporal

**Arnés reproducible:** `supabase_migrations/tests/z212_behavioral_test.sql`.

El arnés:

1. crea roles `anon`, `authenticated`, `service_role`;
2. crea un schema `auth` con `auth.uid()` basado en `request.jwt.claim.sub`;
3. crea tablas mínimas `users`, `bt_tokens`, `matches`, `messages`, `reports`;
4. incluye la migración con `\ir ../z212_security_hardening.sql`;
5. ejecuta seis grupos de aserciones.

**Comando ejecutado:**

```powershell
initdb -D <temp> -U postgres -A trust --no-locale -E UTF8
pg_ctl -D <temp> -o '"-p 55433 -c listen_addresses=127.0.0.1"' start
psql -h 127.0.0.1 -p 55433 -U postgres -d postgres `
  -v ON_ERROR_STOP=1 `
  -f D:\Proyectos\Zone\supabase_migrations\tests\z212_behavioral_test.sql
```

**Resultado:**

```text
PSQL_EXIT=0
ALL Z-212 SQL TESTS PASSED
```

| Grupo | Aserción | Resultado |
|---|---|---|
| 1 | `claim_zone_id` rechaza un reclamo ajeno con error `Z-212` | **PASS** |
| 2 | `resolve_bt_token` exige sesión, resuelve el perfil y oculta avatar/handle privados | **PASS** |
| 3 | `messages`: contenido/identidad inmutables; `delivered_at` permitido | **PASS** |
| 4 | `matches`: par inmutable; `accepted` no degrada | **PASS** |
| 5 | `users`: columnas protegidas inmutables; `display_name` editable | **PASS** |
| 6 | Moderación: 3 reportes incrementan contador y aplican shadowban | **PASS** |

**Re-ejecución:** la migración se aplicó una segunda vez sobre la misma base (`psql -f z212_security_hardening.sql`); `RUN2_EXIT=0`. Los `DROP ... IF EXISTS` / `CREATE OR REPLACE` permiten re-aplicarla sin error.

**Limitación explícita:** los stubs **no habilitan RLS**. Se validan funciones y triggers, no el enforcement de las políticas `CREATE POLICY`. La verificación de RLS real requiere un proyecto Supabase de staging con JWT reales y queda **NOT VERIFIED**.

### 5.2 Dart

```powershell
C:\flutter\bin\flutter.bat analyze --no-pub
# Analyzing Zone...
# No issues found! (ran in 12.2s)

C:\flutter\bin\flutter.bat test --no-pub test\mesh_policy_test.dart
# 23/23 passed

C:\flutter\bin\flutter.bat test --no-pub
# 00:30 +219 -21: Some tests failed.
```

Los 21 fallos son los mismos tres archivos de identidad bloqueados por `isar.dll`:

```text
Invalid argument(s): Failed to load dynamic library
'D:\Proyectos\Zone\isar.dll': error code 126
```

- `identity_bootstrap_integration_test.dart`: 3
- `identity_persistence_test.dart`: 10
- `migration_persistence_test.dart`: 8

No hay fallos funcionales nuevos atribuibles a los cambios de esta fase.

### 5.3 Lo que NO se verificó

| Elemento | Estado | Motivo |
|---|---|---|
| Aplicación de la migración en staging/producción | **NOT VERIFIED** | Requiere autorización explícita y credenciales |
| RLS real con JWT de Supabase | **NOT VERIFIED** | Stubs locales sin RLS |
| `resolve_bt_token` contra PostgREST real | **NOT VERIFIED** | Sin proyecto remoto |
| Build release firmado | **NOT VERIFIED** | Sin keystore; Gradle firma con debug |
| Dispositivos físicos BLE/Nearby | **NOT VERIFIED** | No disponibles |
| Backup/restore y rollback | **NOT VERIFIED** | No ejecutado |
| Rendimiento del hardening | **NOT VERIFIED** | Sin benchmark |

---

## 6. Riesgos residuales

### P0 — bloquean beta

| ID | Riesgo | Por qué no se cerró | Criterio de salida |
|---|---|---|---|
| P0-1 | La migración Z-212 no está aplicada en remoto | Requiere autorización explícita; no se toca producción sin ella | Aplicar en staging, verificar con JWT/RLS reales, luego producción con backup |
| P0-2 | Spoofing/MITM P2P en primer contacto (Z-004) | Requiere protocolo de identidad firmada, no un parche | Binding `zone_id ↔ account_id ↔ device_id ↔ clave` con challenge/response Ed25519 y rotación/recovery |
| P0-3 | Login de usuario existente no funcional | Decisión de producto: no hay puente cuenta/dispositivo | Implementar registro de dispositivo + challenge firmado, o declarar “new device = new account” en UX y retirar el login roto |
| P0-4 | Release firmado con claves debug | Falta keystore y decisión de custodia | Configurar signing release, custodiar claves, verificar AAB |
| P0-5 | 21 tests de identidad bloqueados | Falta `isar.dll` en Windows | CI Linux/macOS o binario nativo; suite 240/240 o exclusiones aprobadas |
| P0-6 | Sin validación en dos dispositivos físicos | No hay hardware disponible | Matriz E2E: descubrimiento, match, chat, receipts, offline, mesh, reinicio, reinstalación |
| P0-7 | E2EE sin forward secrecy (Z-101) | Requiere rediseño criptográfico | Ratchet/HKDF/AAD o retirar la afirmación de FS de docs/UX |

### P1 — antes de beta pública

| ID | Riesgo | Nota |
|---|---|---|
| P1-1 | `resolve_bt_token` es bearer dentro del TTL | Token compartido por diseño; no es identidad. Documentar y acortar TTL si aplica |
| P1-2 | RLS no ejercitado en la validación local | Añadir tests de staging con JWT reales |
| P1-3 | Documentación sobreestima Z-001 | `BUG_REGISTER.md` debe distinguir “anon/rate-limit verificado” de “posesión probada” |
| P1-4 | `usesCleartextTraffic=false` puede romper dev | Verificar configuración de red de desarrollo |
| P1-5 | Migración sin script de rollback | Plan de rollback = restore de snapshot; documentar y ensayar |
| P1-6 | Sin escaneo de secretos en CI | Añadir gitleaks/trufflehog y revisión de historial |
| P1-7 | Dependencias desactualizadas (Z-302) | Auditoría y actualización planificada |

### P2 — deuda reconocida

- El trigger de `users` no es column-level grant; futuras funciones `SECURITY DEFINER` deben respetar el flag.
- `resolve_bt_token` devuelve `id` y `public_key` a cualquier portador de un token válido; es una capacidad de descubrimiento, no una identidad.
- El test SQL no cubre concurrencia ni volúmenes grandes.
- La cuarentena de `claim_zone_id` deja una RPC que siempre falla; es deliberado, pero debe retirarse o reemplazarse cuando exista el puente.

---

## 7. Plan de despliegue (NO EJECUTADO — requiere autorización)

> **Este plan no se ejecutó.** No se aplicó ninguna migración en remoto. Cualquier paso requiere autorización explícita del responsable del proyecto.

### 7.1 Precondiciones

1. Snapshot/backup verificable de la base de producción.
2. Proyecto de staging con RLS y JWT reales.
3. Ventana de cambio y responsable humano presente.
4. Plan de rollback = restore del snapshot (la migración es forward-only; no hay down script).
5. Cliente de release actualizado para tolerar `claim_zone_id` fail-closed y `resolve_bt_token` sin fallback.

### 7.2 Secuencia

1. **Staging:** aplicar `supabase_migrations/z212_security_hardening.sql` en una transacción.
2. **Verificar definiciones:**
   - `claim_zone_id` contiene la excepción `Z-212` y no contiene `UPDATE public.users`.
   - `has_function_privilege('anon', 'public.claim_zone_id(text)', 'EXECUTE') = false`.
   - `pg_policies` ya no muestra la policy amplia `"Resolver token BT"`.
   - Existen `trg_messages_immutable`, `trg_matches_immutable_participants`, `trg_users_protected_columns`.
3. **Verificar comportamiento con JWT reales de staging:**
   - claim ajeno → error;
   - token sin sesión → error; token con sesión → perfil con campos privados `null`;
   - UPDATE directo de `messages.encrypted_content` → rechazado;
   - `delivered_at`/`read_at` vía RPC Z-007 → aceptado;
   - reescritura de `matches.requester_id` → rechazada;
   - `accepted → rejected` → rechazado;
   - `is_shadowbanned` por cliente → rechazado;
   - 3 reportes → contador/shadowban correctos.
4. **Prueba de regresión funcional:** login nuevo, radar, match, chat, receipts, offline/outbox, encuentros.
5. **Producción:** repetir con backup y ventana; monitorear errores 42501/400 y logs de RPC.
6. **Post-deploy:** verificar que el cliente no usa el fallback eliminado y que el radar sigue resolviendo tokens con sesión.
7. **Rollback:** restore del snapshot si falla la verificación; no intentar “deshacer” triggers a mano en producción.

### 7.3 Órdenes de verificación (referencia, no ejecutadas)

```sql
-- La función ya no reescribe identidad
SELECT pg_get_functiondef('public.claim_zone_id(text)'::regprocedure);

-- anon no puede ejecutar
SELECT has_function_privilege('anon', 'public.claim_zone_id(text)', 'EXECUTE');

-- Políticas vigentes
SELECT tablename, policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('bt_tokens', 'messages', 'matches', 'users')
ORDER BY tablename, policyname;

-- Triggers vigentes
SELECT tgname, tgrelid::regclass
FROM pg_trigger
WHERE NOT tgisinternal
  AND tgname IN (
    'trg_messages_immutable',
    'trg_matches_immutable_participants',
    'trg_users_protected_columns'
  );
```

---

## 8. Archivos

### 8.1 Creados en esta fase

| Archivo | Propósito |
|---|---|
| `supabase_migrations/z212_security_hardening.sql` | Migración idempotente de los cinco controles SQL |
| `supabase_migrations/tests/z212_behavioral_test.sql` | Arnés reproducible de validación conductual |
| `docs/audit/PHASE_0_1_BASELINE_AUDIT.md` | Baseline y hallazgos |
| `docs/audit/PHASE_2_SECURITY_HARDENING_Z212.md` | Este documento |
| `docs/audit/BETA_READINESS_GATE.md` | Gate de beta |

### 8.2 Hunks añadidos en archivos preexistentes

Estos archivos **ya estaban modificados** al inicio de la auditoría. Esta fase añadió hunks concretos; no se atribuye el resto del diff a esta auditoría.

| Archivo | Hunks de esta fase |
|---|---|
| `supabase_schema.sql` | Controles Z-212 (claim, tokens, messages, matches, users, moderación) |
| `supabase_deploy.sql` | Espejo de los controles Z-212 |
| `lib/services/nearby_service.dart` | Descarte fail-closed, validación mesh, visibilidad P2P, no sustitución de clave |
| `lib/services/mesh_policy.dart` | `validateIncomingPacket`, `validateRoutingTable`, cotas |
| `lib/services/supabase_service.dart` | `resolveToken` solo RPC, `sendMessagesBatch`, `sendMessageIdempotent`, `registerEncounter` bool |
| `lib/services/sync_service.dart` | Borrado solo de IDs confirmados; encounters rechazados no se marcan |
| `lib/services/isar_service.dart` | Validación de perfil remoto/LWW |
| `lib/screens/chat_screen.dart` | Reintento con `messageId`/ciphertext estables |
| `android/app/src/main/AndroidManifest.xml` | Backup/cleartext/permiso |
| `test/mesh_policy_test.dart` | 10 tests nuevos de validación (23 total) |

### 8.3 Trabajo previo preservado

`lib/identity/`, `lib/services/same_account_claim_policy.dart`, `z210_encounter_key.sql`, `z211_match_canonical.sql`, `test/identity/`, `docs/PHASE_2_*` y el resto del árbol untracked **no fueron creados ni revertidos por esta fase**.

---

## 9. Control de cambios

| Regla | Estado |
|---|---|
| Sin `git reset --hard`, `git clean`, `git checkout --` | Cumplido |
| Sin borrar archivos/migraciones/tests | Cumplido |
| Sin migración remota | Cumplido |
| Sin commit/push/deploy | Cumplido |
| Sin secretos en el diff/reportes | Cumplido |
| Sin deshabilitar RLS/TLS/cripto | Cumplido |
| Todos los cambios sin commitear | Cumplido |

**Conclusión:** el hardening está implementado y validado localmente con evidencia reproducible. **No está desplegado.** La beta sigue bloqueada por los riesgos P0 del `BETA_READINESS_GATE.md`.
