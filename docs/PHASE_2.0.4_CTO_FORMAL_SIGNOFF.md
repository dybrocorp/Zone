# PHASE 2.0.4 — CTO FORMAL SIGN-OFF & IMPLEMENTATION GATE

> **Tipo:** Sign-off formal del CTO (humano) sobre las tres decisiones pendientes de
> FASE 2.0.3 — **DOCUMENTACIÓN + CTO SIGN-OFF + IMPLEMENTATION GATE · NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Fase:** FASE 2.0.4
> **Autoridad de aprobación:** CTO humano
> **Alcance:** documentación/arquitectura únicamente. NO autoriza implementación general;
> NO autoriza código, migraciones, RPC, RLS, Supabase ni cambios fuera de `docs/`.
> **Documentos fuente:** `PHASE_2.0.3_CTO_SIGNOFF_PACK.md`,
> `PHASE_2.0.3.1_FINAL_DOCUMENTATION_AUDIT.md`, `PHASE_2_DECISION_RESOLUTION.md`,
> `PHASE_2_OPEN_DECISIONS.md`, `PHASE_2_SECURITY_INVARIANTS.md`,
> `PHASE_2_CONSISTENCY_MATRIX.md`, `PHASE_2_CTO_HANDOFF_FINAL.md`
> y las 5 políticas 2.0.2.

---

## 1. CTO authority

Las decisiones registradas en este documento fueron aprobadas por el **CTO humano**
(revisión formal de FASE 2.0.3) el **2026-09-24**, dentro de **FASE 2.0.4**.

Las tres decisiones pendientes de FASE 2.0.3 quedan **CTO APPROVED**:

1. **OPEN-001** — Recovery.
2. **OPEN-018** — Recovery readiness.
3. **M5** — Retirada definitiva de `claim_zone_id`.

Esta autorización **NO** habilita la implementación de la arquitectura M0–M5 en general:
únicamente formaliza el CTO SIGN-OFF y prepara la puerta de implementación de FASE 2.1.

---

## 2. Approved decisions

| Decisión | Aprobación | Contenido aprobado |
|---|---|---|
| OPEN-001 | **CTO APPROVED** | OPTION A = RECOVERY BLOB **SIN X25519 v1**. La recuperación NO restaura la X25519 v1 histórica. Account recovery ≠ legacy key recovery; device recovery ≠ legacy key recovery; message history recovery ≠ account recovery; ratchet state recovery ≠ identity recovery. El sistema NO presenta recovery como garantía de recuperación universal del historial. |
| OPEN-018 | **CTO APPROVED** | Recovery permite alcanzar **RECOVERY_READY**; la configuración de recovery NO bloquea inmediatamente la creación inicial de una cuenta. Estados mínimos: `RECOVERY_UNCONFIGURED → RECOVERY_READY`. Mientras esté `RECOVERY_UNCONFIGURED`, aplican restricciones para operaciones de alto riesgo con requisito de recovery. |
| M5 (`claim_zone_id`) | **CTO APPROVED** | `claim_zone_id` NO es prueba de ownership en la arquitectura secure; durante la transición existe únicamente como mecanismo legacy controlado. Retirada definitiva **solo en M5**, condicionada a los requisitos documentados de readiness (NUNCA a una fecha arbitraria). |

Historial conservado de cada decisión (propuesta, aprobación, consecuencias, fecha/fase,
autoridad): `PHASE_2_DECISION_RESOLUTION.md` (apartados "CTO Approval" de
OPEN-001 / OPEN-011 / OPEN-018) y `PHASE_2_OPEN_DECISIONS.md`.

---

## 3. Recovery policy

Recovery **restaura la autorización de cuenta/dispositivo** según la arquitectura secure:
- Restaura la identidad de cuenta (Ed25519) y material de sesión/claves nuevas.
- Emite y gestiona códigos de recuperación (single-use, rotación, rate-limit).
- Permite re-bootstrap del dispositivo tras reinstalación.

Recovery **NO hace**:
- **NO restaura la X25519 v1 histórica** (OPTION A = blob SIN X25519 v1).
- **NO garantiza** la recuperación del historial de mensajes legacy v1.
- **NO convierte al servidor en custodio de la X25519 v1 privada** para solucionar la
  pérdida de historial.
- **NO** almacena códigos de recuperación en plaintext en el servidor
  (hash/derivación donde corresponda, client-side wrapping cuando corresponda, no
  custodia de private keys en plaintext, auditabilidad, protección contra replay y anti-abuso).

**STATUS: CTO APPROVED** — OPTION A = SIN X25519 v1 (FASE 2.0.4).

---

## 4. Legacy history consequence

Consecuencia explícitamente **aceptada por el CTO**:

Si un usuario pierde permanentemente el material criptográfico necesario para descifrar el
historial legacy v1, ese historial puede quedar **permanentemente ilegible**.

- La X25519 v1 **no** se recupera con el recovery.
- El ciphertext del historial v1 permanece sin descifrar; no se reescribe ni se destruye.
- El servidor **no** introduce ninguna clave histórica X25519 v1 en custodia únicamente
  para ofrecer recuperación del historial legacy.
- La app comunica el comportamiento fail-closed con copy honesto ("historial anterior no
  se descifra").

Esta consecuencia no se revierte salvo mediante un nuevo CTO review.

---

## 5. Recovery readiness

Estados mínimos definidos y aprobados:

```
RECOVERY_UNCONFIGURED
        ↓
RECOVERY_READY
```

- La creación inicial de una cuenta **no se bloquea** por no tener recovery configurado.
- Mientras una cuenta permanezca `RECOVERY_UNCONFIGURED`, existe una política de
  restricciones para las operaciones de alto riesgo que requieran recovery.
- La cuenta puede comenzar su uso normal según las reglas definidas por la arquitectura.
- La transición a determinadas operaciones/migraciones secure puede requerir
  `RECOVERY_READY`.

**STATUS: CTO APPROVED** (FASE 2.0.4, OPEN-018 — opción no bloqueante).

---

## 6. Legacy retirement

**M5 = LEGACY CLAIM RETIREMENT** — retirada definitiva de `claim_zone_id`.

Preconditions obligatorias (todas documentadas, previas a la retirada):

1. Secure enrollment disponible.
2. Secure identity (Ed25519) disponible.
3. Device authorization disponible.
4. Recovery path disponible y validado.
5. Reinstall path validado.
6. Legacy migration path validado.
7. Rollback strategy validado (feature flag `claim_legacy_disabled`).
8. Compatibilidad mínima satisfecha.
9. Ausencia de lockout conocido.
10. Validaciones de seguridad y auditabilidad cumplidas.

Reglas de retirada:

- **Sin fecha arbitraria**: la retirada NO depende de una fecha de corte; la propuesta de
  "90 días tras M4" queda superada como plazo fijo.
- **Condición "not ready"**: si alguno de los preconditions no se cumple,
  **M5 MUST NOT EXECUTE**.
- **Sin ventana de lockout**: en ningún punto una cuenta `mode=legacy` sin devices queda
  sin vía documentada (REGL-1..3, I-021/I-028).
- NO se elimina `claim_zone_id` en esta fase; NO se modifican RPC ni RLS; NO se modifica
  Supabase. La decisión es únicamente política arquitectónica.

**STATUS: CTO APPROVED** (FASE 2.0.4, M5).

---

## 7. Security invariants

Se confirman vigentes **I-001…I-030** (30/30 VALID, sin renumerar, sin eliminar).

El sign-off de FASE 2.0.4 **NO** convierte automáticamente ningún invariante de
`DESIGNED → IMPLEMENTED` ni de `PLANNED → VERIFIED`: el estado de los invariantes refleja
la especificación, no la existencia de código. El sign-off aprueba la arquitectura, no
demuestra que el software ya posea dichas propiedades.

Relevantes a las decisiones aprobadas:
- I-011 (sin promesa de FS sobre historial legacy) · I-012 (servidor no custodio de
  claves privadas) · I-016 (recovery code single-use) · I-021 (retirada del claim sin
  lockout) · I-024 (recovery no degrada garantía del historial) · I-025 (recovery jamás
  restaura X25519 v1) · I-028 (ninguna cuenta legacy sin devices queda sin vía M0-M5).

---

## 8. Threat model

Se confirma que los estados del threat model **continúan distinguiéndose correctamente**:

```
DESIGNED | PLANNED | IMPLEMENTED | VERIFIED
```

- Las amenazas T1-T17 mantienen sus estados previos (sin alteración por este sign-off).
- **Ninguna** amenaza se marca como `IMPLEMENTED` o `VERIFIED` por el hecho de existir
  este sign-off: la aprobación es de la especificación, no evidencia de implementación.
- T17 (recovery) permanece en su estado documentado (PLANNED — M4/M5 según el modelo).

---

## 9. Implementation boundary

Este documento **NO autoriza implementación general**.

Sigue prohibido:

- Implementar código o modificar `lib/`, `test/`, `pubspec.yaml`, config Flutter/Supabase.
- Ejecutar migraciones, modificar RPC/RLS/criptografía/protocolo de mensajería/Double
  Ratchet/Mesh/recovery runtime.
- Modificar Supabase remoto, ejecutar operaciones destructivas o borrar archivos.
- Realizar cambios fuera de `docs/` ni commits automáticos.

Alcance de FASE 2.0.4: **documentación + CTO sign-off + preparación de la puerta de
implementación.**

---

## 10. Next phase

La siguiente fase permitida será **FASE 2.1**, que **deberá tener su propio prompt, su
propio alcance, sus propias pruebas y su propio CTO gate**.

Este documento **no** inicia FASE 2.1 automáticamente: el estado de implementación pasa
de `BLOCKED` a **`PHASE 2.1 AUTHORIZATION PENDING`**, no a "autorizada".

---

## 11. Final status

CTO SIGN-OFF: APPROVED

FASE 2.0 DESIGN: APPROVED

IMPLEMENTATION AUTHORIZATION: PHASE 2.1 ONLY

NO OTHER IMPLEMENTATION AUTHORIZED