# PHASE 2.0 — Plan de Migración Criptográfica de ZONE

> **Tipo:** Diseño definitivo (FASE 2.0 · puerta CTO) — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** REVISIÓN PENDIENTE DE CTO · **FASE 2.0.2**: §8
> reconstrucción conceptual post-decisiones (claim acotado, recovery en M1, failure matrix)
> · **FASE 2.0.4**: M5 = **LEGACY CLAIM RETIREMENT** **CTO APPROVED** (condicionado a
> readiness; sin fecha arbitraria; registro: `PHASE_2.0.4_CTO_FORMAL_SIGNOFF.md`)
> **Depende de:** `PHASE_2_IDENTITY_ARCHITECTURE.md`, `PHASE_2_DEVICE_MODEL.md`
> **Referencia:** `CRYPTO_CTO_REVIEW.md` §8 (fases B0-B6) — este documento refina y cierra el orden.

Este documento responde a las secciones 14 y 15 del mandato: compatibilidad del
historial existente, modos legacy/transition/secure, retiro de legacy, e interfaces
que necesitará el Double Ratchet. **Nada de esto se implementa en FASE 2.0.**

---

## 1. Línea evolutiva v1 → v5

```
v1  legacy X25519 estático E2EE          ← HOY (production)
v2  Ed25519 account + device identity    ← bootstrap + devices (sin cambiar cifrado)
v3  HKDF + AAD sobre el mismo core       ← session key derivada, AEAD con contexto
v4  handshake autenticado                ← fingerprint + firma en 1er contacto
v5  Double Ratchet                       ← FS + PCS + out-of-order
```

Regla rectora: **cada fase es compatible con la anterior y reversible sin pérdida de
datos.** Nunca se descifra ni se reescribe el historial; solo se añaden versiones de
derivación y nuevas claves.

---

## 2. Modos de operación (por cuenta/par)

| Modo | Descripción | Cuándo existe | Qué cifra |
|---|---|---|---|
| **legacy** | Par usa v1 (X25519 estático, sin KDF, sin AAD, sin Ed25519) | Cuentas creadas antes de FASE 2.0; par sin upgrade | Shared secret crudo X25519 |
| **transition** | Un lado ya tiene Ed25519/account, el otro no; o el par soporta v3 | Cuentas nuevas/upgraded; peers mezclados | v3 (HKDF+AAD) cuando ambos lados lo soportan; v1 si alguno no |
| **secure** | v4/v5 ambos lados + devices activos | Par completo upgrade | v5 ratchet |
| **retired-legacy** | El servidor ya no permite paquetes v1 **nuevos** para ese par | Solo historial aún descifrable con claves retiradas | Solo lectura v1 |

---

## 3. Compatibilidad garantizada (lo que NO puede romperse)

| Recurso | Requisito | Mecanismo |
|---|---|---|
| Mensajes existentes (historial cloud) | Siguen legibles con la clave **con la que se cifraron** | `device_keys` conserva `old` X25519 como `retired` + `key_version` para seleccionar derivación por mensaje |
| Matches | No tocar `matches` | Sin cambios de esquema en `matches` (FASE 2.0) |
| Perfiles | No tocar `users` público | `users` se mantiene; `account_identity/devices` son tablas NUEVAS adjuntas |
| ZONE-ID | No cambia | `users.zone_id` igual; `account_identity.zone_id` copia |
| Usuarios activos | Sin fricción de login | Login legacy sigue posible mientras exista modo legacy; upgrade es opcional |
| Mesh | `profile_exchange` sigue funcionando | v2 trae además `fingerprint` + firma Opcional; si el peer es legacy, se cae a v1 |

---

## 4. Detalle por fase

### FASE M0 — Preparatoria (sin criptografía nueva)

- Inventario y monitoreo: nueva tabla `account_identity` en **banco** (no migración).
- Corregir inconsistencias vigentes **sin tocar protocolo**:
  - Dedicir fuente única de keypair (hoy doble keypair: `p2p_security_service.dart:27-49` + `zone_id_service.dart:197-203`).
  - Sincronizar `_publicBase64` de `P2PSecurityService` con la clave real en uso.
- **Criterio de salida:** `flutter analyze` 0, tests de compat v1 intactos.

### FASE M1 — v2: identidad Ed25519 (account + devices) — **grande, sin mover cifrado**

- Tablas: `account_identity`, `devices`, `device_keys`, `device_challenges`, `device_revocations`, `recovery_credentials` (schema de DEVICE_MODEL §1).
- Bootstrapping de cuentas legacy (IDENTITY_ARCHITECTURE §5).
- Registro de dispositivos (DEVICE_MODEL §3).
- RPCs de challenge-response (§5.2/§5.3 DEVICE_MODEL).
- **No cambia** el cifrado de mensajes: los pares legacy siguen con shared secret v1.
- Los mensajes nuevos de una cuenta upgraded se siguen cifrando **igual que hoy**
  (misma public_key archivada) — solo añadimos identidad de firma alrededor.
- **Criterio de salida:** los usuarios legacy pueden upgrade; nuevos pueden crear cuenta; mensajes v1 intactos; `resolve_bt_token`/radar no cambian.

### FASE M2 — v3: HKDF + AAD (sin cambios de formato de mensaje fuera de la derivación)

- La session key pasa de `shared_secret crudo` → `HKDF-SHA256(shared, salt=pub‖pub, info="zone-e2ee-v3|match|sender|epoch")`.
- AEAD con AAD = `match_id ‖ sender_uid ‖ msg_id`.
- **No cambia** el formato de fila `messages` (mismas columnas); solo el **contenido
  cifrado** se produce con la nueva derivación. Compatibilidad: al abrir un chat, si
  el mensaje tiene caducidad/version footer (diseño: se añade un byte de versión al
  inicio del `encrypted_content`), se usa la derivación correcta.
- Backward: mensajes v1 se descifran con derivación v1 → la `public_key` archivada
  debe seguir existiendo (no se revoca hasta ‘retired-legacy’).
- **Criterio de salida:** chat v1 y v3 coexisten; tests mostrando v3 no rompe historial.

### FASE M3 — v4: handshake autenticado

- `profile_exchange` v2 con `fingerprint` + firma Ed25519 (CRYPTO_CTO_REVIEW §5) en el primer contacto mesh/cloud.
- Fingerprint de cuenta y de dispositivo (IDENTITY_ARCHITECTURE §7).
- MITM se reduce a comparación out-of-band (QR/pantalla).
- **Criterio de salida:** pares upgraded nunca derivan con clave no autenticada;
  peers legacy aceptan el downgrade explícito con warning.

### FASE M4 — v5: Double Ratchet

Ver §5 (interfaces) y `CRYPTO_CTO_REVIEW.md` §6. Solo tras M3.

- Nueva derivación por ratchet por **par de devices** (DR-2).
- Mensajes con `header` explícito: `{version, dh_pk, msg_n, prev_n}` + AEAD nonce.
- **Criterio de salida:** FS/PCS probados por vectores; out-of-order OK; rendimiento BLE < 50 ms.

### FASE M5 — LEGACY CLAIM RETIREMENT (retiro de legacy)

- `retired-legacy`: el servidor deja de aceptar **nuevos** paquetes v1 **entre pares
  que ya soportan v5**; el historial v1 se lee solo con claves retiradas.
- Anuncio de "cuenta requires upgrade" cuando un par vuelve a legacy.
- **Retirada definitiva de `claim_zone_id`** (CTO APPROVED — FASE 2.0.4): **solo** cuando
  se cumplen los preconditions de readiness documentados (sección 8, M5). **Sin fecha
  arbitraria.** La "fecha de corte propuesta: 90 días tras M4" queda **superada** como
  plazo fijo; M5 depende de readiness, no del calendario.

---

## 5. Interfaces necesarias para Double Ratchet (sección 15) — SOLO DEFINICIÓN

### 5.1 Tipos de estado (semántica, no implementación)

| Concepto | Definición | Dónde debe vivir |
|---|---|---|
| `SessionState` | Estado del ratchet para un par (o device-pair): raíz, cadenas, contadores, DH actual, skipped | SecureStorage (o Isar cifrado localmente — decisión DR-6) |
| `RootKey` | Se deriva de los DH del handshake; raíz de las cadenas | derivado del estado, no persistido si es posible |
| `ChainKey` | Cada dirección tiene su cadena (sending/receiving); avanza con KDF | parte de `SessionState` |
| `MessageKey` | Clave AEAD única por mensaje, derivada de la cadena | cifrada con la cadena, no persistida a largo plazo (solo deduplicación) |
| `RatchetPublicKey` | Nueva clave DH pública que se publica cuando se rota el ratchet | en el `header` del mensaje; persistida como parte de `SessionState` |
| `SkippedMessageKeys` | Mensajes recibidos fuera de orden esperado; se cachean hasta el límite | en `SessionState.skipped`, con TTL/cuota (2000/par propuesto) |
| `MessageCounter` | `msg_n` en la cabecera; evita replay y permite out-of-order | en `header` |

### 5.2 Persistencia, cifrado local y recuperación

- **Persistencia:** `SessionState` por par de devices guardado en **SecureStorage**
  (`ratchet_<peer_device_id>`), con snapshots para restauración tras reinicio.
- **Cifrado local:** la DB Isar puede guardar los estados cifrados con una clave
  derivada (pin opcional o keystore), para no dejar ratchet desprotegido en backup.
- **Recuperación:** tras reinstalación, el estado del ratchet **no** se recupera del
  servidor (es secreto local): el par recién sincronizado reinicia el ratchet con un
  mensaje de re-sincronización. Dejar el historial v1 intacto.
- **Sync multi-device:** los parámetros públicos del ratchet (no secretos) se pueden
  sincronizar por `device_keys`; los secretos NO.

### 5.3 Protección

| Propiedad | Mecanismo |
|---|---|
| Rollback | `msg_n`/`prev_n` estrictamente crecientes por dirección; rechazo de `msg_n <= prev_n_aceptado` |
| Out-of-order | `skipped` cache; límite 2000; al superar, re-sync |
| Replay | `msg_n` + nonce usado (tabla local deduplicación AEAD) |
| FS | rotación DH periódica (por turno) con ecuación doble DH → `prev_n` ligado |
| PCS | tras revelación, siguiente mensaje con nuevo DH sano |

### 5.4 Consecuencia sobre el esquema

- `messages` **no cambia su forma** (mismas columnas `encrypted_content/nonce/mac`);
  la versión de derivación y el header de ratchet van **dentro** del campo cifrado o
  como prefijo versionado. → No hay migración destructiva de mensajes.

---

## 6. Riesgos y mitigaciones (resumen — detalle en THREAT_MODEL)

| Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|
| Romper historial v1 al añadir v3 | Media | Alto | `key_version`/footer de versión; tests de compat; nunca revocar clave antes de cutover |
| Par legacy y nuevo incompatibles | Alta | Medio | Modo transition con downgrade explícito |
| Complejidad de M1 (bootstrap) | Alta | Alto | Feature flag con fallback legacy; señuelos anti-apropiación ya definidos |
| Pérdida de estados de ratchet por reinstalación | Media | Medio | Re-sync + historial v1 como red de respaldo |
| Coste BLE (4 DH + HKDF) | Media | Medio | Medir; rotar por turno; no por mensaje |
| Claims maliciosos durante M1 | Alta (hoy) | Crítico | Eliminar claim, eventos de apropiación, ventana de actividad, fail-closed en cuentas frías |

---

## 7. Orden exacto de implementación (propuesta — para CTO)

```
M0  (preparatoria, sin crypto)         → 1 sprint
M1  (Ed25519 + devices + RPCs)         → 2-3 sprints
M2  (HKDF + AAD)                       → 1 sprint (solo derivación + footer)
M3  (handshake v4)                     → 1 sprint
M4  (Double Ratchet v5)                → 2 sprints (ratchet + UI)
M5  (retiro legacy)                    → 1 sprint (tras 90 días de M4)
```

La **condición de parada**: cada fase solo comienza tras aprobación CTO de la fase
anterior (checklist en `PHASE_2_CTO_REVIEW_REQUIRED.md`).

---

## 8. FASE 2.0.2 — Reconstrucción conceptual M0-M5 (post-resolución de OPEN)

> Autoridad complementaria: `PHASE_2_LEGACY_ACCESS_POLICY.md`,
> `PHASE_2_MIGRATION_FAILURE_MATRIX.md`, `PHASE_2_RECOVERY_POLICY.md`,
> `PHASE_2_BOOTSTRAP_POLICY.md`. **Solo diseño — nada se implementa en FASE 2.0.2.**

### M0 — Preparatoria
- **Objetivo:** única fuente de keypair; `flutter analyze` 0; sin criptografía nueva.
- **Precondición:** OPEN-012 aceptado (matriz de failure-modes como contrato).
- **Cambios permitidos:** corrección del doble keypair de `_registerInSupabase`; inventario;
  banco de migraciones. **Prohibidos:** tocar `claim_zone_id`, cifrado, remoto.
- **Compatibilidad / Rollback:** superficie nula (reversible por revert de código).
- **Recovery / legacy / secure:** sin cambio. Server/client state: sin cambios.
- **Verificación:** analyze 0 + tests v1 intactos (I-020, I-005).

### M1 — v2 (identidad Ed25519 + devices) — *ajustada por FASE 2.0.2*
- **Objetivo:** `account_identity` + `devices` + recovery; bootstrap; RPCs con challenge;
  binding `users.account_id` (OPEN-007); claim **acotado** (OPEN-011); emisión de recovery
  codes en el **primer arranque post-M1** (OPEN-018).
- **Precondición:** OPEN-001/002/003/011 aprobados + resto de OPEN; `external_anonymous_users`
  intacto.
- **Cambios permitidos:** tablas nuevas (`IF NOT EXISTS`), RPCs SECURITY DEFINER, REVOKE ALL,
  device_1 **`pending`** (I-013/I-030), blob `recovery_wrapped` sin X25519 v1 (I-025).
- **Prohibidos:** tocar el cifrado v1 de mensajes; eliminar el claim (solo acotarlo);
  SELECT directo a tablas de identidad (I-014).
- **Compatibilidad:** v1 intacto; legacy puede seguir sin upgrade. **Rollback:** flag de fase;
  tablas inertes; claim vuelve a pleno.
- **Recovery:** códigos emitidos (OPEN-018); vía de reinstalación legacy = claim acotado
  (I-028).
- **Server/client state:** `users.account_id` backfilled; cliente guarda Ed25519 en
  SecureStorage.
- **Verificación:** KAT fingerprint + canonical v1; T1-T4, T7-T11, T14-T15; máquina
  PENDING→ACTIVE (I-030).

### M2 — v3 (HKDF + AAD)
- **Objetivo:** derivación HKDF + AAD con footer de versión; sin cambio de formato de fila.
- **Precondición:** M1 VERIFICADO. **Permitido:** solo derivación + footer.
- **Prohibido:** revocar la clave archivada antes de `retired-legacy`.
- **Compatibilidad / Rollback:** v1↔v3 coexisten; sin pérdida (clave archivada).
- **Verificación:** KAT RFC 5869; tests v1↔v3 (I-010/I-011).

### M3 — v4 (handshake autenticado)
- **Objetivo:** `profile_exchange` v2 con firma + **DEVICE_FINGERPRINT** (OPEN-016).
- **Precondición:** OPEN-002/016; FINGERPRINT_SPEC como contrato.
- **Permitido:** comparación off-band obligatoria. **Prohibido:** aceptar fingerprint sin
  comparación (I-007); downgrade legacy explícito con warning (I-009).
- **Verificación:** T6/T12/T16; KAT fingerprint en dos implementaciones (I-017).

### M4 — v5 (Double Ratchet)
- **Objetivo:** FS/PCS; estado por **par de devices** (OPEN-006); sin prekeys v1 (OPEN-014);
  `SessionState` secreto local (I-023).
- **Precondición:** OPEN-006/014; M3 VERIFICADO.
- **Permitido:** re-sync de ratchet por reinstalación (MIGRATION §5.2).
- **Prohibido:** subir `SessionState`; historial v1 sin tocar.
- **Verificación:** T5/T9/T17 + vectors FS/PCS + rendimiento BLE.

### M5 — LEGACY CLAIM RETIREMENT (retiro de legacy)
- **Objetivo:** retirar definitivamente `claim_zone_id` **solo** bajo las condiciones de
  LEGACY_ACCESS_POLICY §5 (OPEN-011/I-028) y los preconditions de readiness; `retired-legacy`
  solo lectura.
- **Preconditions (CTO APPROVED — FASE 2.0.4):**
  1. Secure enrollment disponible y verificado.
  2. Secure identity (Ed25519) disponible y verificada.
  3. Device authorization disponible y verificada.
  4. Recovery path disponible y validado (`RECOVERY_UNCONFIGURED → RECOVERY_READY`).
  5. Reinstall path validado (sin lockout de reinstalación).
  6. Legacy migration path validado (upgrade documentado para toda la base).
  7. Rollback strategy validado (feature flag `claim_legacy_disabled`, re-enable + audit).
  8. Sin lockout conocido (ninguna cuenta `mode=legacy` sin devices **ni** recovery).
  9. Condiciones de compatibilidad mínima satisfechas (I-021/I-028; REGL-1..3).
  10. Validaciones de seguridad y auditabilidad cumplidas.
- **Condición "not ready":** si alguno de los preconditions no se cumple, **M5 MUST NOT
  EXECUTE**. La retirada se aplaza hasta que todos estén satisfechos — **sin fecha
  arbitraria** (la propuesta de "90 días tras M4" queda superada como plazo fijo;
  solo permanece como referencia histórica de producto).
- **Prohibido:** retirar el claim si quedan cuentas `mode=legacy` sin devices **ni**
  recovery. **Rollback:** feature flag `claim_legacy_disabled`.
- **Verificación:** tests de regresión de reinstalación legacy (M1-M5); I-021/I-028.

> **Integración con la matriz de fallos:** los 12 escenarios de
> `PHASE_2_MIGRATION_FAILURE_MATRIX.md` son contrato de M0-M5 (ejecución duplicada,
> red/Supabase caídas, reinicio/reinstalación, versión antigua/nueva, rollback parcial) — se
> verifican como pruebas de fase (I-010/I-019).