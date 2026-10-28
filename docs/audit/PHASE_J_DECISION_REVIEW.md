# PHASE J — Revisión de decisiones CTO (informe)

**Fecha:** 2026-10-27
**Modo:** revisión de decisiones en modo solo lectura. Durante la revisión no se editó, creó, movió ni eliminó ningún archivo, no se ejecutaron migraciones ni accesos a entornos remotos, no se imprimió ningún secreto y no se hizo `git commit`/`git push`. Este documento es el único artefacto añadido: se escribió *después* de la revisión, por autorización expresa del propietario.
**Base de evidencia:** `HEAD = origin/main = a5a7080` (*feat(phase-2): identity foundation, Z-2xx hardening, P2P AKE, gate docs (289/289)*). Suite local: **289/289 PASS**. `flutter analyze --no-pub` limpio. Fail-closed de release verificado dos veces en esta fecha (exit 1, mensaje *"Release signing is not configured. Refusing to build a release with debug keys"*).
**Estado del gate que este informe registra:** ❌ **NO-GO**. El informe **no aprueba ninguna decisión por inferencia**: concentra las decisiones pendientes del propietario (DEC-F1…DEC-H1), su evidencia y los criterios verificables para declarar PASS. La aprobación formal de cada DEC-\* debe registrarse con firma del propietario en este documento o en los docs fuente.

**Soportes leídos íntegros:** `PHASE_F_EXISTING_USER_LOGIN.md` (§3.2.1–§3.2.7, §3.5, §10), `PHASE_G_E2EE_KEY_ESTABLISHMENT.md` (§2–§9), `E2EE_RATCHET_ALTERNATIVES.md` (§2–§3), `PHASE_E_P2P_AUTH_DESIGN.md` (§4, §7.2–§7.9, §10), `Z212_STAGING_RUNBOOK.md` (§0–§11), `RELEASE_SIGNING.md`, `BETA_READINESS_GATE.md` (§8–§9), `PHASE_H_TWO_DEVICE_MATRIX.md` (H-01…H-15), `PHASE_2_RECOVERY_POLICY.md` (I-025) y `PHASE_2_LEGACY_ACCESS_POLICY.md` (REGL-1/REGL-2); más el código real: `lib/services/chat_e2ee_service.dart` y los anclajes de producción (`nearby_service.dart:907`/`:1044`, `p2p_auth`, `p2p_handshake`).

## Convención de etiquetas (obligatoria)

| Etiqueta | Significado estricto |
|---|---|
| **DISEÑADO** | Propuesta/documento sin código. |
| **IMPLEMENTADO** | Existe en el código del árbol. |
| **PROBADO LOCALMENTE** | Suite local verde (289/289; contrato handshake 24 + 18 tests de integración con ancla). |
| **VALIDADO EN ENTORNO REAL** | Staging, PostgreSQL remoto o dispositivos físicos, con evidencia fechada. |
| **NOT RUN / NOT IMPLEMENTADO / BLOCKED** | Sin ejecutar / sin cablear en producción / esperando decisión o insumo externo. |

---

## 1. Alternativa A — inicio de sesión con usuario existente

### 1.1 Las cinco ambigüedades de `PHASE_F` §3.2.5

| # | Ambigüedad (texto de §3.2.5, resumida) | Resolución propuesta en §10.4 (**sin aprobar**) |
|---|---|---|
| 1 | **Generación de `account_id`** — ¿UUID server-side o derivado de la Ed25519? *"Un UUID server-side es sustituible en creación; un UUID derivado es autocertificante pero añade linkabilidad. La política de recovery asume que la identidad de cuenta es la Ed25519"* | UUID `gen_random_uuid()` server-side |
| 2 | **Semántica de `messages.sender_id`** — ¿device o account? *"Afecta autoría, el AAD de Fase G y el destino de la FK"* | `device_id` para autoría/RLS; vista de mensajería por `account_id` |
| 3 | **Binding del primer device** — *"no puede resolverse con TOFU silencioso"* (el mismo defecto que Z-004) | Anclaje de fingerprint fuera de banda (OOB) + señuelos UI + registro de auditoría |
| 4 | **Backfill legacy** — ¿`account_id = users.id` o UUID nuevo con tabla de mapeo? | `account_id = users.id` (grafo social intacto, sin rebind) |
| 5 | **Propagación de revocación** — ¿tabla server-side, lista firmada o ambas? ¿qué consulta P2P sirve cuando no hay red? | Tabla `device_revocations` server-side como única verdad inicial; lista firmada a fase posterior |

Ninguna de las cinco resoluciones está firmada; las decisiones correspondientes son **DEC-F2…DEC-F6**.

### 1.2 A1 / A2 / A3 — comparación con las definiciones reales (§3.2.2–§3.2.4)

| Criterio | **A1** — rebind `UPDATE users SET id` transaccional | **A2** — `account_identity` + `devices` + `current_account_id()` | **A3** — device bridge sobre `auth.uid()` propietario |
|---|---|---|---|
| **Seguridad** | `users.id` pasa a ser un binding mutable; un bug de rebind mueve todo el grafo social; los RPC que solo comprueban `auth.uid()` (sin JOIN a `users`) pueden seguir operando con el JWT del uid viejo | Identidad de cuenta inmutable; punto de fallo típico = sobre-concesión en `current_account_id()` (debe devolver `NULL` ante la duda y estar indexada) | No resuelve las RLS de `SELECT`: exige RPC SECURITY DEFINER por consulta (más superficie) o emitir JWT con `service_role` / hook custom, no soportado por Auth para Auth anónimo |
| **Compatibilidad** | No reescribe las 9 FK (`ON UPDATE CASCADE`), ni las 21 policies, ni las queries | Reapunta 9 FKs, reescribe 21 policies y 45 referencias a `auth.uid()` (eran 38 el 23-10-2026; el esquema se re-contó en esta revisión) | Duplica la lógica de autorización; cada lectura/escritura pasa por RPC auditable |
| **Recuperación** | Frágil: *"la revocación efectiva depende de que no exista fila `users` para el uid viejo"* (no de `signOut`); `zone_claim_attempts.uid` queda stale; la carrera exige bloqueo de fila + código single-use | Multi-device natural; revocación por device; el recovery mantiene el `account_id` | Recuperación e impermeabilidad no definidas en el documento |
| **Abuso potencial** | Punto único de fraude: recuperación concurrente (mitigable con `SELECT … FOR UPDATE` + auditoría) | El riesgo raíz sigue siendo código + blob: quien lo tenga controla la cuenta (§3.3 de la política de recovery) | El atacante que firme con su device key puede actuar "en nombre de" la cuenta vía RPC auditable |
| **Migración** | Fase corta; el único entregable realista para beta | Proyecto M1–M5 con staging obligatorio | **Rechazada** (§10.3) |

### 1.3 Decisión productiva registrada y bloqueo

El gate ya registró la dirección de producto: **Alternativa A (prueba de posesión)** — no implementada. La decisión pendiente es única y binaria: **Ruta A2 (objetivo)** vs **Ruta A1 como shim condicionado** (con fecha de salida). Pre-requisito común obligatorio a ambas: fix fail-closed del orden del cliente (ver abajo, R-13) y el bloqueo de la carrera del RPC de recovery (§3.2.2). Consecuencia de no decidir: cuarentena de usuario existente indefinida → NO-GO se mantiene.

### 1.4 Matriz de aceptación R-01…R-14 (§3.2.7) — **0/14 NOT RUN**

R-01 recovery legítima · R-02 suplantación solo-ZONE-ID · R-03 código erróneo · R-04 sin códigos (sin backdoor) · R-05 storage corrupto fail-closed (prohibido `deleteAll()`) · R-06 replay de challenge · R-07 recovery concurrente · R-08 claim legacy acotado · R-09 claim de cuenta segura rechazado (REGL-2) · R-10 blob manipulado · R-11 blob entre cuentas (AAD) · R-12 device revocado no firma · R-13 orden fail-closed del cliente · R-14 downgrade de recovery. La clasificación automatizable ↔ dos dispositivos ya está hecha en el gate (§8.2, P0-3). PASS exige verdes en staging con **dos dispositivos físicos** + revisión CTO del modelo de amenazas.

### 1.5 Políticas de recovery relacionadas

- **`PHASE_2_RECOVERY_POLICY.md` (RECOVERY_POLICY_V1):** el recovery **no restaura** la X25519 v1 ni el historial v1 (**I-025**); las *cinco recuperaciones son cosas distintas* (§1); el material criptográfico en el blob envuelto está prohibido para claves X25519 (§3.3).
- **`PHASE_2_LEGACY_ACCESS_POLICY.md`:** REGL-1 ventana M0–M5. §3.5 de `PHASE_F`: la cuarentena total actual es **más estricta** que la política aprobada porque el puente de migración no existe — A debeallows migrar usuarios legacy **sin** reabrir el claim inseguro para cuentas seguras (REGL-2). → DEC-F7.

---

## 2. E2EE y ratchet

### 2.1 Esquema actual (verificado en código, no inferido)

`lib/services/chat_e2ee_service.dart`: X25519 **estático-estático**; el secreto compartido se usa **crudo** como `SecretKey` de ChaCha20-Poly1305 (`PHASE_G` §2.1: sin HKDF, sin `salt`, sin `info`, sin separación por dirección) · **sin AAD** (§2.2: reordenar, borrar o reinyectar ciphertexts no se detecta) · **sin anclaje** de la clave del peer (§2.3: el servidor puede sustituir `public_key` y leer) · **dos caminos divergentes** cloud/mesh (§2.4) · sesiones `sk_<zoneId>` en SecureStorage (§2.5) · la afirmación falsa de forward secrecy ya **corregida en el código** (`chat_e2ee_service.dart:59–66`; paso 1 de `PHASE_G` §6.6, hecho en `a5a7080`). Tabla estado↔objetivo: `PHASE_G` §2.8. Amenazas T1–T12 mapeadas en §3.3.

### 2.2 Sustentabilidad de cada alternativa (fuentes identificables, verificación del 2026-10-27)

| Candidata | Fuente (verificada) |
|---|---|
| `libsignal_protocol_dart` 0.8.2 | pub.dev (GPL-3.0; publisher mixin.dev; publicado 20-06-2026; ~16,4k descargas) |
| `libsignal` 9.0.0 | pub.dev (AGPL-3.0; wrapper Rust; publicado 26-10-2026) |
| `omemo_dart` | Codeberg/GitHub (MIT; su propio README dice *"not been audited, works with itself"*) |
| `double_ratchet` 0.2.1 | pub.dev (2 días de vida al momento del chequeo, sin adopción) |
| Minilibs (`chat_secure_guard`, `azproto`, `pq_aura`, etc.) | pub.dev, orden de decenas de descargas |
| libsignal oficial (Rust/Java/Swift/JS) | signal.org / GitHub Signal (AGPL) |
| **Propia según specs públicas** | Double Ratchet + X3DH por las especificaciones públicas de Signal sobre `cryptography` 2.9.0 |

Veredicto documentado con esa misma evidencia: **no existe paquete Dart mantenido + licencia compatible + modelo de primitivas D1/D2**. Cumpliendo la instrucción de no seleccionar por la tabla: la comparativa es el insumo; la selección exige además el encaje funcional (§2.3) y la disponibilidad de KATs; la decisión es del CTO (**DEC-G1**). No se cambió ninguna primitiva, parámetro ni código.

### 2.3 Requisitos funcionales y de seguridad del protocolo elegido (spec `PHASE_G` §4–§5)

- X3DH-análogo: `dh1..dh4` (tres DH con material efímero + uno ligado a las identidades estáticas) → salt canónico derivado de ambas identidades (orden por `account_id`, menor primero) → HKDF master con `info` que incluye el hash del transcript → root chain + cadenas separadas `A2B`/`B2A` + header key (§4.1–§4.3).
- Verificación previa **antes** de derivar (§4.4); primer contacto marcado `firstContact` con anclaje OOB obligatorio (§4.5).
- Double Ratchet con message key de un solo uso (§5.2); cabecera {version, session_id, dh, n, pn} y **AAD = header ‖ match_id ‖ sender_id ‖ message_id** (§5.3).
- Skipped keys acotadas: **2000 / 7 días / 10 min** propuestos, **pendientes de firma CTO** (§5.4 + matrices E2EE §4). → DEC-G2.
- Estado del ratchet solo en SecureStorage (§5.5); un solo ciphertext para cloud y mesh (§5.6); fan-out por device (§5.7, fase posterior).

> **⚠️ Hallazgo nuevo (2026-10-27) — DEC-G4:** divergencia de key schedule entre lo **IMPLEMENTADO** y lo **ESPECIFICADO**. `PHASE_E` §7.3 (implementado) deriva una única clave de sesión con `info="zone-xtdhs-v1"` + hash(hello_B), mientras `PHASE_G` §4.3 (especificado) define root + cadenas `A2B`/`B2A` + header key con `info="ZONE-AKE-1 …"`. No bloquea el AKE actual, pero **v3 exige reconciliar ambos schedules** (ver fila DEC-G4 en §5).

### 2.4 Riesgos de un ratchet propio (aun basado en specs públicas)

Código criptográfico de *composición* propio = riesgo alto: errores de máquina de estados (reuso de message key, ventana de skip mal acotada, orden de verificación) invalidan el forward secrecy en la práctica. La API de `cryptography` no ofrece zeroización garantizada (`destroy()` libera la referencia, no el buffer). Sin interop con pares externos, "works with itself" es un riesgo propio (mitigable solo contra la spec de Signal + tests). Mantenibilidad del equipo. Por eso el plan obliga: KATs RFC 5869/8439/7748/8032 por versión (§7.1), matriz de propiedades §7.2–§7.6 en verde, y **revisión externa** antes de afirmar FS/PCS en ningún documento — regla idéntica del gate (§3.1.1.2 y prohibiciones del doc E2EE).

### 2.5 Migración v1→v4 (sin ejecutar)

Orden de `PHASE_G` §6.6 (paso 1 hecho — comentario FS corregido): **v2** (HKDF + AAD + `crypto_version`, claves estáticas, KAT/AAD) → **v3** (AKE + transcript; debe reconciliar DEC-G4) → **v4** (ratchet) → unificación cloud/mesh → multi-device. Condiciones: añadir `crypto_version`/`session_id`/`header` **nullable** a `messages` sin tocar filas v1 (§6.4); historial v1 descifrado con la clave estática archivada **sin subirla al servidor** (§6.2 + I-025); sin downgrade silencioso — la versión se firma en el transcript y viaja en el AAD (§6.3); rollback solo por feature flag, sin "bajada" de formato (§6.5).

---

## 3. P2P y certificados de dispositivo

### 3.1 Flujo de autenticación paso a paso (contrato `ZONE-P2P-AKE-1` + §7.2)

1. **Descubrimiento**: el `endpointId` solo sirve de direccionamiento; no es identidad (§7.4).
2. **hello_A** (iniciador): los 16 campos de §4.2 — versión fija `ZONE-P2P-AKE-1`, `zone_id` canónico, `account_id`/`device_id` UUID canónicos, pk Ed25519, pk X25519 + versión, efímera X25519, nonce 32 B, `session_id` v4, `issued_at_ms`, firma Ed25519 de 64 B sobre el transcript canónico de longitud prefijada (§4.3).
3. **B verifica en orden deliberado** (§4.4, 12 pasos): campos → versión → canonicalidad → algoritmos → longitudes → estado del device (de fuente local de confianza, no del cable) → TTL 2 min / skew 30 s → `session_id` no visto → ancla → `expectedZoneId` → firma → caché **solo si acepta**.
4. **hello_B** del respondedor, **con `prior = SHA-256(hello_A)`**: los dos lados exigen roles opuestos (`transcriptBindingRequired` / `unexpectedPriorTranscript`).
5. **complete()** en ambos: exige hello local + hello remoto + decisión aceptada + prior correcto + `endpointId` ligado → **solo ahí** se deriva clave (DH1–DH4 → HKDF → clave de sesión; el test de regresión Z-004 comprueba `session ≠ dh4`).
6. **Comunicación** derivada de ese estado con las cadenas/AAD de Fase G (no implementado aún).
7. **Destrucción** de la sesión al desconectar; el ancla solo persiste tras OOB confirmada.

### 3.2 Vinculación identidad ↔ device ↔ certificado

`P2PTrustAnchor` = {identity_public_key, encryption_public_key, encryption_key_version} con reglas de sustitución (§4.6). En v1, `account_id`/`device_id` del `hello` son **declarativos**; `deviceStatus`/`revokedAt` llegan de un registro local confiable.

**Gap documental (hallazgo de esta revisión):** `device_certificate` v2 **no tiene documento propio** — solo existe como definición de hueco en `PHASE_E` §7.8.1(b), el gap de §7.9 y la fila de riesgos "account_id declarativo". Se registra como **DEC-E2**. Su emisión depende de: decisión F (§10.3) → fundación server-side → `register_device` firmado por la Ed25519 de cuenta → tabla de revocaciones (ambigüedad #5) → recién entonces el certificado firma el `hello` o el registro alternativo.

### 3.3 MITM / replay / downgrade / sustitución — qué está probado y qué no

| Ataque | Estado | Fuente |
|---|---|---|
| Sustitución de clave contra **ancla existente** | **PROBADO LOCALMENTE** (24 negativos + 18 integración) | `p2p_auth_negative_test` / `p2p_handshake_integration_test` |
| Replay de hello (TTL + cache anti-replay LRU 512 / 10 min) | **PROBADO LOCALMENTE** | idem |
| Downgrade de versión (sin negociación, versión fija) | **PROBADO LOCALMENTE** | idem |
| **MITM en primer contacto** | **NO defendido** hasta ancla/OOB o cert v2 — *"no se demuestra que el primer contacto sea seguro"* (§7.9) | `PHASE_E` §7.9 |
| MITM en radio con integración activa | **VALIDADO EN ENTORNO REAL: 0/15** (demo §7.8.1(j), hardware 1/2) | `PHASE_H` |
| Sustitución en **camino cloud** (perfiles de Supabase) | NO defendido todavía (T1) | `PHASE_G` §2.3 |
| Cableado en producción | **NOT IMPLEMENTADO**: `nearby_service.dart:907` sigue aceptando directos; `:1044` envía `profile_exchange` sin firma | verificado 27-10-2026 |

Regla respetada: **no se declara protección MITM en producción**; lo único demostrado es la solidez del contrato con ancla en local.

### 3.4 Expiración, revocación, rotación y device perdido

TTL del hello 2 min (skew 30 s) · caché anti-replay 10 min / 512 entradas · `endpointId` internado en el handshake (`assertEndpoint` por payload; sesión destruida al desconectar) · revocación solo desde fuente local confiable (rechazo tipado) · **rotación legítima imposible hoy** (depende del registro firmado; consecuencia operativa aceptable para beta con 1 device/cuenta; re-anclaje solo por OOB) · device perdido: el estado del ratchet se pierde con el device, las sesiones se re-negocian y los mensajes previos **no** se recuperan (I-025).

### 3.5 WI-1…WI-7 ↔ pruebas reproducibles (matriz §7.8.2)

- **PROBADO LOCALMENTE:** WI-1 (handshake completo), WI-4 (`endpointMismatch`), WI-5 (sin downgrade), WI-7 (`keyVersionRollback` / `keyRotationRequired`).
- **Sin cablear en producción:** WI-1 y WI-4 (el contrato pasa sus tests pero nadie lo invoca en `nearby_service.dart`).
- **NOT IMPLEMENTADO:** WI-2 (gate del despachador), WI-3 (en producción), **WI-6 rate-limit** (nadie lo ha añadido). Chequeo horizontal del registro de logs: PARCIAL (sin aserción explícita de no-filtración en el handshake).

### 3.6 Dependencias entre registro del certificado e integración del handshake

El cableado de §7.8.1(a) **puede** implementarse con ancla OOB local; el **cierre de Z-004** exige: (a) DEC-F1 + DEC-F2…F6, (b) `device_certificate` v2 (que depende de lo anterior), (c) demo física H-10 + los requisitos (1)(2)(3) de §7.8.1(j). **P0-3 precede al cierre de P0-2** (verificado y documentado en el gate).

---

## 4. Staging y release

### 4.1 Datos y confirmaciones exactos antes de autorizar staging (`Z212` §0.1 — **ningún campo recibido al 2026-10-27**)

1. Identidad del proyecto de staging: `project_ref` (el host **no** se imprime; se compara el ref esperado).
2. Ventana de aplicación con zona horaria.
3. Alcance exacto ☑ preflight + backup + aplicación + postflight + matriz P/N + idempotencia (y todo lo que queda **NO** autorizado).
4. Respaldo creado **y restauración probada en base desechable** (no visualmente en producción).
5. Cliente de staging habilitado en RPC (`resolve_bt_token`, receipts) + `allowSameAccountClaim=false` si aplica.
6. Rol de migración (`postgres` / owner).
7. Responsable de negocio y responder técnico.
8. Firma/registro: fecha + referencia de la autorización.

Precondiciones operativas completas en §3.2 del runbook (tablas/columnas, backups tar, roles).

### 4.2 Respaldo recuperable y plan de rollback (§4, §5.2, §10)

- **Preferido:** branch/point-in-time snapshot con **restauración probada en instancia desechable** (jamás sobre producción). `pg_dump --schema=public --format=custom` + prueba efectiva de `pg_restore --clean --if-exists` en desechable; cifrado en reposo; retención hasta el sign-off.
- **Aplicación:** `psql -v ON_ERROR_STOP=1` con `PGOPTIONS="-c lock_timeout=5s -c statement_timeout=120s"`; el SQL del runbook trae `BEGIN`/`COMMIT` — un fallo revierte todo y se verifica que no quedaron objetos parciales; se ejecuta **dos veces** para demostrar idempotencia (exit 0 ×2).
- **Rollback:** la transacción se auto-revierte; si ya se aplicó y rompe la app, la vía segura es **restaurar el snapshot o un forward-fix revisado**. **No existe "reverse SQL" seguro**: recrear las policies antiguas (resolver token BT, UPDATE de mensajes, `UPDATE users SET id`) reintroduce los defectos P0/P1 de Z-212. Documentar la ventana de escrituras perdidas si hay restore.
- **Aceptación (§9, 14 casillas):** preflight limpio, backup probado, exit 0 ×2, post-estado = §5.3, **matriz P-01…P-10 / N-01…N-18 en PASS con JWT reales** (staging), `anon` rechazado, sin policies amplias residuales, radar/chat/receipts OK, evidencia saneada de device_lab, y **CTO sign-off a producción fuera de este runbook**.

### 4.3 Comprobaciones para firmar AAB/APK de producción con clave real (`RELEASE_SIGNING.md`)

1. **Crear keystore** con `keytool -genkeypair` (RSA-4096, 10000 días), **fuera del repositorio**, contraseñas por prompt interactivo (nunca en CLI ni en historial), backup cifrado; recomendación explícita: **Play App Signing** primero (upload key para recuperabilidad).
2. **Credenciales:** `android/key.properties` (git-ignored, permisos restrictivos, rutas con `/` incluso en Windows) **o** variables de entorno `ZONE_KEYSTORE_PATH/PASSWORD/ALIAS/KEY_PASSWORD` (en CI desde gestor de secretos; jamás impresas en logs).
3. **Compilar + verificar:** `flutter build appbundle --release --dart-define-from-file=.env` → `apksigner verify --print-certs` con certificado **≠ `CN=Android Debug`** y SHA-256 = keystore de release; check rápido `./gradlew :app:validateSigningRelease`.
4. **Fail-closed ya verificado (2026-10-27):** sin configuración, el build muere antes de producir artefacto con el mensaje *"Refusing to build a release with debug keys"* (exit 1, dos verificaciones). Prueba de cableado permitida con keystore temporal de vida corta (§6 del doc) sin tocar el repo.
5. **Claves fuera del repo:** `.gitignore` raíz (líneas 44-47) y `android/.gitignore` (líneas 12-14) excluyen `key.properties`, `*.jks`, `*.keystore` (re-verificado hoy: 0 keystores en el árbol); no publicar claves en issues/artifacts; rotación si la upload key se compromete. El `.env` local (git-ignored) nunca entra en el repo.

### 4.4 Pruebas de dos dispositivos necesarias (matriz H-01…H-15 — **0/15 NOT RUN**)

- **H-01…H-05, H-07, H-08, H-11…H-15** requieren 2 dispositivos físicos.
- **H-06** (mesh a 2+ saltos) requiere **3 dispositivos**.
- **H-09** (reinstalación / login de usuario existente) depende de la decisión de Fase F.
- **H-10** (suplantación de ZONE-ID) = **KNOWN FAIL esperado** hasta cerrar Z-004; se ejecuta contra ancla OOB.
- Estado físico al 2026-10-27: TB305FU (serial HA26RCFN, Android 15) con APK debug v1.0.4 instalada y verificada (`lastUpdateTime 2026-10-27 19:36`, actualización preservó datos locales; buffer de crash sin registros de `com.dybrocorp.zone`); 2º dispositivo: instalación manual en curso por el propietario (APK v1.0.4 entregada).

---

## Hallazgos nuevos registrados por esta revisión

| ID | Hallazgo | Evidencia | Decisión afectada |
|---|---|---|---|
| **H-J1** | Divergencia de key schedule: lo implementado (`PHASE_E` §7.3, `info="zone-xtdhs-v1"`, clave de sesión única) ≠ lo especificado (`PHASE_G` §4.3, root/cadenas/header) | Código y docs comparados el 2026-10-27 | **DEC-G4** |
| **H-J2** | `device_certificate` v2 **sin documento de spec propio** (solo definiciones de hueco en `PHASE_E`) | Búsqueda en `docs/` el 2026-10-27 | **DEC-E2** |

---

## 5. Tabla de decisiones DEC-F1…DEC-H1

> Las **Recomendaciones no implican aprobación**: la decisión la toma y firma el propietario/CTO. Los criterios PASS son condiciones **verificables**, no intenciones.

| ID | Evidencia documental | Opciones disponibles | Riesgos | Recomendación (sin aprobar) | Decisión que debe tomar el propietario | Criterios verificables para declarar PASS |
|---|---|---|---|---|---|---|
| **DEC-F1** — variante de login A | `PHASE_F` §10.1–§10.3; esquema real verificado (9 FK `ON UPDATE CASCADE` / 21 policies / 45 refs `auth.uid()`) | A2 como objetivo / A1 como shim condicionado / mantener cuarentena | A1 convierte `users.id` en binding mutable; A2 = migración grande M1–M5 con staging obligatorio | A2 objetivo; A1 solo shim corto con fecha de salida y 5 condiciones | **Aprobar la variante** | Variante firmada en este doc o en `PHASE_F`; R-01…R-14 en verde con dos dispositivos; pre-requisito común R-13 resuelto y decidido primero |
| **DEC-F2…F6** — 5 ambigüedades | §3.2.5 + resoluciones propuestas §10.4 | 2–3 alternativas por ambigüedad (tabla §10.4) | Definen el modelo de seguridad: linkabilidad, autoría, TOFU, backfill, revocación | Aprobar los defaults fail-safe propuestos en §10.4 | **Firmar las 5** (o alternativas justificadas) | Cada ambigüedad con firma o alternativa registrada y reflejada en `PHASE_F` §10.4 |
| **DEC-F7** — ventana legacy | §3.5 + `PHASE_2_LEGACY_ACCESS_POLICY` (REGL-1/REGL-2) | Claim acotado a legacy / emisión obligatoria de recovery en M1 | Reabrir el claim inseguro para cuentas seguras (REGL-2) | Ventana acotada (`mode=legacy`, sin devices, rate-limit, auditoría) retirada en M5 | **Aprobar la transición** | R-08/R-09 en PASS |
| **DEC-G1** — ruta E2EE | `E2EE_RATCHET_ALTERNATIVES` §2–§3 (fuentes verificadas 27-10-2026) + `PHASE_G` §7 | Propia según specs públicas / libsignal GPL-AGPL con cambio de modelo / descartar FS | Composición propia sin revisión externa; licencias GPL/AGPL incompatibles con el modelo | Ruta propia: Double Ratchet de primera parte sobre `cryptography` 2.9.0, con obligaciones (KATs RFC + matriz §7 + revisión externa) | **Aprobar ruta + presupuesto de revisión externa** | KATs §7.1 en verde + matriz de propiedades §7.2–§7.6 en verde + informe de revisión externa recibido y tramitado |
| **DEC-G2** — parámetros del ratchet | `E2EE_RATCHET_ALTERNATIVES` §4 + `PHASE_G` §5.4 | 2000 skipped / 7 días / 10 min, u otros justificados | Ventana arqueológica vs UX offline | Aprobar 2000 / 7 días / 10 min | **Firmar los valores** | Valores fijados en un doc firmado y calculados en cliente con límites duros |
| **DEC-G3** — fase v2 | `PHASE_G` §6.6 (paso 1 hecho: comentario FS corregido) | Autorizar v2 ahora / esperar v3 | v2 solo cierra HKDF/AAD, no el MITM cloud; pero es paso ordenado y acotado | Autorizar v2 tras decidir DEC-F y DEC-G1/G2/G4 | **Autorizar la fase v2** | v2 IMPLEMENTADA + KAT HKDF/AAD en verde + columnas `messages` añadidas nullable sin tocar filas v1 |
| **DEC-G4** — schedule normativo (H-J1) | `PHASE_E` §7.3 (implementado) vs `PHASE_G` §4.3 (especificado) — divergencia detectada el 2026-10-27 | Unificar al schedule de `PHASE_G` en v3 / documentar el de E como intermedio deprecable | Dos schedules normativos = auditoría imposible y riesgo de mezcla de dominio KDF | Unificar al formato de `PHASE_G` en v3 (root/cadenas/header único normativo) | **Decidir qué schedule es normativo** | Un solo schedule normativo en el spec + KAT derivado del schedule final |
| **DEC-E1** — cableado P2P | `PHASE_E` §7.8.1(a)–(i); hoy 0 referencias al contrato desde `nearby_service.dart` ([:907] acepta directos; [:1044] sin firma) | Cablear ya con ancla OOB + WI-6 / esperar cert v2 | Cablear sin WI-6 abre superficie de abuso de hello; esperar retrasa el cierre de Z-004 | Cablear tras DEC-F + DEC-E2, **con WI-6 incluida** | **Aprobar el cableado** | WI-2…WI-6 IMPLEMENTADAS y probadas; H-01/H-02/H-05 validadas entre dos físicos |
| **DEC-E2** — `device_certificate` v2 (H-J2) | Huecos de §7.9 + fila "account_id declarativo"; **sin spec propio** | Cert firmado por cuenta / salida con ancla OOB pura | MITM en primer contacto sin cert/OOB | Redactar el spec mínimo del cert v2 tras DEC-F1…F6 + UI OOB obligatoria | **Registrar el diseño mínimo** (exige spec escrito) | Spec del cert escrito en `docs/audit`; emisión IMPLEMENTADA; cierre demostrado por H-10 |
| **DEC-S1** — autorización staging | `Z212` §0 — formulario vacío al 2026-10-27 | Autorizar ventana / no autorizar | Migraciones remotas sin backup probado | No autorizar hasta completar los 8 campos con restauración probada en desechables | **Firmar el §0** | Matriz P-01…P-10 / N-01…N-18 en PASS con JWT reales; postflight = §5.3; idempotencia exit 0 ×2 |
| **DEC-R1** — keystore de release | `RELEASE_SIGNING.md` estado BLOCKED (27-10-2026); fail-closed verificado hoy (exit 1) | Crear keystore + Play App Signing / mantener signing temporal | Pérdida de la identidad de la app si se publica con debug | Crear keystore fuera del repo + Play App Signing primero, backup cifrado | **Autorizar creación y custodia** (contraseñas nunca por chat) | `apksigner verify --print-certs` con certificado ≠ `CN=Android Debug` y SHA-256 = keystore release |
| **DEC-H1** — hardware | `PHASE_H` 0/15 NOT RUN; hardware 1/2 (TB305FU listo) | Disponer 2º y 3º device / declarar el subconjunto ejecutable | H-06 exige 3 dispositivos; H-09 depende de DEC-F | Disponer 2º device (APK v1.0.4 ya entregada) y 3º para H-06 | **Disponer hardware + calendario** | H-01…H-05, H-07, H-08, H-11…H-15 en PASS; H-06 con 3º device; H-10 pasa tras el cierre de Z-004 |

---

## 6. Bloqueos P0/P1 y orden de ejecución

| Bloqueo | Estado al 2026-10-27 |
|---|---|
| **P0-1** — Z-212 staging/prod | **BLOCKED** — DEC-S1 sin firmar; §0 vacío; SQL local en PASS (guardas 4/4) |
| **P0-2** — cierre Z-004 (P2P) | **BLOCKED** — contrato PROBADO LOCALMENTE (24+18); cableado NOT IMPLEMENTADO; cert v2 sin spec (DEC-E2) |
| **P0-3** — login de usuario existente | **BLOCKED** — paquete listo; 5 ambigüedades sin firmar (DEC-F2…F6); R-01…R-14: 0/14 |
| **P0-4** — firma de release | **BLOCKED** — sin keystore; fail-closed VERIFICADO hoy; DEC-R1 pendiente |
| **P0-5** — suite + calidad | **VERIFICADO LOCALMENTE** — 289/289 + `flutter analyze` limpio (no habilita go por sí solo) |
| **P0-6** — dos dispositivos | **NOT RUN** — hardware 1/2 (TB305FU con APK v1.0.4; 2º device en instalación manual) |
| **P0-7** — E2EE forward secrecy | **BLOCKED** — DEC-G1/G2/G4 sin firmar, DEC-G3 sin autorizar; paso 1 de §6.6 completado (comentario FS corregido) |

**Orden de ejecución recomendado (dependencias reales, sin tocar código):**

1. **① Firmar DEC-F1 + DEC-F2…F6 + DEC-F7** — vía crítica del login (resolver R-13 primero).
2. **② Firmar DEC-G1 + DEC-G2 + DEC-G4 y autorizar DEC-G3 (v2)**.
3. **③ DEC-E2** — spec escrito del `device_certificate` v2.
4. **④ DEC-S1** — completar §0 con backup probado → ejecutar Z-212 + matriz P/N en staging.
5. **⑤ DEC-R1 (keystore) y DEC-H1 (2º/3º device)**.
6. **⑥ DEC-E1** — cablear WI-2…WI-6 en producción.
7. **⑦ Validación en entorno real** — H-01…H-15 (H-10 contra ancla OOB), R-01…R-14 con dos dispositivos; recién entonces reevaluar el gate.

---

## Cierre

El estado de beta permanece **❌ NO-GO**: ningún bloqueo crítico (P0-1…P0-4, P0-6, P0-7) tiene decisión firmada ni validación en entorno real; P0-5 es calidad local y no habilita go por sí solo. La reevaluación del gate solo procede tras completar el orden de ejecución del §6 y sostener cada PASS con los criterios verificables del §5. Se mantiene NO-GO mientras exista algún bloqueo crítico sin resolución.
