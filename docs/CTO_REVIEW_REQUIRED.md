# CTO_REVIEW_REQUIRED — Decisión de diseño requerida · ZONE

> **Regla aplicada (FASE 1, §2/§14):** cualquier cambio que afecte autenticación,
> autorización, RLS, SECURITY DEFINER, esquema remoto de Supabase o protocolo de
> mensajería **no se implementa sin decisión explícita del CTO**.
>
> **Hallazgo:** Z-001 — `claim_zone_id` inseguro. **Hallazgo:** Z-002 — RLS `users`.
> **Fecha:** 2026-09-22 · **Estado:** ✔️ Z-001 DECIDIDO (Opción 3) → **Fase A implementada localmente** · Fase B pendiente de diseño.
> **Fecha:** 2026-09-23 · **Estado:** ✔️ Z-002 DECIDIDO (A estricto + vista `v_profile`) → implementado localmente.
> **⚠️ Remoto (sonda 2026-09-23):** producción VULNERABLE (2-arg GRANT anon viva; oráculo verify anon).
> **✅ Remoto (2026-09-23, APLICADO + VERIFICADO):** migraciones 1.2 (Z-001/Z-103) y 1.3 (Z-002) aplicadas en
> transacciones atómicas vía Management API y verificadas en vivo. Detalle y evidencia en `PHASE_1_PROGRESS.md`
> y en el §8.

## 0. Resolución del CTO (2026-09-22)

- **Modelo de posesión:** Opción 3 — Híbrida por fases (Fase A ahora, Fase B después).
- **Acceso remoto:** vía supabase CLI (`SUPABASE_ACCESS_TOKEN` + project ref pendientes de entrega).
- **Alcance:** Z-103 (`verify_zone_id`) incluido en el mismo lote.
- **Rate-limit:** sí (tabla `zone_claim_attempts`, ventana 15 min, máx 5 fallos/zone_id).

**Ajuste de diseño con base en nueva evidencia (importante):**
Al inspeccionar `chat_e2ee_service.dart:12`, las claves de identidad del cliente son
**X25519 (ECDH)**, no Ed25519 → **no pueden firmar** un challenge (el contrato de verificación
de Supabase es `pgsodium` Ed25519). Por eso la **Fase A** implementada cubre la
**autorización** (revoke anon, formato, rate-limit, fin de rotación silenciosa de `public_key`)
y el **`update_public_key` firmado se pospone a Fase B**, donde se introduce una **identidad
de firma Ed25519 separada** (x25519 = cifrado E2EE; Ed25519 = autenticación de cuenta) junto
con códigos de recuperación. Implementar la firma sobre X25519 sería criptografía improvisada
(prohibida por el protocolo).

**Fase B (diseño pendiente de CTO, NO iniciado):**
1. Alta de par Ed25519 de cuenta (Secure Storage) + `users.auth_public_key` (nuevo campo).
2. `request_zone_challenge()` (nonce efímero) + `update_public_key(p_auth_public_key, p_signature, p_challenge)` validando Ed25519 contra la `auth_public_key` previa.
3. Códigos de recuperación emitidos al crear la cuenta (hash server-side; presentación al usuario 1 sola vez).
4. `transfer_zone_id` firmado o con código de recuperación (sustituye el claim por ZONE-ID como único mecanismo).
5. Migración de datos: usuarios existentes generan `auth_public_key` al actualizar la app (establecimiento inicial sin firma previa, marcado en auditoría).

---

## 1. Problema

`public.claim_zone_id` traslada la **propiedad** de la fila `public.users`
(campo `id` → `auth.uid()`) de un ZONE-ID dado, y (según versión remota) también
sobrescribe `public_key`. El ZONE-ID (8 caracteres `A-Z0-9` con prefijo `ZONE-`,
≈ 2.8×10¹² combinaciones) es tratado como **única credencial de login**, pero:

- La función está `SECURITY DEFINER` (bypass RLS) y tiene `GRANT EXECUTE` a
  **`anon`** además de `authenticated` (schema.sql:357, deploy.sql:153,
  emergency_recovery.sql:29, migration_fix.sql:31).
- No valida **prueba de posesión** de la clave privada E2EE antes de cambiar
  `id`/`public_key`.
- `verify_zone_id` (oráculo `anon`, Z-103) confirma existencia y devuelve `id`
  sin marcar `used`, con GRANT anon (schema.sql:361+; deploy.sql:155+).
- No hay rate-limit ni validación de formato en `claim_zone_id`.
- El flujo legítimo de login en otro dispositivo (teclear el ZONE-ID) **no puede
  demostrar posesión de la clave** → conflicto fundamental de diseño.

## 2. Archivos afectados

**Backend (SQL):**
- `supabase_schema.sql:340-357` — función 1-arg `claim_zone_id(p_zone_id)` + GRANT anon/authenticated.
- `supabase_deploy.sql:140-153` — idem (1-arg) + `REVOKE FROM PUBLIC` + GRANT anon.
- `supabase_emergency_recovery.sql:6-32` — "fix" parcial: 2-arg `(p_zone_id, p_public_key DEFAULT NULL)`; **sigue GRANT anon**; escribe `public_key` sin prueba de posesión.
- `supabase_migration_fix.sql:2-31` — "fix" DESTRUCTIVO: incluye `DELETE FROM public.users WHERE id = current_uid AND zone_id != p_zone_id` (líneas 14-16). **NO APLICAR.**
- `supabase_schema.sql:361-379` — `verify_zone_id` anon (oráculo, relacionado, Z-103).

**Cliente:**
- `lib/services/zone_id_service.dart`:
  - 154-157 — login nuevo dispositivo: `rpc('claim_zone_id', {p_zone_id, p_public_key})` → **firma 2-arg**, no coincide con deploy 1-arg (la llamada legítima falla si el remoto no tiene la 2-arg).
  - 310-326 — `ensureAuth()` re-clama en CADA arranque y re-envía `p_public_key`.
  - 276-302 — si falta la clave local, **genera un par nuevo SILENCIOSAMENTE** y lo sube → rotación de identidad E2EE sin prueba (rompe continuidad de sesiones y permite asumir identidad).
  - 127-186 — `loginWithExistingID`: `signInAnonymously` → SELECT directo a `users` por zone_id (RLS expuesto, Z-002) → `claim_zone_id` → UPDATE directo de perfil → `ensureAuth`.
  - 555-562 — `_generateZoneId`: `ZONE-` + 8×`[A-Z0-9]` con `Random.secure()` (generación OK; seguridad depende del modelo de posesión).

## 3. Riesgo

**Crítico (P0).** Vectores concretos:
- **A) Toma de control directa:** cualquiera con la publishable anon key llama `claim_zone_id` por PostgREST sin sesión. Con el ZONE-ID de la víctima conocido → la fila pasa a ser suya (`id = auth.uid()`), sobrescribe `public_key` (versiones 2-arg) → robo de cuenta (perfil, radar, identidad E2EE) y exclusión de la víctima. `anon` + `auth.uid() = NULL` en modo anon deja `id` en NULL (destruye la row).
- **B) Re-claim permanente:** el cliente reclama en cada arranque (310-326); el atacante puede hacer lo mismo para mantener el control.
- **C) Rotación silenciosa de clave E2EE** (cliente 276-302 + `p_public_key` sin prueba) → ruptura de continuidad de sesiones E2EE y suplantación futura.
- **D) DESTRUCTIVO:** `supabase_migration_fix.sql` elimina rows "temporales"; en dispositivos compartidos/múltiples sesiones anónimas → pérdida de datos. No debe aplicarse.
- **E) Oráculo `verify_zone_id` anon** (sin rate-limit): enumeración/existencia + fuga de `id` (facilita A).

**Controles que aportará la corrección:** autenticación (`authenticated`), autorización (prueba de posesión), RLS coherente, rate-limiting, validación de formato/entrada, claves no rotables sin prueba, auditoría de claims.

## 4. Solución propuesta (2 fases, requiere decisión CTO)

### Conflicto de diseño que debe decidir el CTO
"Login en otro dispositivo tecleando el ZONE-ID" y "prueba de posesión con clave privada"
son **incompatibles**: la clave privada vive solo en el dispositivo original. El CTO debe elegir:

**Opción 1 — ZONE-ID como secreto endurecido (rápido):**
- `REVOKE anon`, `GRANT authenticated`; validar formato (`^ZONE-[A-Z0-9]{8}$`);
- rate-limit por `zone_id`+IP (tabla `zone_claim_attempts` con ventana) — mantiene 36⁸ como fuerza;
- `claim_zone_id` deja de tocar `public_key` (prohibir rotación vía claim);
- cliente: `ensureAuth` NO sube una clave nueva; reintentos exponenciales.
- ⚠️ El robo por conocimiento del ZONE-ID sigue siendo posible (mitigado por rate-limit); coincide con el modelo de amenazas actual.

**Opción 2 — Posesión por firma Ed25519 + códigos de recuperación (seguro, cambio de UX):**
- El `id` queda atado al dispositivo cuya clave privada creó la fila.
- Transferir a otro dispositivo exige **firma del propietario actual** sobre un challenge, o **códigos de recuperación** emitidos en la creación (guardados en Secure Storage, no en el servidor salvo hash).
- Teclear solo el ZONE-ID ya no transfiere → UX "solicitar aprobación al dueño / usar código de recuperación".
- Supabase: `pgsodium.crypto_sign_verify_ed25519` en `claim_zone_id`/`transfer_zone_id`; `update_public_key` firmado con la clave vieja.

**Opción 3 — HIbrida por fases (recomendada):**
- **Fase A (ahora, shippable):** Opción 1 + registro de claims + `claim_zone_id` idéntica al deploy (sin público_key) + endpoint firmado `update_public_key` (firma con clave vieja; recuperación vía código para re-instalación).
- **Fase B (siguiente iteración):** codes de recuperación + transfer firmado (Opción 2).

### Migración necesaria (esquema propuesto, consolidada en una migración nueva)
```sql
-- REVOKE ANON siempre:
REVOKE EXECUTE ON FUNCTION public.claim_zone_id(text)              FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.claim_zone_id(text, text)        FROM PUBLIC, anon;
DROP FUNCTION IF EXISTS public.claim_zone_id(text);                -- versión 1-arg obsoleta
GRANT EXECUTE ON FUNCTION public.claim_zone_id(text, text) TO authenticated;

-- (según decisión) tabla de rate-limit + función endurecida con formato/possesión...
```
⚠️ **No ejecutar** `supabase_emergency_recovery.sql` ni `supabase_migration_fix.sql` a ciegas
(hay GRANT anon y un DELETE destructivo). Consolidar solo lo necesario en una migración nueva.

## 5. Alternativas consideradas

| Alternativa | Veredicto |
|---|---|
| Cambiar solo GRANT (quitamos anon) | Insuficiente: sigue sin prueba de posesión y con rotación de public_key |
| Aplicar `emergency_recovery.sql` tal cual | ❌ Mantiene GRANT anon y escritura de public_key sin prueba |
| Aplicar `migration_fix.sql` tal cual | ❌ DELETE destructivo (líneas 14-16) |
| Borrar zona → re-registro forzoso por sesión | Cambia el modelo de login entero; rompe UX y ZONE-ID existentes |
| Dejar como está | ❌ P0 confirmado |

## 6. Pruebas necesarias

- SQL/pgTAP: (1) `anon` → 403; (2) `authenticated` con ZONE-ID inexistente → no-op/404;
  (3) rate-limit dispara tras N intentos; (4) `claim` NO altera `public_key`;
  (5) rotación de `public_key` requiere firma/código válidos, si no → sin cambios;
  (6) claim legítimo mueve `id`, conserva perfil y es idempotente; (7) `verify_zone_id`
  deja de ser oráculo (devuelve solo mínimo tras prueba).
- Cliente (`flutter test`): integración simulada de login en 2º dispositivo
  (opciones 1/3: claim OK sin rotar clave; opción 2: fallo sin firma/código + flujo recuperación).

## 7. Información que falta (REQUIRES_REMOTE_VERIFICATION)

1. **Estado remoto real de Supabase** (NO verificable desde el repo):
   - ¿Qué firma tiene `claim_zone_id` en remoto (1-arg, 2-arg emergencia, o migration_fix)?
   - ¿Quién tiene GRANT en remoto (anon vigente?)? ¿Está aplicado `verify_zone_id` anon?
   - Método de verificación: `supabase db diff` (repositorio local enlazado) o pegar
     `\df public.claim_zone_id` + policies desde el SQL Editor.
2. **Decisión de diseño** (Opción 1 / 2 / 3) y UX del flujo de transferencia.
3. **Presupuesto de cambios** en misma migración de Z-103 (`verify_zone_id`) — interdependiente.
4. **Infraestructura de rate-limit**: ¿aceptable incluir tabla `zone_claim_attempts`?

---

## 8. Z-002 — Exposición RLS de `users` · Decisiones CTO (2026-09-23)

**Hallazgo:** la policy `"Ver perfiles públicos"` (`FOR SELECT TO authenticated USING (is_shadowbanned = FALSE)`)
expone TODO el perfil de cualquier usuario autenticado (handles privados, galería, `public_key`).
El filtrado de visibilidad vivía solo en el cliente.

**Decisiones tomadas:**
1. **Visibilidad avatar/galería:** **A. ESTRICTO SERVER-SIDE.** `avatar_url` y `gallery_photos` se devuelven
   NULL en `v_profile` cuando `avatar_is_public = false`; se elimina el bypass por conexión mesh en
   `public_profile_sheet.dart` (ya no se muestra avatar/galería "privados" por estado de conexión).
2. **Mecanismo server-side:** **VISTA `public.v_profile`** como ÚNICO camino de lectura de terceros +
   `claim_zone_id` **devuelve el perfil completo (jsonb)** al reclamar (el login no vuelve a releer `users`).
   Se descartó "solo RPC `get_public_profile`" (menos superficie PostgREST pero obliga a migrar todas las queries a RPC).
3. RLS `users` SELECT → self-scoped (`auth.uid() = id`). La vista usa semántica de dueño (security definer)
   y aplica sus propios filtros (shadowban, bloqueos bidireccionales, gating de privacidad) — NO `security_invoker`
   (re-aplicaría el RLS self-scoped y rompería el radar).

**Aprobado implícitamente (acotado en el mismo lote):**
- `users.updated_at` (columna; el remoto YA la tiene — solo se alinea schema/deploy). Sin trigger por ahora (Z-109).
- Cliente: `updateProfile` escribe `updated_at` en vez del `updatedAt` camelCase (que daba 400 contra el remoto).
- `verify_zone_id` gating de `avatar_url` por `avatar_is_public` (coherencia con A).

**Pendientes nuevos para revisión del CTO (NO aplicadas en este lote):**
1. ~~**Aplicar en remoto** `secure_claim_zone_id.sql` (Fase 1.2) y luego `z002_profile_visibility.sql` (Fase 1.3)~~
   ~~vía **SQL Editor** (recomendado; sin Docker local no funciona `db diff`) o `supabase db push` con la password de la DB.~~
   **✅ APLICADO + VERIFICADO en remoto (2026-09-23)** vía **Management API con PAT** (mismo motor que el SQL Editor). Detalle abajo.
2. **Drift SOLO-REMOTO:** `get_active_users_for_radar`, `update_bt_activity`, `get_radar_stats` existen en producción
   pero no tienen definición canónica en el repo → requiere dump (`\df` + bodies) para consolidarlas (Z-109).
3. **`bio`: no existe en remoto** — columna a añadir SOLO cuando la feature de bio avance (pull-sync ya no la consulta).
4. **Z-104 (`resolve_bt_token`):** sigue con GRANT anon y devuelve `avatar_url` sin gating de `avatar_is_public`.
   No se toca en este lote (batch propio); asignar prioridad (es el próximo conductor de fugas).
5. **Z-111 (`profiles` bucket público):** sigue abierto (avatares "privados" descargables por URL). Depende del gating de Z-002 ya implementado.

**Incidente de encoding durante la aplicación remota (resuelto, requiere conocimiento del CTO):**
- El 1º intento de aplicar Z-002 envió la migración con **doble codificación** (Windows PowerShell 5.1 usa
  ANSI/cp1252 en `Get-Content` para archivos sin BOM → `ú` se convirtió en `Ãº`, y así con todos los acentos).
  Consecuencia: `DROP POLICY IF EXISTS "Ver perfiles públicos"` **no impactó** (no-op) → la policy histórica
  siguió viva exponiendo todas las columnas de perfiles ajenos a `authenticated`, y los textos de RAISE de
  claim/verify quedaron mojibake en la DB.
- **Corrección aplicada (bajo supervisión, transacción atómica):**
  1. Aplicador con **lectura UTF-8 estricto** (`[IO.File]::ReadAllText`, `--data-binary`, sin BOM).
  2. Migración Z-002 endurecida: bloque `DO` que elimina **cualquier política SELECT ajena** en `users`
     salvo la self-scoped (`auth.uid() = id`) — robusto ante variantes de nombre/normalización Unicode —
     + `REVOKE ALL ON v_profile FROM authenticated` (default privileges de Supabase otorgaban `arwdDxtm` a objetos nuevos;
     queda solo `SELECT`) + `DROP FUNCTION claim_zone_id(text)` previo al cambio void→jsonb (Postgres 42P13).
  3. Re-aplicación OK: self-scope verificado (authenticated sin sesión ve 0 filas ajenas), mojibake sanado
     (hex del RAISE = `73657369c3b36e20`).

---

## Estado

**✔️ DECISIÓN CTO REGISTRADA (Opción 3). Fase A implementada y verificada localmente
(Z-001 + Z-103). ✅ REMOTE_APPLIED + VERIFIED (2026-09-23): migración 1.2 aplicada en
transacción atómica vía Management API con PAT. ACL finales sin anon; 2-arg dropeada;
oráculo verify cerrado.**

- Migración: `supabase_migrations/secure_claim_zone_id.sql` (idempotente).
- Baselines actualizados: `supabase_schema.sql`, `supabase_deploy.sql`.
- Cliente: `lib/services/zone_id_service.dart` (sin `p_public_key`; sin rotación silenciosa;
  preserva `public_key` archivada; `isValidZoneIdFormat` fail-fast) + `test/zone_id_format_test.dart`.
- Verificación local: `flutter test` 5/5, `flutter analyze` 0 nuevos.
- Verificación remota: pruebas de rol en vivo (anon→42501 en claim/verify; doble compuerta OK).
  Detalle en `PHASE_1_PROGRESS.md` (FASE 1.2).

**✔️ DECISIÓN CTO Z-002 REGISTRADA (A estricto + vista `v_profile`). ✅ REMOTE_APPLIED + VERIFIED
(2026-09-23): migración 1.3 aplicada y verificada tras corregir un incidente de encoding (ver §8).**

- Migración: `supabase_migrations/z002_profile_visibility.sql` (idempotente, builds sobre 1.2;
  enmendada con DO-block de limpieza de policies, REVOKE de default privileges en v_profile y
  DROP previo a cambio de tipo de retorno).
- Baselines: `supabase_schema.sql`, `supabase_deploy.sql`; cliente: `zone_id_service`,
  `supabase_service` (lecturas de terceros → `v_profile`), `public_profile_sheet` (sin bypass mesh).
- Verificación local: `flutter test` 5/5, `flutter analyze` 0 nuevos.
- Verificación remota: self-scope negativo (0 filas ajenas), 3 policies self-scoped, v_profile
  SELECT-only, mojibake sanado. Pendientes restantes en la sección 8.

Archivos afectados por la Fase B futura: `lib/services/zone_id_service.dart`,
`supabase_migrations/<nueva>` (auth_public_key + challenge + recovery), docs.

---

## 9. Z-003 — Mesh en claro · Solicitud de DECISIÓN de diseño (FASE 1.4, 2026-09-23)

> Regla del protocolo: cualquier cambio que afecte criptografía o protocolo mesh NO se implementa
> sin decisión explícita del CTO. **DECISIÓN TOMADA 2026-09-23 (CTO):** Opción 1 fail-closed;
> **IMPLEMENTADO en commit `fd1e60d`** (todo lo de abajo es el diseño según fue aprobado).

**Evidencia (código, solo lectura — `lib/services/nearby_service.dart`):**
- `sendMeshMessage` (1008-1055): construye el paquete con `'text': <texto>` y `'isEncrypted': false`
  (1016-1018) **antes** de intentar cifrar. Si no hay `sessionKey` → va tal cual; si el cifrado lanza →
  el `catch` (1036-1038) solo loguea y **el paquete sigue saliendo en claro** por flood/relay.
- `_handleMeshMessage` (1057-1111): relay a saltos intermedios aunque no sea el destino → en la
  práctica un mensaje en claro es visible en **toda la malla**.
- `_processIncomingMeshMessage` (1113-1156): `isEncrypted == false` → texto directo (1118-1119).
- La llave de sesión **solo se deriva al recibir** `profile_exchange` con la clave pública del peer
  (`_handleProfileExchange` 905-917). Sin intercambio de perfil previo → NO hay llave → hoy se envía en claro.
- Primitivas existentes (reutilizar, NO criptografía nueva): X25519 ECDH (`generateKeyPair`,
  `deriveSessionKey`), AEAD `encryptMessage`/`decryptMessage` (SecretKey + nonce + mac), Secure Storage.

**Opciones de diseño (pendiente decisión CTO):**

- **Opción 1 — FAIL-CLOSED mínimo (recomendada para FASE 1.4):**
  - Emisor: si no hay `sessionKey` o el cifrado falla → **NO enviar**; emitir evento
    "clave no disponible" y opcionalmente encolar el mensaje localmente para reintento
    tras derivar llave. Nada en claro toca el cable.
  - Relay/receptor: `_handleMeshMessage` reenvía solo paquetes `isEncrypted == true`
    (si no, descarta y loguea); el receptor mantiene el placeholder actual sin llave.
  - Cero cripto nuevo. En la práctica el radar/descubrimiento ya intercambia perfiles →
    los pares visibles tendrán llave derivada.
- **Opción 2 — Bootstrap de llave bajo demanda:** si no hay llave, el emisor envía su
  `profile_exchange` y pide el perfil del destino antes de cifrar. Más fluido pero requiere
  perfil del otro (que solo existe si se vieron antes → no resuelve el primer contacto
  con desconocidos y añade mensajes/superficie).
- **Opción 3 — Handshake completo (evolución con Fase B de Z-001):** autenticar endpoints
  con challenge/nonce firmado por identidad Ed25519 (las claves actuales X25519 no firman →
  depende de la identidad de firma de la Fase B) + llave derivada por par + solo cifrado.
  Correcto a medio plazo; NO bloquear FASE 1.4 con esto.

**Decisiones pedidas al CTO — RESUELTAS 2026-09-23:**
1. ¿Opción 1 para FASE 1.4? → **SÍ** (fail-closed, sin cripto nuevo, reutilizando X25519+AEAD existentes).
2. UX en emisor sin llave: ¿encolar con reintento automático o descartar con aviso al usuario? → **ENCOLAR**
   con reintento automático al derivarse la llave (cola local con tope 200 + eviction FIFO + stream de estado).
3. ¿El relay debe descartar paquetes no cifrados (`isEncrypted != true`) incluso de peers conocidos? → **SÍ**,
   descarta siempre (antes de dedup y de propagar), con log de warning.
4. ¿Incluir en el mismo lote la prueba unitaria? → **SÍ** — `test/mesh_policy_test.dart` (7 casos fail-closed,
   12/12 tests verdes; `flutter analyze` 0 errores).

**Resolución de implementación (commit `fd1e60d`):** `MeshPolicy` puro en `lib/services/mesh_policy.dart`
(`decideSend`/`decideRelay`/`ciphertextPacket` — API que no acepta texto en claro por construcción);
`sendMeshMessage` encola en vez de emitir en claro; `_handleMeshMessage` descarta `isEncrypted != true`;
`_processIncomingMeshMessage` guard previo; flush de la cola en `_handleProfileExchange` tras derivar llave.
**Nota de convivencia con WIP:** el archivo tenía vuestro WIP (llave vía Secure Storage, dedup, pseudónimos
OFFLINE) en exactamente las mismas funciones → se aplicó stash→implementar sobre HEAD→pop con resolución
de 2 conflictos; vuestro WIP quedó intacto y SIN commitear en el working tree.

## 10. Hallazgos nuevos del dump remoto (2026-09-23) — RPCs drift con GRANT anon

> Snapshot completo read-only en `docs/REMOTE_DRIFT_SNAPSHOT_2026-09-23.sql` (Z-109, consolidación pendiente).

**Funciones SOLO-REMOTO con `GRANT EXECUTE TO anon` y SECURITY DEFINER sin gate de sesión:**
1. **`get_active_users_for_radar(p_limit default 1000)`** — devuelve `id, zone_id, display_name,
   avatar_url, public_key, stealth_mode` de usuarios activos 24 h. **El anon puede enumerar usuarios
   activos y sus claves públicas por PostgREST** (fuga nueva; además expone `avatar_url` sin gating
   de `avatar_is_public`). → Requiere batch propio (REVOKE anon + gate + gating + consolida en canon).
2. **`get_radar_stats()`** — métricas agregadas (total_users, activos 24 h, tokens, encuentros) → fuga P2.
3. **`refresh_active_users_cache()`** — anon puede disparar `REFRESH MATERIALIZED VIEW CONCURRENTLY`
   → abuso/DoS del backend.
4. **`auto_cleanup_tokens()`** — anon puede ejecutar el cleanup → innecesario; REVOKE.
5. **`update_bt_activity()`** — usa `auth.uid()` (no filtra a anon) pero GRANT anon innecesario; REVOKE.
6. **`resolve_bt_token(p_token)`** — GRANT anon (Z-104, ya documentado; pendiente).
7. **`update_users_updated_at()`** (trigger function) — GRANT `PUBLIC`; REVOKE PUBLIC (defensivo).

**Trigger remoto confirmado:** `users_updated_at_trigger` EXISTE en remoto sobre `users`
(`update_users_updated_at()` BEFORE UPDATE) → Z-205/Z-109 parcialmente cubierto; baselines
`supabase_schema.sql`/`deploy.sql` alineados con la definición (commit de esta tanda).
**`updated_at` en el SQL Editor creado por postgres hereda default privileges; los baselines ya lo cubren.**

---

### Z-109 · DECISIÓN CTO APROBADA (2026-09-23, batch completo) — ejecutada en remoto

> **Aprobación registrada antes de codificar:** el batch completo A–F (ver puntos 1–5 y 7 de arriba)
> fue aprobado por el CTO con estos acuerdos explícitos:
> 1. **A `get_active_users_for_radar`:** REVOKE `anon/PUBLIC` → solo `authenticated`+`service_role`;
>    reescrita como **`SECURITY INVOKER` sobre `v_profile`** (+ filtro `stealth_mode=false` del
>    original) → hereda TODO el gating server-side de Z-002 (avatar_is_public, shadowban, bloqueos
>    mutuos). La app ya usa exactamente esa consulta como fallback → cero breakage esperado.
> 2. **B `get_radar_stats`:** REVOKE anon/PUBLIC + gate `auth.uid() IS NULL → NULL`; `authenticated`+`service_role`.
> 3. **C `refresh_active_users_cache` y D `auto_cleanup_tokens`:** solo `service_role` (mantenimiento).
> 4. **E `update_bt_activity`:** REVOKE anon/PUBLIC; `authenticated`+`service_role`.
> 5. **F `update_users_updated_at`:** REVOKE `PUBLIC` (defensivo; los triggers no dependen de grants).
> 6. **G `resolve_bt_token`:** SE MANTIENE `anon` **por diseño** (radar bilateral; tokens UUIDv4 =
>    122 bits aleatorios → fuerza bruta infeasible). Item futuro: rate-limit (Z-104).
> 7. **Consolidación en canon:** versiones corregidas de A–F + `rls_auto_enable` añadidas a
>    `supabase_schema.sql`/`supabase_deploy.sql` (tras la creación de `v_profile`), y REVOKE
>    alineado en `update_users_updated_at`.
>
> Migración: `supabase_migrations/z109_rpc_anon_revoke.sql` (aplicada en remoto en transacción
> atómica con verificación en-transacción). Evidencia remota y conteos en `PHASE_1_PROGRESS.md`.