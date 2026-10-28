# Gate de beta · ZONE

**Proyecto:** ZONE (Flutter)
**Repositorio:** `D:\Proyectos\Zone`
**Commit base:** `7f59b776c62cc131fd05dc999e99cbb7804385e8`
**Fecha:** 2026-10-23
**Auditor:** agente AI (DeepSeek V4.1 Flash Free). No sustituye la firma de un CTO humano.

---

## 1. Decisión

# ❌ NO-GO · BLOCKED

**ZONE no está listo para una beta con usuarios reales.**

La decisión no se basa en impresiones: se basa en que **la base de producción sigue sin el hardening Z-212 aplicado y verificado**, la identidad P2P sigue siendo TOFU en producción (solo existe el contrato de verificación, no integrado), el login de usuarios existentes sigue bloqueado a la espera de una decisión de producto, el release real aún no tiene keystore de upload y no hay validación en dos dispositivos físicos. El defecto de Isar en Windows y la firma debug ya no bloquean localmente, pero no sustituyen esas evidencias.

Lo que **sí** está verificado localmente (2026-10-23):

- `flutter analyze --no-pub`: `No issues found!`.
- Suite completa: **271/271 tests PASS**; identidad **126/126 PASS** (los 21 tests antes bloqueados por `isar.dll` ahora ejecutan cargando el core nativo de `isar_flutter_libs`).
- La migración Z-212 pasa seis grupos de pruebas conductuales en PostgreSQL 18.4 real; quedan pendientes RLS/JWT y staging.
- Los controles cliente de payload, mesh, visibilidad, idempotencia y manifest están implementados.
- Firma release: configuración explícita sin fallback a debug, fail-fast verificado sin config y validación con keystore temporal; el keystore real sigue pendiente.
- Diseño y contrato ejecutable de autenticación P2P (`ZONE-P2P-AKE-1`, 24 tests negativos) y especificación E2EE (HKDF/AAD/ratchet); **no integrados**.
- No se aplicó nada en remoto, no se commiteó y no se desplegó.

---

## 2. Criterios del gate

| # | Criterio | Requerido para beta | Estado | Evidencia |
|---|---|---|---|---|
| G-01 | Análisis estático limpio | Sí | **VERIFIED** | `flutter analyze --no-pub` → `No issues found!` |
| G-02 | Suite de tests verde | Sí | **VERIFIED (local)** | `flutter test --no-pub` → **271/271 PASS** |
| G-03 | Tests de identidad ejecutables | Sí | **VERIFIED (local)** | `flutter test --no-pub test/identity` → **126/126 PASS**; core Isar de `isar_flutter_libs` |
| G-04 | Hardening SQL implementado | Sí | **VERIFIED (local)** | `z212_security_hardening.sql` + arnés SQL |
| G-05 | Hardening SQL aplicado en staging | Sí | **NOT VERIFIED** | runbook listo; sin autorización ni conexión |
| G-06 | Hardening SQL aplicado en producción | Sí | **NOT VERIFIED** | sin autorización |
| G-07 | RLS real verificado con JWT | Sí | **NOT VERIFIED** | stubs locales sin RLS/JWT |
| G-08 | Account takeover cerrado | Sí | **BLOCKED (remoto)** — local verificado | cuarentena `claim_zone_id` + tests SQL |
| G-09 | Identidad P2P autenticada (Z-004) | Sí | **BLOCKED** | contrato `P2PAuthPolicy` + 24 tests; **no cableado** |
| G-10 | Login de usuario existente funcional | Sí | **BLOCKED** | decisión Fase F pendiente (A/B) |
| G-11 | E2EE con forward secrecy | Sí para afirmar FS | **BLOCKED** | diseño Fase G; sin HKDF/AAD/ratchet |
| G-12 | Release firmado con keystore real | Sí | **PARTIAL** | fail-fast y keystore temporal OK; falta keystore real y AAB verificado |
| G-13 | Validación en dos dispositivos físicos | Sí | **NOT VERIFIED** | 0 dispositivos Android; H-01…H-15 **NOT RUN** |
| G-14 | Backup/restore y rollback ensayados | Sí | **NOT VERIFIED** | no ejecutado |
| G-15 | Escaneo de secretos en CI | Sí | **NOT VERIFIED** | barrido local sin hallazgos; no hay pipeline CI |
| G-16 | Documentación alineada con la realidad | Sí | **PARTIAL** | `BUG_REGISTER` corregido y docs de fase añadidos; quedan docs heredados por revisar |

**Resultado:** 4 criterios verificados localmente, 2 parciales, 4 bloqueados y 6 no verificados. **No se alcanza el umbral de beta.**

---

## 3. Bloqueadores P0

### P0-1 · Aplicar y verificar Z-212 en staging y producción

**Por qué bloquea:** el código de `HEAD` permitía account takeover, tampering de mensajes, reescritura de matches y evasión de shadowban. Tener la migración en el repo no protege a los usuarios; solo aplicarla y verificarla lo hace.

**Estado (2026-10-23):** runbook listo en `docs/audit/Z212_STAGING_RUNBOOK.md`. **No se conectó ni modificó staging/producción.** Requiere autorización explícita y un backup verificado.

**Criterio de salida:**

- [ ] Snapshot/backup verificado.
- [ ] Migración aplicada en staging en transacción.
- [ ] Verificación con JWT/RLS reales (no stubs).
- [ ] Regresión funcional de radar, match, chat, receipts, offline y encuentros.
- [ ] Migración aplicada en producción en ventana autorizada.
- [ ] Post-deploy sin errores 42501/400 anómalos.

**Responsable:** CTO/operador con acceso a Supabase. **Requiere autorización explícita.**

---

### P0-2 · Cerrar el spoofing/MITM P2P (Z-004)

**Por qué bloquea:** `profile_exchange` vincula un `zone_id` declarado a una clave X25519 aportada por el par. El primer contacto es TOFU: un atacante puede presentarse como otro ZONE-ID y establecer una clave de sesión propia. No hay prueba de posesión de la identidad.

**Estado (2026-10-23):** diseño, modelo de amenazas y contrato de verificación completados (`docs/audit/PHASE_E_P2P_AUTH_DESIGN.md`, `lib/services/p2p_auth_policy.dart`, **24/24 tests**). El contrato **no está integrado** en `NearbyService`; la producción sigue aceptando `profile_exchange` sin firma. El P0 sigue abierto.

**Criterio de salida:**

- [ ] Binding verificable `zone_id ↔ account_id ↔ device_id ↔ clave` (el contrato lo exige; falta integración).
- [ ] Challenge/response firmado (Ed25519) en el primer contacto (especificado y probado en el contrato; falta cableado).
- [ ] Rotación y recuperación de dispositivo definidas (diseño parcial en Fases E/F/G; falta registro firmado).
- [ ] Test de suplantación en dos dispositivos: el atacante no puede establecer sesión como la víctima.
- [x] Documentación de que el ZONE-ID/token **no** son identidad criptográfica (`PHASE_E`, `BUG_REGISTER`).

**Nota:** no se debe “arreglar” con un checksum o un campo `verified: true`; eso sería seguridad teatral.

---

### P0-3 · Resolver el login de usuario existente (decisión de producto)

**Por qué bloquea:** `SameAccountClaimPolicy.allowSameAccountClaim = false` y `claim_zone_id` falla cerrado. Un usuario que cambia de dispositivo **no puede recuperar su cuenta**. Es más seguro que el takeover, pero es un bloqueo funcional de beta.

**Estado (2026-10-23):** análisis y recomendación en `docs/audit/PHASE_F_EXISTING_USER_LOGIN.md`. Se documentaron la Alternativa A (recuperación con prueba de posesión) y la B (nueva identidad por dispositivo), con modelos de amenaza, coste de esquema y conflicto con REGL-1. **No se implementó ninguna** y la cuarentena sigue activa. También se documentó un bug de orden en `_loginWithExistingIDInternal` (escrituras locales antes de validar/RPC) que debe corregirse en cualquier alternativa.

**Criterio de salida (una de dos):**

- [ ] Implementar el puente cuenta/dispositivo con prueba de posesión + `register_device` firmado (Alternativa A; falta elegir variante A1/A2/A3); o
- [ ] Declarar formalmente “new device = new account”, retirar/ocultar el login roto y comunicarlo en UX/legales (Alternativa B; requiere excepción explícita a REGL-1).

**Responsable:** producto + CTO. No es una decisión que deba tomar la implementación por sí sola. Preguntas concretas en `PHASE_F` §7.

---

### P0-4 · Firmar el release con un keystore real

**Por qué bloquea:** el release debe firmarse con una clave de upload custodiada. `HEAD` usaba la clave debug; ya se sustituyó por una configuración explícita que falla cerrada, pero **todavía no existe el keystore real** ni un artefacto release verificado.

**Estado (2026-10-23):** `android/app/build.gradle.kts` ya no usa `debug` para release. Exige `android/key.properties` (git-ignored) o las variables `ZONE_KEYSTORE_PATH`, `ZONE_KEYSTORE_PASSWORD`, `ZONE_KEY_ALIAS`, `ZONE_KEY_PASSWORD`. Sin configuración, `:app:assembleRelease` falla con: `Release signing is not configured. Refusing to build a release with debug keys.` La configuración se validó con un keystore temporal fuera del repo (`validateSigningRelease` exit 0) y se eliminó. Documentación completa: `docs/RELEASE_SIGNING.md`.

**Criterio de salida:**

- [ ] Keystore de release creado y custodiado (no existe aún).
- [x] `signingConfig` de release configurado sin secretos en el repo.
- [ ] `flutter build appbundle --release` verificado con el keystore real.
- [ ] `apksigner verify` / Play Console acepta el artefacto.
- [x] Procedimiento de configuración y rotación/recuperación documentado (`docs/RELEASE_SIGNING.md` §2–§7).

---

### P0-5 · Suite de tests verde o exclusiones aprobadas

**Por qué bloqueaba:** 21 tests de identidad no se ejecutaban en Windows por `isar.dll` error 126.

**Estado (2026-10-23): resuelto localmente.** `test/flutter_test_config.dart` carga el core nativo que ya distribuye `isar_flutter_libs` (resuelto vía `.dart_tool/package_config.json`), sin descargar binarios ni copiar DLLs al repo. Resultado: identidad **126/126 PASS**, suite completa **271/271 PASS**, sin `skip` nuevos ni tests borrados. Documentación: `docs/audit/PHASE_D_ISAR_WINDOWS.md`.

**Criterio de salida:**

- [x] Core Isar correcto en Windows (desde el paquete oficial, no desde el repo).
- [x] 271/271 tests verdes en este host.
- [ ] CI en Linux/macOS con Isar nativo (las rutas están implementadas, no ejecutadas en CI).
- [x] Sin `skip` silenciosos ni tests borrados.

---

### P0-6 · Validación E2E en dos dispositivos físicos

**Por qué bloquea:** BLE/Nearby, mesh multi-salto, receipts, outbox offline y reinstalación no se pueden validar con stubs.

**Estado (2026-10-23): NOT VERIFIED.** `adb devices` no detecta dispositivos, `flutter devices` solo muestra Windows/Edge y no hay emuladores. Se preparó la matriz de 15 casos en `docs/audit/PHASE_H_TWO_DEVICE_MATRIX.md`; los 15 quedan **NOT RUN** (H-10 marcado **KNOWN FAIL** por Z-004). Se ejecutó el subconjunto automatizable: **89/89 PASS**. No se simula evidencia física.

**Matriz mínima:**

- [ ] Descubrimiento BLE/Nearby en dos Android.
- [ ] Intercambio de perfil y derivación de clave.
- [ ] Match request/accept.
- [ ] Chat online y offline.
- [ ] Receipts enviado → entregado → leído.
- [ ] Mesh a 2+ saltos con un tercer dispositivo.
- [ ] Reinicio de app con outbox pendiente.
- [ ] Reinstalación y recuperación (o mensaje de producto claro).
- [ ] Intento de suplantación de ZONE-ID (debe fallar; hoy **KNOWN FAIL**).

---

### P0-7 · E2EE: implementar forward secrecy o retirar la afirmación

**Por qué bloquea:** el esquema X25519 estático-estático no tiene forward secrecy, HKDF, AAD ni ratchet. Si la beta se comunica como “E2EE con forward secrecy”, la afirmación es falsa.

**Estado (2026-10-23):** auditoría y especificación completadas (`docs/audit/PHASE_G_E2EE_KEY_ESTABLISHMENT.md`). Se confirmó que el secreto X25519 crudo se usa como clave AEAD, sin HKDF, AAD ni ratchet, que cloud y mesh cifran por caminos separados y que el comentario “garantizando Forward Secrecy” de `chat_e2ee_service.dart:59` es falso. No se implementó criptografía nueva ni se cambió el comportamiento. El P0 sigue abierto.

**Criterio de salida (una de dos):**

- [ ] Implementar ratchet/HKDF/AAD y demostrar FS con tests (diseño v1→v4 en `PHASE_G`; requiere aprobación y migración); o
- [ ] Retirar “forward secrecy” de README, docs, store listing y UX hasta implementarlo (el comentario falso sigue en el código).

---

## 4. P1 — antes de beta pública

| # | Item | Criterio |
|---|---|---|
| P1-1 | RLS real con JWT | Tests de staging que ejerciten `CREATE POLICY`, no solo triggers |
| P1-2 | Token bearer | Documentar TTL/rotación; evaluar acortar ventana de replay |
| P1-3 | Documentación | Corregir `BUG_REGISTER` Z-001: “anon/rate-limit verificado” ≠ “posesión probada” |
| P1-4 | Rollback | Ensayar restore de snapshot; no hay down migration |
| P1-5 | Secretos en CI | gitleaks/trufflehog + revisión de historial |
| P1-6 | Dependencias | Plan para Z-302 (69 upgradable, 17 fuera de rango, 4 discontinuadas) |
| P1-7 | Cleartext dev | Verificar que `usesCleartextTraffic=false` no rompe staging local |
| P1-8 | Observabilidad | Alertas de errores RPC/RLS y tasa de fallos de sync |

---

## 5. Lo que se puede afirmar honestamente

Frases aptas para un informe interno o una conversación con inversores, **sin sobreafirmar**:

- “Se implementó y validó localmente un hardening de seguridad para cinco defectos SQL demostrables y varios defectos del pipeline cliente.”
- “La migración pasa pruebas conductuales en PostgreSQL 18.4 con un arnés reproducible.”
- “El análisis estático está limpio y la suite completa pasa **271/271** en este host Windows, incluidos los **126** tests de identidad.”
- “La firma release falla cerrada sin configuración y fue validada con un keystore temporal; el keystore real aún no existe.”
- “Existe un contrato ejecutable de autenticación P2P y una especificación E2EE, pero **no están integrados** en producción.”
- “La migración **no** está aplicada en producción; la verificación remota y la validación en dispositivos están pendientes.”
- “La beta permanece en NO-GO hasta cerrar los P0.”

Frases **prohibidas** hasta que exista evidencia:

- “ZONE es E2EE con forward secrecy.”
- “La identidad P2P está autenticada en producción.”
- “Z-001 está cerrado en producción.”
- “La suite está verde en CI.”
- “La beta está validada en dos dispositivos.”
- “Beta lista para usuarios.”

---

## 6. Checklist para cambiar a GO

- [ ] P0-1: Z-212 aplicado y verificado en staging y producción.
- [ ] P0-2: identidad P2P firmada, integrada y probada contra suplantación (diseño/contrato listos; falta integración).
- [ ] P0-3: decisión de producto implementada (A/B; decisión pendiente).
- [ ] P0-4: release firmado con keystore real y artefacto verificado (config fail-closed lista; falta keystore real).
- [ ] P0-5: 271/271 tests verdes en CI (local 271/271; falta CI Linux/macOS).
- [ ] P0-6: matriz E2E en dos dispositivos físicos completada (0/15 ejecutados).
- [ ] P0-7: FS implementado o afirmación retirada (diseño listo; sin implementación).
- [ ] P1-1: RLS real verificado con JWT.
- [ ] P1-4: backup/restore y rollback ensayados.
- [ ] P1-5: escaneo de secretos en CI.
- [ ] Revisión y firma de un CTO humano.

**Solo cuando todos los P0 estén cerrados y los P1 acordados estén resueltos se puede emitir un GO.**

---

## 7. Índice de evidencia

| Documento | Contenido |
|---|---|
| `docs/audit/PHASE_0_1_BASELINE_AUDIT.md` | Estado Git, toolchain, baseline de tests, hallazgos en `HEAD` |
| `docs/audit/PHASE_2_SECURITY_HARDENING_Z212.md` | Controles SQL/cliente, validación PostgreSQL, riesgos residuales, plan de rollout |
| `docs/audit/PHASE_A_RECONCILIATION.md` | Reconciliación de estado, migraciones históricas fail-closed, tests SQL |
| `docs/audit/PHASE_C_RELEASE_SIGNING.md` | Firma release explícita, fail-fast y validación con clave temporal |
| `docs/audit/PHASE_D_ISAR_WINDOWS.md` | Causa raíz del error 126 y carga del core Isar en tests |
| `docs/audit/PHASE_E_P2P_AUTH_DESIGN.md` | Auditoría P2P, `ZONE-P2P-AKE-1`, modelo de amenazas y 24 tests |
| `docs/audit/PHASE_F_EXISTING_USER_LOGIN.md` | Alternativas A/B, modelos de amenaza y decisión de producto pendiente |
| `docs/audit/PHASE_G_E2EE_KEY_ESTABLISHMENT.md` | Auditoría E2EE, HKDF/AAD/ratchet y migración v1→v4 |
| `docs/audit/PHASE_H_TWO_DEVICE_MATRIX.md` | Matriz H-01…H-15 y evidencia de ausencia de hardware |
| `docs/audit/Z212_STAGING_RUNBOOK.md` | Procedimiento de staging, preflight/postflight y autorización |
| `supabase_migrations/z212_security_hardening.sql` | Migración de hardening |
| `supabase_migrations/tests/z212_behavioral_test.sql` | Arnés SQL reproducible |
| `lib/services/p2p_auth_policy.dart` | Contrato de verificación P2P (no cableado) |
| `test/p2p_auth_negative_test.dart` | 24 tests negativos/positivos de autenticación P2P |
| `test/sql_security_regression_test.dart` | Guardas estáticas de SQL (claim, policies, `users.id`) |
| `test/android_release_signing_test.dart` | Guardas estáticas de firma release |
| `test/flutter_test_config.dart` | Carga del core Isar desde `isar_flutter_libs` |
| `test/mesh_policy_test.dart` | Tests de validación mesh |
| `android/app/build.gradle.kts` | Configuración de firma release fail-closed (sin fallback debug) |
| `android/key.properties.example` | Plantilla sin secretos |
| `docs/RELEASE_SIGNING.md` | Creación, configuración, verificación y rotación |
| `lib/services/same_account_claim_policy.dart:49` | Evidencia de cuarentena de login |
| `docs/BUG_REGISTER.md` | Registro de hallazgos, corregido en Fase A |

### Comandos de reproducción

```powershell
C:\flutter\bin\flutter.bat analyze --no-pub
C:\flutter\bin\flutter.bat test --no-pub
C:\flutter\bin\flutter.bat test --no-pub test\identity
C:\flutter\bin\flutter.bat test --no-pub test\p2p_auth_negative_test.dart
C:\flutter\bin\flutter.bat test --no-pub test\sql_security_regression_test.dart test\android_release_signing_test.dart
C:\flutter\bin\flutter.bat build apk --debug --no-pub

# Release: sin configuración debe fallar con el mensaje de P0-4.
cd android
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
.\gradlew.bat :app:assembleRelease --no-daemon --console=plain

# SQL (base desechable; ver el arnés para precondiciones)
psql -v ON_ERROR_STOP=1 -f supabase_migrations/tests/z212_behavioral_test.sql
```

---

## 8. Registro de bloqueadores y criterios — actualización 2026-10-27

Sesión de preparación (instrucción del CTO). Se inspeccionó Git y documentos
antes de editar; se conservaron todos los cambios y archivos untracked;
**sin commits, sin push, sin conexión a staging/producción, sin migraciones
remotas, sin secretos generados**. Gate: sigue **NO-GO / BLOCKED**.

### 8.1 Evidencia de validación (2026-10-27)

| Comando | Resultado |
|---|---|
| `flutter analyze --no-pub` | **PASS** — `No issues found!` |
| `flutter test --no-pub` (suite completa) | **289/289 PASS** (≈ 02:08). La línea base reportada del 2026-10-23 (271/271) se conserva; los +18 son los tests de integración del handshake añadidos después de ese reporte, más ajustes posteriores de suites existentes |
| Guardas incluidas | identidad (alcance completo), P2P negativos (24), integración handshake (18), cifrado/mesh, guardas SQL Z-001/Z-212, guardas de firma release |
| `git diff --check` | PASS (sin errores de whitespace, ver §9.4) |
| `flutter analyze --no-pub` (2.ª ejecución, mismo día — gate CTO; exit 0) | **PASS** — `No issues found!` (25.0 s) |
| `flutter test --no-pub` (2.ª ejecución; exit 0) | **289/289 PASS** (1:20), 0 fallos. Cifra medida en esta ejecución, no histórica; coincide con la de arriba |
| `flutter build apk --release --no-pub` (sin firma; exit 1) | **FAIL CLOSED** — `Release signing is not configured. Refusing to build a release with debug keys` (1:30). El build debug sí compila (`app-debug.apk`) |

### 8.2 Estado por bloqueador tras esta sesión

| P0 | Acción de esta sesión | Estado tras la sesión |
|---|---|---|
| P0-1 (Z-212 en staging/prod) | Runbook reforzado con puerta de autorización expresa del propietario por proyecto/ventana (`Z212_STAGING_RUNBOOK.md` §0); sin conexión remota | **BLOCKED (autorización)** — requiere confirmación §0 |
| P0-2 (Z-004 P2P) | Verificación concreta de que el contrato sigue **sin cablear** (0 imports en `NearbyService`); diseño de integración completo expansión de §7.8.1 en `PHASE_E` (8 aspectos exigidos + plan WI-1…WI-7 + método de demostración del cierre de Z-004) | **BLOCKED (implementación)** — diseño listo para implementar tras decisión CTO |
| P0-3 (login existente) | Dirección de producto registrada: **Alternativa A** (`PHASE_F` §10); comparación A1/A2/A3 re-verificada contra el esquema (9 FKs, 21 políticas, 45 `auth.uid()`); 5 ambigüedades listas para firma con resolución propuesta; pruebas R-01…R-14 clasificadas en automatizables/2 dispositivos (0/14 ejecutadas); cuarentena intacta | **BLOCKED (decisión CTO §10.4)** — se detuvo antes de implementar |
| P0-4 (release) | Verificado: sin `key.properties` ni keystores en el repo (fail-closed intacto); estado BLOCKED documentado en `RELEASE_SIGNING.md` | **BLOCKED (keystore real)** — instrucciones ya completas |
| P0-5 (suite) | — (resuelto el 23; suite 289/289 re-verificada) | **VERIFIED (local)** |
| P0-6 (dos dispositivos) | — sin hardware disponible en el ambiente | **NOT VERIFIED** |
| P0-7 (E2EE/FS) | Comparación de librerías con evidencia (`E2EE_RATCHET_ALTERNATIVES.md`): **no existe paquete Dart adecuado** (GPL-3.0/AGPL-3.0/no-auditadas/sin adopción); recomendación de módulo propio con KATs + matriz + revisión externa; parámetros 2000/7d/10min justificados; condiciones de migración documentadas; **comentario falso de Forward Secrecy corregido** en `chat_e2ee_service.dart:59` (PHASE_G §6.6 paso 1, sin cambio de comportamiento) | **BLOCKED (decisión CTO + implementación v2→v4)** |

### 8.3 Decisiones que requieren autorización/propiedad (paquete único)

1. **Z-212 staging:** completar la confirmación §0 del runbook (proyecto,
   ventana, backup probado, responsable).
2. **Login existente (P0-3):** aprobar variante (A2 objetivo, o A1 shim con
   fecha de salida) + responder las 5 ambigüedades (`PHASE_F` §10.3-§10.4).
3. **E2EE (P0-7):** aprobar `E2EE_RATCHET_ALTERNATIVES.md` §6 (ruta, parámetros,
   presupuesto de revisión) + autorizar la fase v2.
4. **P2P (P0-2):** autorizar el cableado de §7.8.1 y el `device_certificate`
   v2; decisión del modelo de confianza de primer contacto (OOB obligatorio).
5. **Keystore release (P0-4):** crear/custodiar el keystore real fuera del
   repositorio (instrucciones en `RELEASE_SIGNING.md`).
6. **Dos dispositivos físicos (P0-6):** disponer del hardware de la matriz
   `PHASE_H_TWO_DEVICE_MATRIX.md`.

### 8.4 Cambios de esta sesión (diff completo)

- **Solo documentación:** `PHASE_F` (§10), `PHASE_E` (§7.8.1), `PHASE_G`
  (§9 actualizado), `Z212_STAGING_RUNBOOK` (§0 + §11), `RELEASE_SIGNING.md`
  (estado), este gate (§9) y el nuevo `E2EE_RATCHET_ALTERNATIVES.md`.
- **Un cambio de código (comentario):** `chat_e2ee_service.dart:59` — se
  retira la afirmación falsa de FS (mandato explícito de PHASE_G §6.6 paso 1
  y criterio de salida (b) de P0-7); sin cambio de comportamiento; suite y
  analyze re-ejecutados después del cambio (§9.1).

---

## 9. Firma

| Campo | Valor |
|---|---|
| Decisión | **NO-GO / BLOCKED** |
| Fecha | 2026-10-23 |
| Auditor | Agente AI (DeepSeek V4.1 Flash Free) |
| Firma humana de CTO | **PENDIENTE** |
| Cambios en remoto | Ninguno |
| Cambios commiteados | Ninguno |

**Este gate debe reevaluarse cuando los P0 estén cerrados con evidencia, no cuando el calendario lo exija.**
