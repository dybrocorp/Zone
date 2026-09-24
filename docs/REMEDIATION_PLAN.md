# REMEDIATION_PLAN — Plan de Corrección FASE 1 (PROPUESTA) · ZONE

> **Estado: AUTORIZADA (FASE 1).** Orden obligatorio de ejecución autorizado por el CTO:
> Z-006 → Z-001 → Z-002 → Z-003 → Z-007 (Fase 1.1-1.5) → REPORTE `PHASE_1_COMPLETION_REPORT.md` antes de continuar con P1.
> FASE 1.6 (2026-09-23): batch mecánico+SQL sin decisión criptográfica — Z-005, Z-106, Z-206, Z-207, Z-201/Z-303, Z-203, Z-209, Z-307 (parcial).
> FASE 1.7 (2026-09-23): batch seguro sin tocar criptografía — Z-104 (revoke anon resolve_bt_token, remoto verificado), Z-204 (filtro BLE), Z-308 (catchers), Z-105 reste (cableado markMessageDelivered).
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
| 6 | **Z-005** | ✅ **HECHO (FASE 1.6):** `msgId` = **UUID v4** en `MeshPolicy.ciphertextPacket` (sin colisiones); dedup **`MeshDedup` LRU + TTL 15 min** (clase pura, sin `clear()` global, eviction de UNA entrada) en `mesh_policy.dart`/`nearby_service.dart`; 6 tests (unicidad, duplicado en ventana, LRU no pierde nuevas, replay post-TTL). | — | ✅ `flutter analyze` 0 issues; ✅ `flutter test` 18/18 (test `Z-005: msgId es UUID v4 único` + grupo `MeshDedup`) |
| 7 | **Z-007** | Escribir SIEMPRE en `LocalPendingMessage`/Isar en `_sendMessage`; cola offline que drena en `SyncService`; abrir chat con merge Isar+server; UI "sin conexión, en cola". | Z-107 | Enviar sin red → mensaje persiste; reabrir chat → presente; recuperación de red → sincroniza sin duplicar |
| 8 | **Z-008** | Quitar `setPremium(true)` directo del botón; integrar flujo de pago verificado server-side (Play/Store + Edge Function) o deshabilitar premium hasta implementar. | Backend | E2E sandbox: sin recibo válido la feature no se activa |

## Fase 1.2 — Seguridad de backend y plataforma (P0/P1)

| # | Bug | Acción | Depende de | Prueba |
|---|-----|--------|-----------|--------|
| 9 | **Z-104** | ✅ **HECHO (FASE 1.7):** `resolve_bt_token` pasa a SOLO `authenticated` — **REVOKE EXECUTE a anon/PUBLIC aplicado en remoto** (`z104_bt_token_hardening.sql`, tx atómica). Decisión CTO: **NO single-use estricto** (cada vecino resuelve el MISMO token compartido → lo rompería); mitigación = revoke anon + TTL 10 min + rotación 5 min. | — | ✅ Remoto V1–V4: anon `has_function_privilege=false`; anon call → **42501**; authenticated/postgres OK; anon SELECT → 0 filas; producción intacta (2/1/2) |
| 10 | **Z-103** | ✅ **HECHO (FASE 1.2, mismo lote):** `verify_zone_id` solo `authenticated`, formato+rate-limit, sin exponer `id`. **✅ REMOTO APLICADO + VERIFICADO (2026-09-23):** oráculo cerrado; anon → 42501 en vivo; payload final `{exists, display_name, avatar_url}` sin `id`/`zone_id`. | Z-001 | ✅ `flutter analyze` 0 nuevos; SQL pruebas 1/7 migración `secure_claim_zone_id.sql`. Remoto: ✅ REMOTE_VERIFIED |
| 11 | **Z-105** | ✅ **PARCIAL→HECHO (FASE 1.5 + 1.7):** columnas + RPC `mark_messages_read`/`mark_message_delivered` via `z007_offline_chat.sql` (canon, remoto verificado); policy UPDATE/DELETE `messages` via Z-206 (FASE 1.6); **`markAllMessagesRead` cableado al abrir chat (1.5) y `markMessageDelivered` cableado al receptor en `chat_screen.dart` (1.7)**. Pendiente menor: mostrar "Entregado/Leído" en el remitente (UI tick) y receipts sobre mensajes mesh directos. | Z-206 | B abre chat → A ve leído (RPC verificado); delivered_on_escucha cableado |
| 12 | **Z-106** | ✅ **HECHO (FASE 1.6):** policy DELETE para participantes consolidada en `supabase_migrations/z106_z206_policies.sql` (canon) + `supabase_deploy.sql`. **✅ REMOTO APLICADO + VERIFICADO (2026-09-23):** `"Eliminar propio match"` FOR DELETE solo `authenticated`; policy duplicada del parche suelto dropeada en remoto; anon bloqueado; mensajes intactos. | — | ✅ Eliminar match funciona y persiste; remoto: pg_policies `{authenticated}` |
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
| 21 | **Z-201 / Z-303** | ✅ **HECHO (FASE 1.6):** guards de `mounted` correctos (chats_list 228, donations 46); prints → `stdout.writeln` en scripts/tools. | ✅ `flutter analyze` = **0 issues** |
| 22 | **Z-202 / Z-308** | ✅ **Z-308 HECHO (FASE 1.7 - alcance acotado):** catchers `catch (_) {}` silenciosos → log con mensaje (env_config, premium_service, zone_id_service, nearby_service, chat_screen). Pendiente: mapeo de errores a textos UX (Z-202) y catchers amplios del resto (Z-308 liste larga) en fase de UX. | Revisión + snackbars correctos |
| 23 | **Z-203** | ✅ **HECHO (FASE 1.6):** credenciales eliminadas de `test/load_test_simulator.dart`; lee `SUPABASE_URL`/`SUPABASE_ANON_KEY` de entorno y aborta si faltan. | ✅ `git grep -i "sb_publishable|supabaseUrl" test/` sin hits |
| 24 | **Z-204** | ✅ **HECHO (FASE 1.7):** `ble_proximity_service.dart` filtra por nombre de token propio (UUID v4 o `OFFLINE:`+pseudónimo 32); dispositivos ajenos NO se registran. Queda para fase de energía: estados paused en background. | Scan solo reacciona a app |
| 25 | **Z-206** | ✅ **HECHO (FASE 1.6):** policies UPDATE/DELETE en `messages` para participantes de match aceptado (`z106_z206_policies.sql` + baselines). **✅ REMOTO APLICADO + VERIFICADO (2026-09-23):** UPDATE/DELETE nuevas con roles `{authenticated}`; anon bloqueado. | ✅ SQL tests en remoto |
| 26 | **Z-205** | ✅ **PARCIAL (FASE 1.3):** columna `updated_at` añadida a schema/deploy (**✅ remoto ya alineado**; columna existía y la migración hace IF NOT EXISTS). Pendiente: trigger base. | Sync LWW funciona |
| 27 | **Z-207** | ✅ **HECHO (FASE 1.6):** auto-claim de `ensureAuth` ELIMINADO (el arranque ya no reclama con solo el ID local); el claim queda solo en login explícito con formato+rate-limit. | ✅ Sin login no se adueña ID (claim solo vía `loginWithExistingID`) |
| 28 | **Z-208** | Implementar emisión de endpoints `CACHE:`/`GLOBAL:` o eliminar la rama. | Radar muestra correcto |
| 29 | **Z-209** | ✅ **HECHO (FASE 1.6):** `.gitignore` ampliado (`hs_err_pid*`, `replay_pid*`, `*.hprof`, `*.dex`); artefactos de crash/build eliminados de la raíz (ninguno trackeado). | ✅ `git status` limpio de esos archivos |
| 30 | **Z-301** | Suite de tests por servicio (cripto vectors, cola offline, sync, RLS) + widget de flujos; CI `analyze+test`. | Cobertura >60% |
| 31 | **Z-302** | Plan de upgrades priorizado (supabase, secure_storage, notifications) validando con tests. | `flutter pub outdated` reducido; suite verde |
| 32 | **Z-304** | Corregir README/SECURITY/PRIVACY a lenguaje veraz; condicionar afirmaciones a FASE 1+. | Revisión legal |
| 33 | **Z-305** | Migrar configuración a `--dart-define`/`fromEnvironment` con defaults; dotenv solo dev. | Build release sin `.env` |
| 34 | **Z-306** | Mínimo necesario de permisos Android/iOS. | Revisión tiendas |
| 35 | **Z-307** | ✅ **PARCIAL (FASE 1.6):** comentario "sync bidireccional" corregido (`sync_service.dart`); pendiente suerte de `getRadarStats`/`verify_zone_id` de cliente (sin callers). | Lint dead_code |

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