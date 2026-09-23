# AUDIT_MASTER — Auditoría Integral FASE 0 · Proyecto ZONE

> **Alcance:** FASE 0 — auditoría completa SIN modificación de código.
> **Fecha:** 2026-09-22
> **Estado:** DIAGNÓSTICO FINALIZADO — esperando autorización para FASE 1 (remediación).
> **Clasificación:** P0 = crítico/seguridad · P1 = grave · P2 = importante · P3 = mejora.

---

## 1. Resumen ejecutivo

`docs/BUG_REGISTER.md` contiene **37 hallazgos** catalogados:

| Severidad | Cantidad | Descripción |
|-----------|----------|-------------|
| **P0** | **8**  | Críticos de seguridad (robo de identidad, fuga RLS, mesh en claro, premium gratuito) y bloqueo funcional (la app NO arranca con el pubspec actual). |
| **P1** | **12** | Seguridad criptográfica real, sincronización, receipts, notifications, storage y plataforma. |
| **P2** | **9**  | UX/estabilidad/privacidad/artefactos. |
| **P3** | **8**  | Deuda técnica, tests, dependencias, docs engañosos. |

**Conclusión:** el proyecto **NO está listo para producción** y **NO cumple** lo que declara (E2EE "grado industrial", offline-first, "privacidad radical"). Las afirmaciones del README/SECURITY.md deben considerarse **NO VERIFICADAS / FALSAS en el estado actual**.

---

## 2. Alcance y método

- **Código revisado:** 15 servicios, 11 pantallas + widgets, 2 modelos (isar), 7 scripts SQL (schema, deploy, 5 parches), configs Android/iOS, docs legales, tests.
- **Herramientas ejecutadas:**
  - `flutter analyze` → **15 issues** (2 `use_build_context_synchronously`, 13 `avoid_print` en scripts/tools).
  - `flutter test` → **1 test pasa** (bomba de humo que NO verifica arranque; reproduce además el fallo `.env`).
  - `flutter pub outdated` → **69 dependencias upgradables**, 17 fuera de rango, 4 paquetes discontinuados.
  - `flutter pub deps` → árbol completo registrado.
  - Inspección estática manual (catches vacíos, streams, timers, controllers, singletons, secretos).
  - Escaneo de historial git por secretos (JWT, service_role, claves) → **sin hallazgos de secretos privados**; sí hay una **anon URL + publishable key hardcodeada de otro proyecto** en `test/load_test_simulator.dart`.
- **NO se modificó código.** El tooling de Flutter dejó efectos en `analysis_options.yaml`, `pubspec.lock` y `.flutter-plugins-dependencies`, **restaurados** con `git checkout` para no contaminar tu working tree.

---

## 3. Decline de responsabilidad legal (docs)

> Los documentos SECURITY.md, PRIVACY_POLICY.md, README.md y TERMS.md **declaran** capacidades que el código **no implementa** (E2EE de extremo a extremo universal, offline-first, Forward Secrecy, compra verificada, "grado industrial"). Se recomienda **no afirmar** nada de esto públicamente hasta remediar (FASE 1+).

---

## 4. Veredicto por dominio

| Dominio | Veredicto |
|---|---|
| **Autenticación / Identidad** | P0 inseguro: `zone_id` es la única credencial; `claim_zone_id` permite robo de cuenta. |
| **RLS / Backend** | P0 fuga de datos personales vía policy SELECT de `users`; funciones `SECURITY DEFINER` expuestas a `anon`. |
| **Mesh / P2P** | P0: plaintext cuando no hay llave de sesión; conexiones aceptadas sin autenticación. |
| **Chat / E2EE** | P1: sin ratchet/FS; sin cola offline real; mensajes se pierden; receipts muertos. |
| **Sincronización** | P1: push-only, IDs regenerados (duplicados), pull de mensajes inexistente. |
| **Arranque** | P0 funcional: `.env` fuera de assets → `FileNotFoundError` en arranque con el árbol actual. |
| **Premium** | P0: flag local sin verificación → cualquier usuario activa Premium gratis. |
| **Rendimiento** | P2: radar tirando de hasta 1000 perfiles cada 2 min + painters con `shouldRepaint=true`. |
| **Tests** | P3: cobertura ~0; sin tests unitarios/de servicios/seguridad. |

---

## 5. Documentos generados (FASE 0)

| # | Documento | Contenido |
|---|-----------|-----------|
| 1 | `AUDIT_MASTER.md` | Este índice y resumen ejecutivo. |
| 2 | `SECURITY_AUDIT.md` | Vulnerabilidades de seguridad (P0/P1) con vectores de ataque. |
| 3 | `CHAT_AUDIT.md` | Estado real del chat E2EE, offline, receipts. |
| 4 | `BACKEND_AUDIT.md` | Supabase: RLS, RPC, functions, storage, realtime. |
| 5 | `CRYPTO_AUDIT.md` | X25519/ChaCha20-Poly1305, gestión de claves, FS/ratchet. |
| 6 | `MESH_AUDIT.md` | Nearby Connections, routing, dedup, autenticación de peers. |
| 7 | `DATABASE_AUDIT.md` | Schema, parches pendientes (delivered_at, updated_at, is_premium…). |
| 8 | `PERFORMANCE_AUDIT.md` | Radar, painters, timers, batería/CPU, red. |
| 9 | `UX_AUDIT.md` | Errores crudos, estados de conexión, onboarding. |
| 10 | `ARCHITECTURE_AUDIT.md` | Singletons, acoplamiento, offline-first, arranque. |
| 11 | `BUG_REGISTER.md` | Los 27 hallazgos con formato completo (ID/Severidad/Archivo/Línea/…). |
| 12 | `REMEDIATION_PLAN.md` | Plan priorizado FASE 1 con dependencias y pruebas por bug. |

---

## 6. Próximo paso

La **FASE 1 (remediación) no ha sido autorizada**. Todo cambio de código debe esperar la aprobación explícita del dueño del repo sobre `REMEDIATION_PLAN.md` y `BUG_REGISTER.md`.

### Conteo final: 8 P0 · 12 P1 · 9 P2 · 8 P3