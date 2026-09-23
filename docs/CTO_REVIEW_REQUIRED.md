# CTO_REVIEW_REQUIRED — Decisión de diseño requerida · ZONE

> **Regla aplicada (FASE 1, §2/§14):** cualquier cambio que afecte autenticación,
> autorización, RLS, SECURITY DEFINER, esquema remoto de Supabase o protocolo de
> mensajería **no se implementa sin decisión explícita del CTO**.
>
> **Hallazgo:** Z-001 — `claim_zone_id` inseguro.
> **Fecha:** 2026-09-22 · **Estado:** ✔️ DECIDIDO (Opción 3) → **Fase A implementada localmente** · Fase B pendiente de diseño.

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

## Estado

**✔️ DECISIÓN CTO REGISTRADA (Opción 3). Fase A implementada y verificada localmente
(Z-001 + Z-103). Estado remoto: REQUIRES_REMOTE_VERIFICATION.**

- Migración: `supabase_migrations/secure_claim_zone_id.sql` (idempotente).
- Baselines actualizados: `supabase_schema.sql`, `supabase_deploy.sql`.
- Cliente: `lib/services/zone_id_service.dart` (sin `p_public_key`; sin rotación silenciosa;
  preserva `public_key` archivada; `isValidZoneIdFormat` fail-fast) + `test/zone_id_format_test.dart`.
- Verificación local: `flutter test` 5/5, `flutter analyze` 0 nuevos.
- Verificación remota pendiente: aplicar migración vía supabase CLI (se requieren
  `SUPABASE_ACCESS_TOKEN` y project ref del CTO) y ejecutar las 7 pruebas SQL del archivo
  (anon → 403, formato, rate-limit, claim no altera public_key, idempotencia, sin oráculo).

Archivos afectados por la Fase B futura: `lib/services/zone_id_service.dart`,
`supabase_migrations/<nueva>` (auth_public_key + challenge + recovery), docs.