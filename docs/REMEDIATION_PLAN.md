# REMEDIATION_PLAN — Plan de Corrección FASE 1 (PROPUESTA) · ZONE

> **Estado: AUTORIZADA (FASE 1).** Orden obligatorio de ejecución autorizado por el CTO:
> Z-006 → Z-001 → Z-002 → Z-003 → Z-007 (Fase 1.1-1.5) → REPORTE `PHASE_1_COMPLETION_REPORT.md` antes de continuar con P1.
> Progreso detallado en `PHASE_1_PROGRESS.md`.

---

## Fase 1.1 — Desbloqueo funcional y seguridad crítica (P0)

| # | Bug | Acción | Depende de | Prueba de éxito |
|---|-----|--------|------------|-----------------|
| 1 | **Z-006** | ✅ **HECHO (FASE 1.1):** migrado a `--dart-define`/`String.fromEnvironment` (nuevo `lib/utils/env_config.dart`) con fallback dev tolerante; sin `!`; arranque degradable si falta config. | — | ✅ `flutter test` pasa y el log ya no muestra `[Startup] ERROR CRÍTICO`; ✅ sonda con `--dart-define-from-file=.env` confirma inyección; ⏳ falta build release en dispositivo |
| 2 | **Z-001** | ✅ **FASE A HECHA (FASE 1.2):** REVOKE anon; claim solo authenticated con formato+rate-limit (`zone_claim_attempts`), sin tocar `public_key`; cliente sin `p_public_key` y sin rotación silenciosa (`zone_id_service.dart`); fail-fast de formato. **FASE B pendiente de CTO:** identidad Ed25519 + códigos de recuperación + `update_public_key` firmado (las claves actuales son X25519 y no firman). **✅ REMOTO APLICADO + VERIFICADO (2026-09-23):** migración 1.2 en tx atómica vía Management API; ACL finales sin anon; variante 2-arg DROPEADA; pruebas de rol en vivo (anon→42501). | Z-103, Z-207 | ✅ `flutter test` 5/5; ✅ analyze 0 nuevos; SQL: 7 pruebas en `secure_claim_zone_id.sql`. Remoto: ✅ REMOTE_VERIFIED |
| 3 | **Z-002** | ✅ **HECHO (FASE 1.3):** RLS `users` SELECT self-scoped + vista `public.v_profile` (owner, filtra shadowban/bloqueos bidireccionales, NULIFICA avatar/galería si `avatar_is_public=false` y handles si `*_visible=false` server-side) como único camino de terceros; `claim_zone_id` → jsonb (perfil completo al reclamar, login sin releer `users`); cliente: 4 lecturas → `v_profile`, sin bypass mesh en perfil público. **Decisión CTO:** A estricto server-side + vista (no RPC). **✅ REMOTO APLICADO + VERIFICADO (2026-09-23):** tx atómica (tras corregir incidente de encoding, ver `CTO_REVIEW_REQUIRED §8`); self-scope negativo (0 filas ajenas), 3 policies self-scoped (`"Ver perfiles públicos"` ELIMINADA), v_profile SELECT-only, mojibake sanado. | Z-001 (misma migración) | ✅ `flutter test` 5/5; ✅ analyze 0 nuevos; SQL: 8 pruebas en `z002_profile_visibility.sql`. Remoto: ✅ REMOTE_VERIFIED |
| 4 | **Z-003** | Mesh fail-closed: prohibir envío sin llave de sesión; flujo de solicitud/derivación de llave previo. | Z-004, Z-101 | Unit: `sendMeshMessage` sin llave no transmite |
| 5 | **Z-004** | Handshake firmado Ed25519 + challenge; atadura endpoint↔identidad; rechazo de perfiles/paquetes no firmados. | — | Peer con `source` falsificado → rechazado |
| 6 | **Z-005** | `msgId` único (UUIDv4/HMAC) + dedup LRU con TTL (sin `clear()` global). | — | 2 mensajes en el mismo ms → distintos; replay rechazado tras TTL |
| 7 | **Z-007** | Escribir SIEMPRE en `LocalPendingMessage`/Isar en `_sendMessage`; cola offline que drena en `SyncService`; abrir chat con merge Isar+server; UI "sin conexión, en cola". | Z-107 | Enviar sin red → mensaje persiste; reabrir chat → presente; recuperación de red → sincroniza sin duplicar |
| 8 | **Z-008** | Quitar `setPremium(true)` directo del botón; integrar flujo de pago verificado server-side (Play/Store + Edge Function) o deshabilitar premium hasta implementar. | Backend | E2E sandbox: sin recibo válido la feature no se activa |

## Fase 1.2 — Seguridad de backend y plataforma (P0/P1)

| # | Bug | Acción | Depende de | Prueba |
|---|-----|--------|-----------|--------|
| 9 | **Z-104** | `resolve_bt_token`: GRANT solo `authenticated`; marcar/eliminar token tras resolución (idempotente); expiración corta. | — | 2ª resolución del mismo token → NULL |
| 10 | **Z-103** | ✅ **HECHO (FASE 1.2, mismo lote):** `verify_zone_id` solo `authenticated`, formato+rate-limit, sin exponer `id`. **✅ REMOTO APLICADO + VERIFICADO (2026-09-23):** oráculo cerrado; anon → 42501 en vivo; payload final `{exists, display_name, avatar_url}` sin `id`/`zone_id`. | Z-001 | ✅ `flutter analyze` 0 nuevos; SQL pruebas 1/7 migración `secure_claim_zone_id.sql`. Remoto: ✅ REMOTE_VERIFIED |
| 11 | **Z-105** | Trackear y aplicar `add_message_delivery_status.sql`; añadir policy UPDATE para `messages`; invocar receipts desde el chat; RPC `mark_messages_read` con SECURITY DEFINER acotado al lector. | Z-206 | B lee → A ve "leído" |
| 12 | **Z-106** | Aplicar `supabase_delete_fix.sql` (policy DELETE matches) y consolidarlo en deploy. | — | Eliminar match funciona y persiste |
| 13 | **Z-107** | IDs locales estables (`client_id`) + upsert idempotente en flush; implementar pull de mensajes por cursor con merge LWW. | Z-007, Z-205 | Sin duplicados tras reintentos; 2º dispositivo ve mensajes |
| 14 | **Z-108** | ✅ **PARCIAL (FASE 1.3):** cliente `updateProfile` escribe `updated_at` (snake_case, columna remota confirmada) en vez de `updatedAt` — **✅ remoto alineado con la migración Z-002**; falta trigger multi-device → Z-205/Z-109. | Z-109 | Editar perfil → persiste; refresco → igual |
| 15 | **Z-109** | ✅ **PARCIAL (FASE 1.3):** `updated_at` consolidado en schema/deploy — **✅ remoto alineado**. Pendiente: **RPCs radar/actividad son drift SOLO-REMOTO** (sin definición canónica; dump pendiente) y trigger updated_at. | Z-205 | Funciones existen; `getActiveUsersForRadar` devuelve datos |
| 16 | **Z-111** | Bucket `profiles` privado + URLs firmadas por flag de visibilidad; migrar avatares. | Z-002 | URL directa sin firma → 403 |
| 17 | **Z-112** | Radar: pull con TTL/caché y límites menores; painter memoizado; unificar endpoints (emitir `CACHE:`/`GLOBAL:` o eliminar rama Z-208). | Z-109 | DevTools: menos repaints y tráfico |
| 18 | **Z-110** | Push (FCM/APNs) con Edge Function; Darwin settings iOS; gestión de listener por lifecycle (parar al background). | Backend | Notificación push con app cerrada |
| 19 | **Z-101** | Ratchet/rotación de sesión; KDF con contexto/contador; corrección de docs FS. | — | Vectors criptográficos; compromiso no descifra historial |
| 20 | **Z-102** | Huella de identidad (safety number) en UI; aviso de cambio de claves; opción de re-autenticación. | Z-101 | Reinstala simulado → aviso visible y control |

## Fase 1.3 — Calidad y estabilidad (P2/P3)

| # | Bug | Acción | Prueba |
|---|-----|--------|--------|
| 21 | **Z-201 / Z-303** | Guards de `mounted`; reemplazar prints; `flutter analyze` 0 issues. | `flutter analyze` |
| 22 | **Z-202 / Z-308** | Errores tipados y mapeados a textos UX; revisar catches silenciosos en rutas críticas. | Revisión + snackbars correctos |
| 23 | **Z-203** | Eliminar credenciales hardcodeadas; mover el load-test a fixture/env; `git grep` sin URL/keys. | grep limpio |
| 24 | **Z-204** | Filtro BLE por UUID/servicio propio; estado pausado en background. | Scan solo reacciona a app |
| 25 | **Z-206** | Policy UPDATE/DELETE para `messages` (participantes). | SQL tests |
| 26 | **Z-205** | ✅ **PARCIAL (FASE 1.3):** columna `updated_at` añadida a schema/deploy (**✅ remoto ya alineado**; columna existía y la migración hace IF NOT EXISTS). Pendiente: trigger base. | Sync LWW funciona |
| 27 | **Z-207** | Quitar auto-claim del arranque; claim explícito y con prueba de posesión. | Sin login no se adueña ID |
| 28 | **Z-208** | Implementar emisión de endpoints `CACHE:`/`GLOBAL:` o eliminar la rama. | Radar muestra correcto |
| 29 | **Z-209** | Limpiar artefactos y ampliar `.gitignore` (`hs_err_pid*`, `replay_pid*`, `*.apk`…). | `git status` limpio |
| 30 | **Z-301** | Suite de tests por servicio (cripto vectors, cola offline, sync, RLS) + widget de flujos; CI `analyze+test`. | Cobertura >60% |
| 31 | **Z-302** | Plan de upgrades priorizado (supabase, secure_storage, notifications) validando con tests. | `flutter pub outdated` reducido; suite verde |
| 32 | **Z-304** | Corregir README/SECURITY/PRIVACY a lenguaje veraz; condicionar afirmaciones a FASE 1+. | Revisión legal |
| 33 | **Z-305** | Migrar configuración a `--dart-define`/`fromEnvironment` con defaults; dotenv solo dev. | Build release sin `.env` |
| 34 | **Z-306** | Mínimo necesario de permisos Android/iOS. | Revisión tiendas |
| 35 | **Z-307** | Eliminar código muerto y comentarios que mienten. | Lint dead_code |

---

## Estimación relativa (esfuerzo en 1/2/3/5)

- **Pequeño (1):** Z-103, Z-201, Z-203, Z-209, Z-303, Z-306, Z-307
- **Medio (2):** Z-005, Z-006, Z-104, Z-108, Z-205, Z-206, Z-207, Z-208, Z-304, Z-305
- **Grande (3):** Z-002, Z-003, Z-004, Z-007, Z-105, Z-106, Z-107, Z-109, Z-112, Z-202, Z-204, Z-308, Z-301, Z-302
- **Épico (5):** Z-001 (rediseño identidad), Z-101 (ratchet), Z-102 (safety numbers), Z-110 (push), Z-111 (storage), Z-008 (IAP)

## Secuencia sugerida de primer sprint (bloqueante mínimo)

> Z-006 → Z-001 → Z-002 → Z-007 → Z-003/Z-004/Z-005 → Z-105/Z-106 → validar con Z-301.

---

**Decisión requerida del dueño antes de FASE 1:**
1. ¿Aprobamos el plan? ¿Cambios de alcance/prioridad?
2. ¿Tenemos acceso a la instancia Supabase remota para `supabase db diff` y aplicar `supabase_deploy.sql` consolidado (Z-105/106/109)?
3. ¿Se autoriza corregir también los cambios locales sin commitear del working tree (pubspec, servicios, modelos), o preservamos su contenido y rebasamos encima?
4. ¿Prioridad: seguridad primero, o feature primero (p.ej. push/IAP)?