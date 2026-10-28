# PHASE 2.0 — CTO Handoff (Entrega Final de Diseño)

> **Tipo:** Resumen ejecutivo + índice de los 6 documentos de diseño FASE 2.0 — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** REVISIÓN PENDIENTE DE CTO
> **Contenido:** los 16 puntos exigidos por el mandato (sección 21), con referencias exactas.

---

## 1. Arquitectura actual

Mapa completo (Cuenta → Auth → ZONE-ID → Identidad → Dispositivos → X25519 → Chat →
Mesh) con evidencia archivo:línea: **`PHASE_2_IDENTITY_ARCHITECTURE.md` §1**.
Inconsistencias vigentes: doble keypair en primer arranque, clave local ≠ archivada tras
reinstalación, `claim_zone_id` sin posesión, `public_key` nunca rotada, session keys mesh
sin expiración (mismo documento §1.2-1.5).

## 2. Arquitectura objetivo

4 niveles de identidad: **Account (Ed25519, firma)** · **Device (Ed25519, firma de
dispositivo)** · **Encryption (X25519, ECDH)** · **Session (ratchet)**.
Separación estricta: X25519 jamás firma. Tabla conceptual de campos + tablas en
`PHASE_2_IDENTITY_ARCHITECTURE.md` §3 y `PHASE_2_DEVICE_MODEL.md` §1.

## 3. Flujo de registro (primer dispositivo)

**Bootstrapping de cuenta legacy**: `bootstrap_account` con sesión sobre la fila
`users` + código de 1 uso (TTL 10 min) + confirmación firmada + evento anti-apropiación
para el dueño; fail-closed en cuentas frías. Detalle: `PHASE_2_IDENTITY_ARCHITECTURE.md`
§4-5, `PHASE_2_DEVICE_MODEL.md` §2.

## 4. Flujo de login

- Login legacy retenido mientras exista modo legacy (compatibilidad).
- Nuevo login se reduce a: restaurar sesión/auth.uid() + verificar device activo +
  opcional upgrade bootstrap. **El ZONE-ID deja de ser credencial de apropiación.**
- `claim_zone_id` → eliminado como claim; sustituido por `transfer_account` /
  `register_device` / `recover_account` (IDENTITY_ARCHITECTURE §6).

## 5. Flujo de segundo dispositivo

Opción F: **autorización firmada por un device activo + QR/challenge + fingerprint**,
con variantes A-E evaluadas (tabla comparativa). Detalle: `PHASE_2_DEVICE_MODEL.md` §3.

## 6. Flujo de recuperación

Recovery codes de alta entropía (hash argon2id server-side + blob envuelto client-side),
presentación única, rotación, revocación; la X25519 privada perdida NO se recupera
(historial v1 ilegible — placeholder `🔒` ya existente). Detalle:
`PHASE_2_CRYPTO_DECISIONS.md` D5/D9/D10; `CRYPTO_CTO_REVIEW.md` §7.

## 7. Flujo de revocación

`revoke_device` firmado + reason + auditoría; `device_keys` → retired/compromised;
propagación mesh con `revocation_notice` firmado; el device revocado deja de recibir
entregas. Detalle: `PHASE_2_DEVICE_MODEL.md` §6; `PHASE_2_THREAT_MODEL.md` T11/T14.

## 8. Modelo Supabase

6 tablas conceptuales diseñadas (sin crear migraciones):

| Tabla | Propósito | RLS | Escalación |
|---|---|---|---|
| `account_identity` | Cuenta + Ed25519 + fingerprints + recovery salt/hash + legacy_public_key | Sin acceso directo; solo RPC | media (controlar RPCs) |
| `devices` | Device identity + estado | Solo RPC (list/authorize/revoke) | controlar firma |
| `device_keys` | X25519 versionada por device | Solo RPC | controlar rotación firmada |
| `device_challenges` | Nonces single-use | Sin acceso directo | controlar single-use/TTL |
| `device_revocations` | Auditoría | Solo lectura owner | baja |
| `recovery_credentials` | Hashes + salt (nunca en claro) | Solo RPC | **alta** — jamás SELECT público |

Detalle columnas/tipos/PK/FK/índices/constraints: `PHASE_2_DEVICE_MODEL.md` §1.

## 9. Threat model

17 amenazas (T1-T17) con precondiciones/ataque/resultado esperado/resultado actual/
mitigación + matriz de propiedades (IMPLEMENTADO/DISEÑADO/NO IMPLEMENTADO/NO VERIFICABLE):
`PHASE_2_THREAT_MODEL.md`. Hallazgo central: HOY no hay autenticación de identidad ni
FS; el diseño cierra todo salvo T12/T13 que se mitigan (no se eliminan) con M3/M4.

## 10. Compatibilidad legacy

- Modos **legacy / transition / secure** (+ retired-legacy).
- Se conserva `ZONE-ID`, `users`, `matches`, `messages` (schema sin cambio destructivo).
- Historial v1 legible con claves retiradas hasta cutover (M5).
- Detalle: `PHASE_2_MIGRATION_PLAN.md` §2-3.

## 11. Estrategia de migración

M0 (prep, sin crypto) → M1 (Ed25519+devices+RPC) → M2 (HKDF+AAD) → M3 (handshake) →
M4 (Double Ratchet) → M5 (retiro legacy). Cada fase compatible/reversible, con
condición de parada CTO. Estimación de sprints incluida. Detalle:
`PHASE_2_MIGRATION_PLAN.md` §1,4,7.

## 12. Interfaces necesarias para E2EE

- `ChatE2EEService` mantiene su API (encrypt/decrypt) pero la derivación pasa a
  HKDF+AAD (v3) con version footer en `encrypted_content`.
- `P2PSecurityService` gana: gestión de fingerprint y verificación de firma.
- Nuevos servicios de RPC: `bootstrap`, `register_device`, `authorize_device`,
  `revoke_device`, `rotate_key`, `request_challenge`, `verify_signed_op`,
  `recover_account`.
- `messages` NO cambia de columnas; solo variante de derivación dentro del campo.
  Detalle: `PHASE_2_MIGRATION_PLAN.md` §4 (M2) y `PHASE_2_DEVICE_MODEL.md` §5.

## 13. Interfaces necesarias para Double Ratchet

Siete conceptos (SessionState, RootKey, ChainKey, MessageKey, RatchetPublicKey,
SkippedMessageKeys, MessageCounter) + persistencia/cifrado local/recuperación/sync/
rollback/out-of-order/replay/FS/PCS. Detalle: `PHASE_2_MIGRATION_PLAN.md` §5;
`PHASE_2_CRYPTO_DECISIONS.md` D13; `CRYPTO_CTO_REVIEW.md` §6.

## 14. Riesgos

1. Historial v1 sin FS retroactiva (aceptar) — THREAT_MODEL T13.
2. Compromiso total de servidor → MITM hasta M3 — THREAT_MODEL T12.
3. Usuarios legacy sin upgrade (coste de soporte indefinido) — D8.
4. Bootstrap M1 (apropiación) — mitigado con UI de señuelos + evento anti-apropiación.
5. Complejidad de M4 (ratchet) — mitigado por interfaces previas + pruebas por fase.

## 15. Decisiones pendientes

Checklist D1-D14 + DR-1..DR-6 → **`PHASE_2_CTO_REVIEW_REQUIRED.md`** (firmas en blanco).

## 16. Orden exacto de implementación (propuesto)

```
M0  (preparatoria)          → 1 sprint
M1  (Ed25519 + devices)     → 2-3 sprints
M2  (HKDF + AAD)            → 1 sprint
M3  (handshake v4)          → 1 sprint
M4  (Double Ratchet)        → 2 sprints
M5  (retiro legacy)         → 1 sprint (tras 90 días de M4)
```

**Ninguna fase comienza sin la aprobación CTO de `PHASE_2_CTO_REVIEW_REQUIRED.md`.**

---

## Documentos de FASE 2.0 (índice)

| Archivo | Contenido |
|---|---|
| `PHASE_2_IDENTITY_ARCHITECTURE.md` | Mapa actual, 4 niveles de identidad, usuarios existentes (A-G), fingerprint, `claim_zone_id` → transfer |
| `PHASE_2_DEVICE_MODEL.md` | Tablas (6), registro primer/segundo device (6 opciones), rotación X25519, challenge-response canónico, revocación |
| `PHASE_2_MIGRATION_PLAN.md` | v1→v5, modos legacy/transition/secure, compatibilidad, interfaces Double Ratchet, riesgo M0-M5, orden |
| `PHASE_2_THREAT_MODEL.md` | Matriz de propiedades + 17 pruebas T1-T17 |
| `PHASE_2_CRYPTO_DECISIONS.md` | D1-D14 cerradas |
| `PHASE_2_CTO_REVIEW_REQUIRED.md` | Checklist de firma (puerta) |
| `CRYPTO_CTO_REVIEW.md` | Documento madre actualizado (referencias a FASE 2.0) |

> ⚠️ **ESTA FASE NO IMPLEMENTA.** Todo queda en DISEÑO hasta la firma del CTO.
> El siguiente paso será decidido únicamente tras la revisión de este handoff.