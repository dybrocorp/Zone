# PHASE 2.0.1 — Invariantes de Seguridad (Security Invariants)

> **Tipo:** Lista formal de reglas que **NUNCA** pueden romperse durante la implementación
> de FASE 2.0 (M0-M5) ni en el futuro — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** ACTUALIZADO EN FASE 2.0.2 (RESOLVED — CTO PROPOSED;
> aprobación humana pendiente). R-IDs referencian `PHASE_2_CONSISTENCY_MATRIX.md`;
> decisiones en `PHASE_2_DECISION_RESOLUTION.md`.
> **Uso:** cada fase (M0-M5) debe declarar, en su criterio de salida, qué invariantes
> verifica y con qué tests. Los ⚠️ PD de FASE 2.0.1 quedaron resueltos (propuestos) en
> FASE 2.0.2; I-025…I-030 incorporan las reglas nuevas. Ninguno se activa sin firma CTO.

---

## I-001 — Conocer ZONE-ID no demuestra posesión
`ZONE-XXXXXXXX` es un identificador enrutable, **no** una credencial. Ninguna operación
privilegiada (alta de device, recovery, transfer, rotación) se autoriza solo por presentarlo.
- Fuente: D11, IDENTITY_ARCHITECTURE §6:266-267, THREAT T1/T3.
- Prueba: T1 (resultado esperado DENEGADO).

## I-002 — X25519 nunca firma
Ninguna firma se produce con material X25519 (ni ECDH-derivado). Las firmas son Ed25519
(account o device). El shared secret X25519 solo alimenta ECDH→KDF→AEAD.
- Fuente: CRYPTO_CTO_REVIEW §0:49-51, §4.1:170; CRYPTO_DECISIONS D2:24.
- Prueba: revisión de código + git grep de `Sign` sobre claves X25519 (M1+).

## I-003 — Toda operación privilegiada requiere autorización criptográfica apropiada
`bootstrap` (sesión+señuelos+confirmación firmada), `register_device`/`authorize_device`
(firma device activo + challenge), `rotate_key` (firma device activo + challenge), `revoke`
(firma de cuenta), `recover` (recovery code single-use), `transfer` (firma de cuenta).
- Fuente: DEVICE_MODEL §5; CRYPTO_DECISIONS D3-D7, D11.
- Prueba: T4, T7-T11.

## I-004 — Las claves privadas nunca salen del dispositivo, salvo el mecanismo de recovery aprobado
SecureStorage es el único hogar de `priv_Ed25519`/`priv_X25519`. La única excepción es el
blob de recovery E2EE definido en `PHASE_2_RECOVERY_POLICY.md` (blob v1 = identidad Ed25519
de cuenta; **jamás X25519 v1**).
- Fuente: D1:13, D5:54-58, DEVICE_MODEL §1.6:98-100; RECOVERY_POLICY §3-§4 (OPEN-001).
- Estado: **VALID** — acotado por I-025.

## I-005 — No hay mensajes en claro por mesh
Fail-closed: `MeshPolicy` nunca transporta plaintext de mensajes (`mesh_policy.dart:125-163`);
los metadatos de routing siguen en claro (riesgo aceptado y documentado).
- Fuente: CRYPTO §3:144; THREAT MESH row.

## I-006 — No se reutilizan nonces
Nonce AEAD: único por (clave, mensaje); la política v1 (aleatorio) se sustituye por contador
+ no-reuso con la misma clave (outbox/Isar). Los challenges usan nonces CSPRNG 32B single-use.
- Fuente: CRYPTO §3:145-148; DEVICE_MODEL §5.3:225.

## I-007 — No existe identidad de peer no autenticada como vértice de confianza
La auto-aceptación de conexiones entrantes (`nearby_service.dart:772-775`) y la entrega de
`public_key` sin anclaje se eliminan en M3; `profile_exchange` v2 firma + DEVICE_FINGERPRINT
(FINGERPRINT_SPEC, OPEN-002/016). Ningún documento trata `public_key` desnuda como identidad
suficiente.
- Fuente: D12, THREAT T16, CRYPTO §5; FINGERPRINT_SPEC §5.
- Estado: **VALID**.

## I-008 — No hay replay de challenges
`request_challenge` → single-use (`used_at`) + TTL 10 min + ventana `ts ±5 min` +
idempotencia por `challenge_id`. Replay de mensajes: `msg_n`/`prev_n` en M4.
- Fuente: DEVICE_MODEL §5.2/§5.3; THREAT T5/T9/T17.

## I-009 — No hay downgrade silencioso secure → legacy
El paso a v1 solo ocurre con advertencia explícita al usuario y versión negociada; el servidor
marca pares upgraded para no aceptar v1 entre quienes soportan v5 (M5).
- Fuente: MIGRATION_PLAN M3:89-93, M5:103-108.

## I-010 — No hay migración destructiva sin rollback definido
Cada fase M*-M5: DDL idempotente, footer de versión como source of truth por fila,
transacciones por fase, y estado recuperable. Nunca se borra/re-escribe historial.
- Fuente: MIGRATION_PLAN §1:24-26, §4; MIGRATION_FAILURE_MATRIX (OPEN-012, 12 escenarios).
- Estado: **VALID**.

## I-011 — No se afirma Forward Secrecy sobre historial legacy
Ningún documento describe el historial v1 como protegido por FS. Los mensajes v1 pueden ser
descriptibles si cae una privada X25519 estática; la FS se aplica solo a mensajes nuevos (M4).
- Fuente: CTO_REVIEW_REQUIRED §3.1; THREAT T13:142-144.

## I-012 — El servidor no es custodio de claves privadas
Supabase nunca posee privadas: solo públicas, hashes de recovery y blob envuelto. Sin excepciones.
- Fuente: D5:57-58, D1:13, THREAT T12/T13.

## I-013 — El primer enroll no otorga estado activo sin confirmación firmada
`device_1` se crea `pending` y solo `confirm_bootstrap` (firma Ed25519 + código 1-uso) lo
activa. Ninguna operación privilegiada con device pendiente — máquina PENDING→ACTIVE de
`PHASE_2_BOOTSTRAP_POLICY.md` §4 (I-030).
- Fuente: R-013 → OPEN-003; IDENTITY §5.C.3:210-212; THREAT T4:70.
- Estado: **VALID**.

## I-014 — Sin acceso directo a tablas de identidad/recovery
REVOKE ALL público (anon/authenticated) sobre `account_identity`, `devices`, `device_keys`,
`device_challenges`, `device_revocations`, `recovery_credentials`; acceso solo vía RPC
SECURITY DEFINER. Se adopta **solo-RPC** (R-023 resuelto: la RLS directa de CRYPTO
§7.1:321-322 queda superada); ninguna tabla de identidad admite SELECT directo.
- Fuente: DEVICE_MODEL §1.1:31, §1.2:46-47, §1.6; HANDOFF §8.
- Estado: **VALID**.

## I-015 — `account_id` inmutable e irreutilizable
Creado server-side, jamás cambia durante la vida de la cuenta; nunca se reasigna a otra fila;
`auth.uid()` efímero es solo sesión.
- Fuente: DEVICE_MODEL §1.1:20; IDENTITY §4:144-146; T1.

## I-016 — El recovery code, una vez usado, deja de ser válido
Single-use por código + rate-limit de intentos por account (5/15 min con bloqueo progresivo —
OPEN-009, `PHASE_2_RECOVERY_POLICY.md` §4). El uso de un código rota el juego completo:
re-envuelve el blob y revoca el anterior.
- Fuente: CRYPTO §7.2:324-328; RECOVERY_POLICY §4.
- Estado: **VALID**.

## I-017 — Fingerprint determinista y canónico
Fingerprint v1 (`PHASE_2_FINGERPRINT_SPEC.md`): **dos** fingerprints — ACCOUNT_FINGERPRINT
(`"ZONE-FP-1\0"‖"ACC"‖account_id‖identity_pk`) y DEVICE_FINGERPRINT
(`"ZONE-FP-1\0"‖"DEV"‖account_id‖device_id‖device_pk`) — SHA-256 + Base32 sin padding,
20 chars en 4×5, canonicalización base64/UUID fija (OPEN-002/015/016). **Sin X25519 en el
input.** Dos implementaciones independientes producen los mismos bytes; KAT obligatorio en M1.
- Fuente: IDENTITY §7; FINGERPRINT_SPEC §2-§4.
- Estado: **VALID** (aclaración aplicada: dos fingerprints, no uno).

## I-018 — Serialización canónica única para firmas
Solo se firma `canonical_payload_v1` (JSON ordenado, sin espacios, UTF-8, `extra` obligatorio);
el servidor re-serializa y nunca confía en bytes del cliente. El transcript del handshake se
especifica aparte (las 6 precisiones de OPEN-015 se adoptaron en DEVICE_MODEL §5).
- Fuente: DEVICE_MODEL §5.1/§5.3; THREAT T7.
- Estado: **VALID**.

## I-019 — Migraciones idempotentes y reversibles
Misma fase ejecutada dos veces = sin efecto (DDL `IF NOT EXISTS`, guard de versión);
reversión definida por fase; sin "limpieza" de datos como parte de la migración.
- Fuente: MIGRATION_PLAN §1; MIGRATION_FAILURE_MATRIX (OPEN-012).
- Estado: **VALID**.

## I-020 — Sin doble keypair / fuente única de verdad de clave
El alias `_publicBase64` y el segundo keypair de `_registerInSupabase` se resuelven en M0:
una única fuente (SecureStorage) usada por mesh y nube.
- Fuente: IDENTITY §1.2:52-56; MIGRATION_PLAN M0:59-61.

## I-021 — La retirada del claim no deja usuarios legacy sin vía de acceso
Mientras existan cuentas `mode=legacy` sin devices, existe un camino (acotado y rate-limitado)
para restaurar sesión tras reinstalación, o su equivalente (OPEN-011). El claim legacy no se
retira antes de M5 ni antes de que el recovery esté disponible para toda la base — reglas
REGL-1..3 en `PHASE_2_LEGACY_ACCESS_POLICY.md` §3-§5.
- Fuente: R-025; LEGACY_ACCESS_POLICY.
- Estado: **VALID** (reforzado por I-028).

## I-022 — `verify_zone_id` no es un oráculo de enumeración
Respuesta no distinguible entre "existe"/"no existe", con rate-limit; sin exponer
`id`/`zone_id` de otros (Z-103). OPEN-010 resuelto: `verify_zone_id` se mantiene con esta
forma (pre-check de recovery, nunca oráculo).
- Fuente: THREAT T3:62-63; `secure_claim_zone_id.sql:129-144`.
- Estado: **VALID**.

## I-023 — El estado del ratchet es secreto local
`SessionState` jamás sube al servidor; solo parámetros públicos viajan por `device_keys`
(sync multi-device). Restauración tras reinstalación = re-sync, no descarga de estado.
- Fuente: MIGRATION_PLAN §5.2:128-136; CRYPTO §6.3.

## I-024 — El recovery no degrada la garantía del historial
Con la semántica de OPEN-001 (Opción A, `PHASE_2_RECOVERY_POLICY.md`), la recuperación
restaura la identidad Ed25519 y NUNCA la X25519 v1: el historial v1 queda ilegible y esto se
muestra con placeholder, nunca con "promesa" de descifrado.
- Fuente: D5/D9; RECOVERY_POLICY §2.
- Estado: **VALID** (reforzado por I-025).

---

## I-025 — El recovery jamás restaura la X25519 v1 ni el historial legacy (NUEVO — FASE 2.0.2)
"Recuperar la cuenta" ≠ "recuperar mensajes": ACCOUNT/DEVICE recovery están separadas de
MESSAGE HISTORY / LEGACY KEY / RATCHET STATE recovery. El blob envuelto puede contener la
identidad Ed25519 de cuenta pero **jamás** la X25519 v1 ni claves de sesión/ratchet; el
historial v1 tras recovery queda ilegible (placeholder `🔒` actual).
- Fuente: RECOVERY_POLICY_V1 §2-§4 (OPEN-001); D5/D9; I-011.
- Prueba: tests de recovery (CRYPTO §11.4) — el blob no contiene X25519; historial v1
  ilegible tras recovery.

## I-026 — El fingerprint nunca es secreto ni credencial (NUEVO — FASE 2.0.2)
Ningún fingerprint se usa como clave de RPC, prueba de posesión ni entrada de recovery; su
conocimiento no concede ninguna operación. Input canónico **sin X25519**; ACCOUNT y DEVICE
fingerprints según FINGERPRINT_SPEC v1.
- Fuente: FINGERPRINT_SPEC §1/§5 (OPEN-002/016).
- Prueba: revisión de RPCs — ningún fingerprint en funciones de autenticación.

## I-027 — Única secuencia de bootstrap por cuenta en curso (NUEVO — FASE 2.0.2)
Una sola `bootstrap_attempt` activa por cuenta; enrolls concurrentes rechazados (409 +
audit); solicitar un nuevo código invalida el anterior (rotación).
- Fuente: BOOTSTRAP_POLICY §2-D/§3 (CONCURRENT_REQUESTS + REISSUE; OPEN-004).
- Prueba: tests de concurrencia (dos enrolls simultáneos → uno 409).

## I-028 — Ninguna cuenta legacy sin devices queda sin vía de reinstalación M0-M5 (NUEVO — FASE 2.0.2)
Entre M0 y M5, un usuario `mode=legacy` sin devices siempre tiene una ruta documentada:
claim acotado (hasta M5) **o** recovery (emitida en el primer arranque post-M1); la retirada
del claim se condiciona a REGL-1..3 (LEGACY_ACCESS_POLICY §3-§5).
- Fuente: LEGACY_ACCESS_POLICY (OPEN-011); R-025.
- Prueba: test de regresión de reinstalación legacy (M1 y M5).

## I-029 — El bootstrap code cumple BOOTSTRAP_SECURITY_POLICY (NUEVO — FASE 2.0.2)
TTL 10 min, single-use, rate-limit 3 emisiones/15 min por account+uid/IP, máx 5 intentos
(LOCKED 15 min), re-emisión invalida la anterior, binding a account+attempt, audit por
evento (emisión/confirmación/cancelación/expiración). El código expira siempre; no es
credencial persistente.
- Fuente: BOOTSTRAP_POLICY §3 (OPEN-004).
- Prueba: tests de fuerza bruta (el 6º intento bloquea) y de re-emisión (el anterior revocado).

## I-030 — Los estados de dispositivo siguen la máquina formal (NUEVO — FASE 2.0.2)
Transiciones deterministas: (ninguno) → PENDING → (confirm_bootstrap) → ACTIVE; PENDING —
timeout→ (artefactos GC; la cuenta legacy queda intacta); PENDING —max attempts→ LOCKED;
PENDING —cancel→ KILLED; ACTIVE —revoke→ REVOKED/COMPROMISED. Sin transiciones indefinidas;
PENDING carece de todo derecho (no autoriza, no lee, no envía, no recibe secretos).
- Fuente: BOOTSTRAP_POLICY §4 (OPEN-003); DEVICE_MODEL §1.2.
- Prueba: tests de máquina de estados sobre `devices.status`.

---

## Verificación por fase (criterio de salida sugerido)

| Fase | Invariantes cubiertos | Tests |
|---|---|---|
| M0 | I-020, I-005 (sin regresión) | `flutter analyze` 0 · tests v1 |
| M1 | I-001…I-004, I-008, I-013…I-015, I-018, I-021, I-022, I-025…I-030 | T1-T4, T7-T11, T14-T15 + KAT fingerprint |
| M2 | I-005…I-006, I-010, I-011, I-019 | v1↔v3, RFC 5869 KAT |
| M3 | I-002, I-007, I-017, I-018, I-022 | T6, T12, T16 |
| M4 | I-006, I-008, I-011, I-023 | T5, T9, T17 + FS/PCS vectors |
| M5 | I-009, I-011, I-019, I-021, I-028 | retiro legacy + historial |

> ⚠️ **La activación de los invariantes (incluidos I-025…I-030) queda condicionada a la
> firma de la puerta `PHASE_2.0.2_CTO_GATE.md`** (resoluciones PROPOSED, no APPROVED).
> Ningún invariante se considera activo para bloquear una fase sin esa firma.