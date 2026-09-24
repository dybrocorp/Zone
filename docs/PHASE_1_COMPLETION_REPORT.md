# PHASE_1_COMPLETION_REPORT — Reporte de cierre FASE 1 · ZONE

> **Puerta obligatoria** del `REMEDIATION_PLAN.md`: antes de continuar con los pendientes
> de P1 y fases siguientes, esta FASE 1 (1.1→1.6) debe quedar documentada con evidencia.
> **Fecha:** 2026-09-23 · **Autor:** agente de remediación (decisión y validación CTO del propietario).

---

## 1. Resumen ejecutivo

FASE 1 cerró los **P0 de seguridad/funcionales autorizados** y un batch de higiene/RLS,
con verificación local (`flutter analyze` 0 issues, `flutter test` 18/18) y remota por rol
(cuando aplica), **sin mutar datos reales** (probes con ROLLBACK; DDL en transacciones atómicas).

**Estado global de FASE 1: ✅ CERRADA** con riesgos residuales documentados (sección 4).
**Próximos pendientes que requieren decisión CTO:** Z-004 (handshake Ed25519), Z-008 (IAP real),
y los requerimientos de backend/epics (Z-110 push, Z-111 storage, Z-101 ratchet).

---

## 2. Fases cerradas y evidencia

| Fase | Bug(s) | Resultado | Evidencia clave |
|------|--------|-----------|-----------------|
| 1.1 | Z-006 | ✅ CERRADA | `--dart-define`/`String.fromEnvironment` (`lib/utils/env_config.dart`), arranque degradable, sin `!`; sonda confirma inyección; build release en dispositivo ⏳ (pendiente externo). |
| 1.2 | Z-001 (Fase A), Z-103 | ✅ REMOTE_APPLIED + VERIFIED | `claim_zone_id`/`verify_zone_id` endurecidos: REVOKE anon, formato+rate-limit, sin rotación silenciosa; anon → 42501 en vivo; 2-arg dropeada. |
| 1.3 | Z-002 | ✅ REMOTE_APPLIED + VERIFIED | RLS `users` self-scoped + vista `v_profile` (gating avatar/handles/bloqueos server-side), claim devuelve perfil jsonb; mojibake sanado. |
| 1.4 | Z-003 | ✅ VERIFIED_LOCAL | Mesh fail-closed: nunca texto en claro; decisión §9. |
| 1.5 | Z-007 | ✅ CERRADA (app+remoto) | Outbox idempotente por PK estable UUID v4 (`ON CONFLICT (id)`), `markAllMessagesRead` al abrir chat, RPCs SECURITY DEFINER con gate `auth.uid()`; verificación por rol OK; commit `c0b10a6`. |
| 1.6 | Z-005, Z-106, Z-206, Z-207, Z-201/Z-303, Z-203, Z-209, Z-307(parcial) | ✅ CERRADA | Mesh msgId UUID v4 + dedup LRU/TTL; policies DELETE/UPDATE remotas (Z-106/Z-206) aplicadas y verificadas; auto-claim eliminado; `flutter analyze` **0 issues**; `flutter test` 18/18. |
| 1.7 | Z-104, Z-204, Z-308 (acotado), Z-105 reste | ✅ CERRADA (esta tanda) | `resolve_bt_token` **REVOKE anon aplicado + verificado remoto** (anon → 42501); filtro BLE por token propio; catchers silenciosos → log; `markMessageDelivered` cableado al receptor. `flutter analyze` 0 issues · `flutter test` 18/18. |

**Detalle por ítem de la 1.6** (commit de esta tanda):
- **Z-005** — `mesh_policy.dart` (`Uuid().v4()` + clase `MeshDedup` LRU/TTL 15 min), `nearby_service.dart`
  usa `register()`; 6 tests nuevos en `mesh_policy_test.dart`.
- **Z-106** — `matches` → policy `"Eliminar propio match"` FOR DELETE solo `authenticated` (participantes);
  aplicada y verificada en remoto.
- **Z-206** — `messages` → policies UPDATE/DELETE `"…con match aceptado"` solo participantes; aplicadas y
  verificadas en remoto (anon bloqueado).
- **Z-207** — auto-claim de `ensureAuth` eliminado; claim solo en login explícito.
- **Z-201/Z-303** — guards `mounted` correctos (2 `use_build_context_synchronously`) + 13 `avoid_print`
  → `flutter analyze` 0 errors/0 warnings/0 infos.
- **Z-203** — credenciales hardcodeadas de otro proyecto fuera del repo (env con abort si faltan).
- **Z-209** — `.gitignore` ampliado + artefactos (`hs_err_pid*`, `replay_pid*`, `Zone.apk`) eliminados.
- **Z-307** — comentario "sync bidireccional" corregido (parcial: `getRadarStats`/`verify_zone_id` sin callers
  quedan pendientes de decisión de limpieza).

**FASE 1.7** (esta tanda, decisión CTO §13 — batch seguro, no toca criptografía):
- **Z-104** — `resolve_bt_token` REVOKE a `anon`/PUBLIC (solo `authenticated`), aplicado y verificado en
  remoto (anon → 42501; producción intacta). Decisión: sin single-use estricto (rompería radar multi-vecino).
- **Z-204** — filtro BLE por nombre de token propio (`_appTokenNamePattern` en `ble_proximity_service.dart`).
- **Z-308** (acotado) — `catch (_) {}` silenciosos → log con mensaje en 5 archivos.
- **Z-105 reste** — `markMessageDelivered` cableado al receptor en `chat_screen.dart` (RPC Z-007 existente).

---

## 3. Verificación

### Local
- `flutter analyze` → **0 issues** (0 errors, 0 warnings, 0 infos).
- `flutter test` → **18/18** (12 previos + 6 nuevos Z-005; merge Z-007 curado cubierto por los previos).

### Remota (Management API vía PAT, proyecto `tdacwsbghmjnrbawxhjk`)
- Migraciones aplicadas en transacciones atómicas y verificadas: `secure_claim_zone_id.sql` (1.2),
  `z002_profile_visibility.sql` (1.3), `z007_offline_chat.sql` (1.5, incluida la consolidación), y
  `z106_z206_policies.sql` (1.6).
- Pruebas de rol en vivo (probes ROLLBACK, sin mutar datos reales):
  - anon → RPCs/claims: **42501 permission denied** ✅
  - anon → DELETE sobre tables: bloqueado por RLS (0 filas) ✅
  - authenticated sin sujeción → 0 filas ajenas (self-scope + policies de participantes) ✅
  - Producción tras probes: datos intactos ✅
- Baselines `supabase_schema.sql`/`supabase_deploy.sql` consolidados (columna, RPCs, policies y ACL
  alineadas con el remoto verificado).

### Git
- Commits de cierre por fase en `main`; HEAD: `c0b10a6` (1.5) + commit común de la 1.6 (esta tanda).
- WIP del usuario preservado (sin `reset --hard`/`clean`); borrador inseguro `add_message_delivery_status.sql`
  eliminado por decisión CTO (suplido por el canon `z007_offline_chat.sql`).

---

## 4. Riesgos residuales y pendientes (fuera de esta FASE 1, requieren decisión CTO)

| Prioridad | ítem | Riesgo / estado |
|-----------|------|-----------------|
| P0 | **Z-004** — handshake firmado Ed25519 + challenge (identidad ↔ endpoint) | Firma sobre identidad nueva (Fase B de Z-001). Requiere diseño (claves X25519 actuales no firman). |
| P0 | **Z-008** — Premium simulado (cualquiera activa Premium gratis) | Requiere IAP real/Edge Function + validación server-side. |
| P1 | **Z-104** — `resolve_bt_token` GRANT a anon + tokens reutilizables | Requiere decisión RLS/GRANT (post-Fase 1). |
| P1 | **Z-105 (reste)** — cablear `markMessageDelivered` al receptor | API lista en `supabase_service.dart`; fuera del alcance de la Opción 1 aprobada. |
| P1 | **Z-107 (reste)** — pull de mensajes por cursor + merge LWW multidispositivo | Herencia de 1.5: el push es idempotente; el pull queda pendiente. |
| P1 | **Z-109 (reste)** — RPCs radar/actividad siguen siendo drift SOLO-REMOTO; trigger `updated_at` | Dump canónico pendiente. |
| P1/P2 | **Z-110**, **Z-111**, **Z-112**, **Z-101**, **Z-102** | Push, storage privado, rendimiento radar, ratchet FS, safety numbers — epics con backend/diseño. |
| P2/P3 | Z-202/308, Z-204, Z-208, Z-301, Z-302, Z-304, Z-306, Z-307 (reste) | Calidad/estabilidad, pendientes de priorización. |

> **Regla vigente:** cualquier cambio en cripto, RLS, SECURITY DEFINER, esquema remoto o mesh exige
> decisión CTO registrada (ver `docs/CTO_REVIEW_REQUIRED.md`).

---

## 5. Decisión de continuidad

✅ **Aprobado para continuar con los pendientes de P1/P2 y las fases siguientes** (bajo las mismas
reglas de decisión y verificación por rol), **sin necesidad de implementar los epics de diseño** hasta
tomar decisión explícita sobre Z-004 / Z-008 / Z-101 / Z-110 / Z-111.

**Próximo paso sugerido:** resolver Z-104 (GRANT solo authenticated + token de un solo uso) y compilar el
canon de las RPC radar (Z-109) como lote de consolidación 1.7 antes de decidir los epics.