# PHASE 2.0 — Modelo de Amenazas de ZONE

> **Tipo:** Diseño definitivo (FASE 2.0 · puerta CTO) — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** REVISIÓN PENDIENTE DE CTO · **FASE 2.0.2**:
> T1-T17 revisados post-decisiones y estados corregidos (§3.1)
> **Visión:** evaluar el diseño resultante (v2-v5) contra amenazas; el estado "HOY" es el actual en producción.

Este documento responde a las secciones 16 y 17 del mandato: matriz de propiedades de
seguridad (IMPLEMENTADO/DISEÑADO/NO IMPLEMENTADO/NO VERIFICABLE) y las **17 pruebas de
amenaza** con precondiciones, ataque, resultado esperado/actual y mitigación.

---

## 1. Matriz de propiedades de seguridad (diseño objetivo vs hoy)

| Propiedad | HOY (evidencia) | Diseño v2-v5 | Clasificación final |
|---|---|---|---|
| Autenticación | Sin firma del sender; RLS por match (`supabase_schema.sql:446-468`) | Ed25519 en handshake y RPC | 🔒 DISEÑADO |
| Confidencialidad | AEAD ChaCha20-Poly1305 (`chat_e2ee_service.dart:60-79`) | Se mantiene + AAD | ✅ IMPLEMENTADO (v1) · DISEÑADO (v3+) |
| Integridad | MAC Poly1305 (`chat_e2ee_service.dart:93-109`) | Se mantiene | ✅ IMPLEMENTADO |
| Replay protection | Dedup LRU/TTL mesh (`mesh_policy.dart`) | nonce single-use + contador ratchet + `used_at` | ⚠️ PARCIAL HOY → DISEÑADO |
| MITM resistance | Ninguna (auto-acepta conexiones `nearby_service.dart:772-775`) | Fingerprint + firma + transcripto | ❌ HOY → DISEÑADO (M3) |
| Forward Secrecy | **NO** (shared secret estático) | Double Ratchet v5 | ❌ HOY → DISEÑADO (M4) |
| Post-Compromise Security | **NO** | Ratchet (DH periódico) | ❌ HOY → DISEÑADO (M4) |
| Key rotation | **NO** (nunca se rota `public_key`) | `device_keys` versionado + firma | ❌ HOY → DISEÑADO (M2+) |
| Device revocation | **NO** (no hay devices) | `devices.status` + firma + auditoría | ❌ HOY → DISEÑADO (M1) |
| Account recovery | **NO** | recovery codes hash + blob envuelto | ❌ HOY → DISEÑADO (M1/M5) |
| Multi-device | **NO** | devices + device_keys + ratchet por par | ❌ HOY → DISEÑADO (M1/M4) |
| Offline | Mesh offline-first en claro de routing; cifra mensajes | Se mantiene; revocación propaga offline | ⚠️ PARCIAL HOY → DISEÑADO |
| Mesh (confidencialidad de mensaje) | AEAD fail-closed (`mesh_policy.dart`) | Se mantiene | ✅ IMPLEMENTADO |
| Server compromise | Servidor NO tiene privadas (solo públicas) | Igual + sin recovery en claro | ✅ IMPLEMENTADO (núcleo) |
| Database compromise | Ciphertext en DB; server sin claves | Igual + blobs envueltos | ✅ IMPLEMENTADO (núcleo) |
| Posesión de cuenta (ZONE-ID) | **NO** demostrable | Firma + challenge + bootstrap | ❌ HOY → DISEÑADO (M1) |

---

## 2. Las 17 pruebas de amenaza

Cada prueba: **PRECONDICIONES → ATAQUE → RESULTADO ESPERADO → RESULTADO ACTUAL → MITIGACIÓN**.
"RESULTADO ESPERADO" es el estado tras implementar el diseño; "RESULTADO ACTUAL" es el
estado hoy en producción (evidencia del código).

### T1 — Atacante conoce el ZONE-ID

- **Precondiciones:** El atacante tiene `ZONE-XXXXXXXX` de un usuario (visto en pantalla, perfil, mesh).
- **Ataque:** `signInAnonymously()` + `claim_zone_id(p_zone_id)`; intenta adueñarse del uid.
- **Resultado esperado:** **DENEGADO** — el claim ya no existe; se exige `bootstrap` con sesión del dueño + señuelos de actividad, o `recover` con recovery code. El ZONE-ID por sí solo no da acceso (`account_id` inmutable).
- **Resultado actual:** ⚠️ **POSIBLE** si el atacante pasa el rate-limit: hoy `claim_zone_id` mueve `users.id` a su uid (`supabase_schema.sql:673`). Solo el rate-limit 5/15 min lo frena (`secure_claim_zone_id.sql:65-73`).
- **Mitigación:** Fases M1+M2 (eliminar claim, firma, account_id inmutable, eventos anti-apropiación: IDENTITY_ARCHITECTURE §5.C).

### T2 — Atacante crea anonymous auth

- **Precondiciones:** Cualquiera puede `signInAnonymously()` (requerido offline-first; no se deshabilita).
- **Ataque:** Crear miles de uids anónimos para enumerar/atacar.
- **Resultado esperado:** Los uids anónimos no otorgan derechos sobre ninguna cuenta; RPCs exigen firma + challenge con TTL; rate-limit por IP/uid en RPCs sensibles.
- **Resultado actual:** Un uid anónimo es lo que **usamos como usuarios reales** hoy; por sí solo solo puede crear su propia fila `users` (`users` RLS self-scoped, `supabase_schema.sql:213-224`).
- **Mitigación:** M1 separa sesión anónima (`auth.uid()` efímero) de `account_id` estable; los RPCs de identidad exigen challenge firmado.

### T3 — Atacante intenta claim

- **Precondiciones:** T1 + conoce la mecánica del RPC.
- **Ataque:** Enumerar `ZONE-*`, probar `claim_zone_id`, usar `verify_zone_id` como oráculo.
- **Resultado esperado:** `verify_zone_id` complementa y NO expone datos sensibles; claim eliminado; `verify_zone_id` ya no revela `id`/`zone_id` (Z-103); nueva ruta de recuperación con rate-limit.
- **Resultado actual:** PARCIAL — `verify_zone_id` ya no expone oráculo (Z-103, `secure_claim_zone_id.sql:129-144`), pero `claim_zone_id` sigue dando apropiación tras rate-limit.
- **Mitigación:** M1 (eliminar claim) + M5 (fail-closed en cuentas frías).

### T4 — Atacante intenta registrar su propia Ed25519 como la de la víctima

- **Precondiciones:** No tiene sesión de la víctima; conoce su ZONE-ID.
- **Ataque:** `bootstrap_account(zone_id=víctima, ...)` con su clave.
- **Resultado esperado:** **DENEGADO** si la cuenta ya tiene dispositivos activos o la cuenta no está en `legacy`; si es una cuenta legacy **fría** (sin actividad), el bootstrap se bloquea por fail-closed (canal fuera de banda); si es reciente, se emite **evento de apropiación** y el bootstrap queda `pending` hasta confirmación con firma.
- **Resultado actual:** NO APLICA (no existe bootstrap hoy; el "registro de Ed25519" no existe — estaría medido por `claim_zone_id`).
- **Mitigación:** señuelos de actividad + `pending` + evento visible al dueño (IDENTITY_ARCHITECTURE §5.C).

### T5 — Atacante repite challenge

- **Precondiciones:** capturó un `request_challenge` legítimo.
- **Ataque:** Re-enviar el mismo nonce o reintentar con el mismo challenge_id.
- **Resultado esperado:** `verify_signed_op` rechaza: nonce **single-use** (`used_at`), `expires_at` 10 min, ventana `ts ±5min`, idempotencia por challenge_id.
- **Resultado actual:** NO APLICA (no hay challenge todavía).
- **Mitigación:** DEVICE_MODEL §5 (canonical + single-use), probado en pruebas de T5.

### T6 — Atacante modifica el transcript

- **Precondiciones:** MITM del handshake `A↔B`.
- **Ataque:** Cambiar `identity_pk`/`x25519_pk`/`nonce` en tránsito.
- **Resultado esperado:** La firma Ed25519 sobre el transcript **canónico completo** no verifica → **ABORTA** (CRYPTO_CTO_REVIEW §5.2: `sig` cubre todos los bytes previos).
- **Resultado actual:** NO APLICA (no hay handshake; el mesh `profile_exchange` va en claro y se auto-acepta).
- **Mitigación:** handshake v4 (M3), fingerprint out-of-band.

### T7 — Atacante cambia device_id

- **Precondiciones:** Logró capturar una firma de dispositivo válida pero altera el `device_id` del payload.
- **Ataque:** Intercambiar `device_id` en `register_device`/`revoke_device`.
- **Resultado esperado:** El `canonical_payload_v1` incluye `device_id` **dentro** de lo firmado; cambiar el id rompe la firma (re-serialización server-side byte a byte) → rechazo.
- **Resultado actual:** NO APLICA.
- **Mitigación:** DEVICE_MODEL §5.3 (“nunca firmar JSON arbitrario del cliente; re-serializar canónico”).

### T8 — Atacante reemplaza la public key

- **Precondiciones:** Atacante con control de un device (robado/comprometido) intenta sustituir `device_keys` o la X25519 del par.
- **Ataque:** `rotate_key` con clave de atacante o inyectar `device_public_key` nueva.
- **Resultado esperado:** `rotate_key` exige firma generada por la **clave previa** (cadena de confianza) y/o firma de la cuenta; el fingerprint del device cambia visiblemente → el par aborte (M3). `device_keys` versionada evita silencioso.
- **Resultado actual:** Actualmente solo la preservación de `public_key` en DB evita overwrite (`checkAndFixRegistration` 357-369) — el atacante con uid del dueño sí podría upsert; RLS self-scoped lo limita al dueño pero no lo cierra a física de dispositivo.
- **Mitigación:** firma de cuenta para rotaciones + fingerprint visible (M1+M3).

### T9 — Atacante reutiliza un challenge (replay de operación firmada)

- **Precondiciones:** T5 + captura del payload firmado completo.
- **Ataque:** Reintentar `verify_signed_op` con el payload y challenge_id ya usado.
- **Resultado esperado:** `used_at` + idempotencia → **rechazo**; sin efecto.
- **Resultado actual:** NO APLICA.
- **Mitigación:** single-use + auditoría (`device_challenges.used_at`).

### T10 — Atacante registra un segundo dispositivo

- **Precondiciones:** Robó/usó un device activo o comprometió una sesión.
- **Ataque:** Autorizar un device nuevo desde el device comprometido.
- **Resultado esperado:** El alta exige firma de un **device activo** (DR-5); si se detectan varios devices nuevos en corto tiempo → flag de riesgo + notificación; los devices se listan y el dueño real puede revocar.
- **Resultado actual:** NO APLICA (no hay devices); hoy "registrar otro dispositivo" = reinstalar y reclamar (destruye el estado del original).
- **Mitigación:** DEVICE_MODEL §3 (opción F) + auditoría `device_revocations`.

### T11 — Dispositivo revocado intenta operar

- **Precondiciones:** `status=revoked`.
- **Ataque:** Enviar un `verify_signed_op` con la firma del device revocado, o seguir en mesh/relay.
- **Resultado esperado:** RPCs con `purpose` de device exigen `devices.status='active'`; el mesh descarta paquetes del device revocado (validación de estado al sincronizar/revocation_notice); nuevas entregas no se enrutan a él.
- **Resultado actual:** NO APLICA.
- **Mitigación:** validación server-side en cada RPC + propagación mesh (DEVICE_MODEL §6.3).

### T12 — Servidor comprometido

- **Precondiciones:** Atacante controla el server Supabase (auth + API).
- **Ataque:** Leer todas las tablas, suplantar RPCs, ver claves públicas, inyectar claves falsas.
- **Resultado esperado:** El servidor **no posee claves privadas** (privadas solo en SecureStorage) ni recovery en claro (solo hash + blob envuelto). Puede hacer MITM de entrega entre pares, pero **no descifrar contenido** sin las privadas de ambos lados. Drama de trust: la confidencialidad queda en manos del cliente; fingerprints off-band (M3) detectan claves falsas.
- **Resultado actual:** Igual núcleo — el servidor nunca tiene privadas; pero las sesiones v1 estáticas hacen que un compromiso total del servidor (que suplante `public_key` de un peer) permita MITM **sin detección**.
- **Mitigación:** fingerprints + firma Ed25519 (M3) + sin secrets server-side.

### T13 — Base de datos comprometida

- **Precondiciones:** Lectura SQL de la DB (sin Auth API).
- **Ataque:** Leer `messages`, `users.public_key`, `device_keys`, recovery comments.
- **Resultado esperado:** Ciphertext AEAD ilegible sin privadas; recovery codes solo como hashes; blobs envueltos client-side; `device_keys` públicas no ayudan a descifrar. El **historial v1** (estático) SÍ es teóricamente descifrable si el atacante obtiene además una privada X25519 — el riesgo de v1 no se oculta, se mitiga con M4 (FS).
- **Resultado actual:** Ciphertext AEAD (igual); sin recovery; v1 estático vulnerable solo si caen privadas.
- **Mitigación:** M4 (FS) para que la pérdida de una privada NO descifre historial; rotación v3.

### T14 — Pérdida de dispositivo

- **Precondiciones:** Usuario pierde/roban el teléfono con SecureStorage.
- **Ataque:** Acceso físico al material de SecureStorage (técnicas de extracción) y/o uso del dispositivo como "device activo".
- **Resultado esperado:** SecureStorage (Android keystore) protegido; **revocación inmediata** desde otro device (`revoke_device` con firma de cuenta) → el lost device deja de recibir entregas y su `device_keys` pasa a `revoked`; recovery codes permiten reinstalar en otro device (sin recuperar privadas viejas).
- **Resultado actual:** AuthScreen anima a guardar el ID; no hay devices ni revocación; la clave local la custodia solo el keystore; pérdida = pérdida de claves y de historial.
- **Mitigación:** devices + revocación + recovery (M1/M5).

### T15 — Reinstalación

- **Precondiciones:** Mismo usuario reinstala la app sin backup (borrado de SecureStorage).
- **Ataque:** Iniciar sesión por ZONE-ID en el nuevo install.
- **Resultado esperado:** Se autentica vía recovery/devices: o bien autoriza el nuevo device desde otro activo, o bien recupera la cuenta con recovery code. La X25519 vieja NO se recupera (historial v1 cifrado para siempre) → mensajes nuevos con clave nueva y fingerprint nuevo.
- **Resultado actual:** Se reclama por `claim_zone_id` (posible robo si su ZONE-ID se hizo público); el historial cloud queda descifrable solo por el par — el nuevo install obtiene underscore de mensajes ilegibles (`🔒` placeholder).
- **Mitigación:** M1 (devices) + M5 (recovery) para que reinstalar NO regale la cuenta a un tercero.

### T16 — MITM mesh

- **Precondiciones:** Peer malicioso en proximidad BLE entre A y B.
- **Ataque:** Interponerse, responder `profile_exchange` con su clave, capturar y reenviar.
- **Resultado esperado:** Con handshake v4 (M3): la firma Ed25519 + fingerprint por pantalla/QR detecta la clave falsa → el usuario NO confirma el peer; la sesión del atacante queda inválida.
- **Resultado actual:** 🚨 **VULNERABLE** — `_onConnectionInitiated` auto-acepta (`nearby_service.dart:772-775`) y `profile_exchange` va en claro; el MITM puede ejecutarse sin detección.
- **Mitigación:** M3 (handshake autenticado + fingerprint) + validación de firma en paquetes mesh v2.

### T17 — Replay mesh

- **Precondiciones:** Atacante captura paquetes `mesh_msg` cifrados y conoce los metadatos.
- **Ataque:** Reinyectar paquetes viejos dirigidos a un peer.
- **Resultado esperado:** Con ratchet (M4): `msg_n`/`prev_n` + nonce ya usado → rechazo por orden de contador. HOY la deduplicación LRU/TTL (`mesh_policy.dart:64-123`) mitiga parcialmente en ventana de 15 min (replay fuera de TTL reentra).
- **Resultado actual:** ⚠️ PARCIAL — dedup temporal; el fallback `queueForKey` (`mesh_policy`) no diferencia reinyección legítima de replay posterior.
- **Mitigación:** M4 (contadores + nonce unique) — problema cerrado en diseño de ratchet (§5.3 MIGRATION_PLAN).

---

## 3. Resumen ejecutivo de la matriz

- **HOY, producción** está bien endurecida en *RLS, grants y fail-closed de mesh* (todo
  verificado en la auditoría), pero **no tiene autenticación criptográfica de
  identidad, ni devices, ni FS, ni recovery**.
- **El diseño FASE 2.0** cierra T1-T17 con excepción de dos riesgos inherentes que se
  documentan (no se "arreglan" con criptografía): (1) compromiso total de servidor
  (requiere fingerprints off-band, M3); (2) historial v1 cifrado con claves estáticas
  (se mitiga con FS en M4, no es retroactivo).
- **Cada fase de MIGRATION_PLAN añade las pruebas T correspondientes** (ver sección 2).

---

## 3.1 Revisión FASE 2.0.2 (post-resolución de OPEN) — estados correctos

Tras resolver OPEN-001…018 (PROPOSED) se revisó cada amenaza. Estados usados con rigor:
**DISEÑADO** = mitigación especificada en documentos (sin código); **PLANEADO** = fase futura
programada (M4); **IMPLEMENTADO** = en producción hoy; **VERIFICADO** = demostrado con pruebas
tras implementar. Ninguna T se declara "mitigated" solo por diseño.

| T | Mitigación (post 2.0.2) | Estado | Riesgo residual | Fase | Dependencia | Evidencia |
|---|---|---|---|---|---|---|
| T1 | Claim acotado a `mode=legacy` sin devices; recovery/device para el resto; ZONE-ID ≠ posesión | DISEÑADO | Sesión legacy comprometida pre-M1 (aceptado, documentado) | M1 | LEGACY_ACCESS_POLICY (OPEN-011); I-001/I-028 | tests claim deny (M1) |
| T2 | RPCs con challenge firmado + rate-limit; uid anónimo sin derechos | DISEÑADO | — | M1 | DEVICE_MODEL §5 | tests T2 (M1) |
| T3 | verify_zone_id sin oráculo + rate-limit (OPEN-010) | DISEÑADO | Enumeración residual nula | M1 | DECISION_RESOLUTION (OPEN-010); I-022 | tests Z-103 |
| T4 | Máquina PENDING→ACTIVE; PENDING sin derechos; cancel + OOB frío | DISEÑADO | Apropiación con sesión robada pre-M1 (aceptado) | M1 | BOOTSTRAP_POLICY (OPEN-003); I-013/I-030 | tests bootstrap (M1) |
| T5 | Challenge single-use + TTL + ventana (bootstrap y ops) | DISEÑADO | — | M1 | I-008 | tests T5 |
| T6 | Firma sobre transcript canónico + DEVICE_FINGERPRINT | DISEÑADO | — | M3 | FINGERPRINT_SPEC (OPEN-002/016) | tests T6/T16 |
| T7 | device_id dentro del payload firmado (re-serialización canónica) | DISEÑADO | — | M1 | I-018 | tests T7 |
| T8 | rotate_key firma `device_sk` activo + fingerprint visible | DISEÑADO | — | M1+M3 | OPEN-008; I-003 | tests T8 |
| T9 | `used_at` + idempotencia por challenge_id | DISEÑADO | — | M1 | I-008 | tests T9 |
| T10 | Alta firmada por device activo + QR ligado a device_2_fp + revocación | DISEÑADO | Device robado que firma (documentado) | M1 | OPEN-005 | tests T10 |
| T11 | RPCs exigen `status=active`; mesh descarta revocado | DISEÑADO | — | M1 | DEVICE_MODEL §6 | tests T11 |
| T12 | Servidor sin privadas; fingerprints off-band detectan claves falsas | DISEÑADO (residual inherente) | MITM en entrega; confianza en cliente (no eliminable) | M3 | I-012 | tests T12/T16 |
| T13 | FS en M4 (mensajes nuevos); v1 sin FS retroactiva (no prometido) | DISEÑADO (residual: historial v1) | Historial v1 descifrable si cae la privada estática (aceptado) | M2/M4 | I-011; OPEN-006 | tests T13 + FS vectors |
| T14 | Revocación desde cualquier device + recovery (sin privadas viejas) | DISEÑADO | Pérdida sin recovery = pérdida de datos (fail-closed aceptado) | M1/M5 | RECOVERY_POLICY (OPEN-001) | tests T14 |
| T15 | Reinstalación: device/recovery/claim acotado; X25519 v1 irrecuperable | DISEÑADO | — (sin lockout: I-028) | M1/M5 | LEGACY_ACCESS_POLICY (OPEN-011) | tests regresión reinstall |
| T16 | Handshake v4 + DEVICE_FINGERPRINT (comparación off-band) | DISEÑADO | — | M3 | FINGERPRINT_SPEC | tests T16 |
| T17 | msg_n/prev_n + nonce único (ratchet); dedup HOY = temporal | PLANEADO | Replay parcial HOY (dedup TTL mesh) | M4 | OPEN-006/014 | tests T17 (M4) |

> **Regla:** los estados DISEÑADO/PLANEADO pasan a VERIFICADO solo al implementar la fase con
> las pruebas indicadas; sin código, ninguna T de esta tabla se considera cerrada (I-002:
> X25519 jamás firma, verificado por git grep en M1+).