# FASE 0–1 · Auditoría base y estado del repositorio

**Proyecto:** ZONE (Flutter)
**Repositorio:** `D:\Proyectos\Zone`
**Rama:** `main`
**Commit base:** `7f59b776c62cc131fd05dc999e99cbb7804385e8`
**Fecha:** 2026-10-23
**Auditor:** agente AI (DeepSeek V4.1 Flash Free). Este documento no sustituye una firma humana de CTO.

---

## 1. Veredicto ejecutivo

| Área | Resultado | Estado |
|---|---|---|
| Análisis estático (`flutter analyze --no-pub`) | `No issues found!` | **VERIFIED** |
| Suite completa (`flutter test --no-pub`) | 219 passed · 21 failed | **FAILED** (los 21 fallos son ambientales) |
| Fallos funcionales en tests que no requieren Isar nativo | 0 | **VERIFIED** |
| Tests de identidad que requieren `isar.dll` | 21 bloqueados | **BLOCKED** (entorno Windows) |
| Estado remoto de Supabase | No consultado / no aplicado | **NOT VERIFIED** |
| Validación en dispositivos físicos | No realizada | **NOT VERIFIED** |
| Cambios en remoto, commits, push o deploy | Ninguno | **VERIFIED** |

La auditoría encontró **cinco defectos SQL demostrables** que el registro previo no cerraba, además de defectos en el pipeline de descubrimiento cliente y bloqueadores ya conocidos (identidad P2P, E2EE sin forward secrecy, firma release con claves debug y login de usuario existente en cuarentena).

El árbol de trabajo ya contenía trabajo previo del usuario. **No se revirtió, borró ni sobrescribió ese trabajo.**

---

## 2. Estado de Git al inicio

| Item | Valor |
|---|---|
| Rama | `main` |
| Commit | `7f59b776c62cc131fd05dc999e99cbb7804385e8` |
| Archivos modificados | 20 |
| Archivos untracked | Documentación de fases, fundación `lib/identity/`, migraciones `z210`/`z211`, tests nuevos, etc. |
| Commits creados en esta auditoría | 0 |
| Push / deploy / migración remota | 0 |

### 2.1 Archivos modificados preexistentes

```text
android/app/src/main/AndroidManifest.xml
lib/models/isar_models.dart
lib/models/isar_models.g.dart
lib/screens/chat_screen.dart
lib/screens/chats_list_screen.dart
lib/screens/initial_loading_screen.dart
lib/screens/login_screen.dart
lib/screens/public_profile_sheet.dart
lib/screens/radar_screen.dart
lib/services/isar_service.dart
lib/services/mesh_policy.dart
lib/services/nearby_service.dart
lib/services/p2p_security_service.dart
lib/services/permissions_service.dart
lib/services/supabase_service.dart
lib/services/sync_service.dart
lib/services/zone_id_service.dart
supabase_deploy.sql
supabase_schema.sql
test/mesh_policy_test.dart
```

### 2.2 Trabajo untracked relevante

- `lib/identity/` — fundación Ed25519/X25519, persistencia y migración (no integrada aún con auth/E2EE).
- `lib/services/same_account_claim_policy.dart` — cuarentena del claim same-account.
- `lib/services/discovery_policy.dart`, `encounter_key.dart`, `match_outbox*.dart`, `match_pair.dart`, `zone_identity_bootstrap_service.dart`.
- `supabase_migrations/z210_encounter_key.sql`, `z211_match_canonical.sql`, `z212_security_hardening.sql`.
- `test/identity/`, `test/discovery_readiness_test.dart`, `test/encounter_idempotency_test.dart`, `test/match_canonicalization_test.dart`, `test/match_outbox_test.dart`.
- `docs/PHASE_2_*`, `docs/architecture/`, `docs/device_lab/`, `docs/migration/`, `docs/phases/`, `docs/security/`, `docs/CRYPTO_CTO_REVIEW.md`.

Estos archivos **no fueron creados ni modificados por esta auditoría** salvo donde se indica expresamente en `PHASE_2_SECURITY_HARDENING_Z212.md`.

---

## 3. Toolchain verificada

| Herramienta | Versión |
|---|---|
| Flutter | 3.47.2 · stable |
| Dart | 3.13.2 |
| DevTools | 2.60.0 |
| Engine | `1cf1c4773fb941c4c74a7f8bb144a8837596c0f4` |
| PostgreSQL (validación SQL) | 18.4 |
| Plataforma | Windows (win32) |

---

## 4. Baseline de calidad

### 4.1 Análisis estático

```powershell
C:\flutter\bin\flutter.bat analyze --no-pub
```

Salida final:

```text
Analyzing Zone...
No issues found! (ran in 12.2s)
```

**Estado: VERIFIED.** No se silenciaron reglas ni se excluyeron archivos para obtener este resultado.

### 4.2 Suite de tests

```powershell
C:\flutter\bin\flutter.bat test --no-pub
```

Salida final:

```text
00:30 +219 -21: Some tests failed.
```

Los 21 fallos están concentrados en tres archivos y **todos** comparten el mismo error ambiental:

```text
Invalid argument(s): Failed to load dynamic library
'D:\Proyectos\Zone\isar.dll': error code 126
```

| Archivo | Fallos | Passed | Causa |
|---|---:|---:|---|
| `test/identity/identity_bootstrap_integration_test.dart` | 3 | 0 | `isar.dll` error 126 |
| `test/identity/identity_persistence_test.dart` | 10 | 0 | `isar.dll` error 126 |
| `test/identity/migration_persistence_test.dart` | 8 | 0 | `isar.dll` error 126 |
| **Total** | **21** | **0** | **BLOCKED (entorno)** |

Los otros diez archivos de `test/identity/` pasan completos (105 tests):

```text
base32_fingerprint_kat_test.dart           10 passed
crypto_separation_test.dart                 7 passed
device_b_safety_test.dart                  12 passed
fingerprint_normalization_test.dart        18 passed
identity_bootstrap_test.dart                7 passed
identity_registry_test.dart                19 passed
migration_controller_test.dart             12 passed
migration_state_machine_test.dart           9 passed
secure_key_store_test.dart                  9 passed
zone_identity_bootstrap_service_test.dart   2 passed
```

**Clasificación:** los 21 fallos son **BLOCKED por entorno**, no defectos funcionales demostrados. No se marcaron como `skip`, no se borraron y no se alteró la suite para ocultarlos. La suite completa **no puede declararse verde** en este host.

### 4.3 Cobertura de la validación

- Los tests que no dependen de Isar nativo pasan: 219.
- Los tests de identidad que usan el almacén nativo no pueden ejecutarse en Windows sin `isar.dll` (error 126 = dependencia nativa no encontrada).
- No se ejecutó `flutter test --coverage` como criterio de aceptación porque la suite no está verde.

---

## 5. Hallazgos de seguridad en `HEAD`

Los siguientes defectos se confirmaron leyendo el SQL canónico de `HEAD`, no solo la documentación.

| ID | Severidad | Evidencia en `HEAD` | Impacto |
|---|---|---|---|
| **Z-212-01** | **P0** | `HEAD:supabase_schema.sql:673` — `UPDATE public.users u SET id = v_uid WHERE u.zone_id = p_zone_id` dentro de `claim_zone_id` | Account takeover: cualquier usuario autenticado que conozca un ZONE-ID ajeno puede reescribir el `users.id` de la víctima. El formato/rate-limit no prueba posesión. |
| **Z-212-02** | **P1** | `HEAD:supabase_schema.sql:408-410` — policy `"Resolver token BT"` con `USING (auth.role() = 'authenticated' AND expires_at > now())` | Cualquier autenticado puede leer el mapping `token → user_id` de todos los usuarios activos. La RPC devolvía avatar/handles sin aplicar visibilidad. |
| **Z-212-03** | **P0/P1** | `HEAD:supabase_schema.sql:472-475` — policy `"Actualizar mensaje con match aceptado"` permite UPDATE a participantes | Un participante puede reescribir `sender_id`, `ciphertext`, `nonce`, `mac` o `match_id`: forgery/tampering del historial. |
| **Z-212-04** | **P1** | `HEAD:supabase_schema.sql:435-437` — policy `"Aceptar o rechazar match"` solo con `USING (auth.uid() = receiver_id)`, sin `WITH CHECK` | El receiver puede reescribir `requester_id`/`receiver_id` o degradar un match `accepted`. |
| **Z-212-05** | **P1** | `HEAD:supabase_schema.sql` — policy `"Actualizar propio perfil"` permite UPDATE de todas las columnas propias, sin trigger de columnas protegidas | Un usuario puede ponerse `is_shadowbanned=false` / `reports_count=0` y evadir moderación. |
| **Z-004** | **P0/P1** | `lib/services/nearby_service.dart` — `profile_exchange` vincula un `zone_id` declarado a una clave X25519 aportada por el par | Spoofing/MITM en primer contacto (TOFU). No hay prueba de posesión de la identidad. |
| **Z-101** | **P1** | E2EE X25519 estático-estático | Sin forward secrecy, sin HKDF, sin AAD y sin ratchet. No se puede afirmar FS. |
| **Release signing** | **P0 de release** | `android/app/build.gradle.kts:38` — `signingConfig = signingConfigs.getByName("debug")` | Un AAB/APK de release se firma con claves debug; no es apto para distribución. |
| **Login existente** | **P0 de producto** | `lib/services/same_account_claim_policy.dart:49` — `allowSameAccountClaim = false`; `loginWithExistingID` retorna error | Un usuario existente no puede recuperar su cuenta en otro dispositivo. Es una decisión de producto pendiente, no un bug de criptografía. |

### 5.1 Discrepancia documental sobre Z-001

`docs/BUG_REGISTER.md` declara **37 hallazgos** y marca Z-001 como:

```text
Estado: REMOTE_APPLIED + VERIFIED (2026-09-23)
```

Esa verificación cubrió, según el propio registro:

- `REVOKE` de `anon`/`PUBLIC`;
- formato estricto del ZONE-ID;
- rate-limit;
- que el claim no alterara `public_key`;
- idempotencia.

**No cubrió la prueba de posesión.** El `UPDATE users SET id = v_uid` seguía presente en `HEAD` (línea 673). Por tanto:

- el estado remoto **no puede confirmarse desde este entorno**;
- la etiqueta “VERIFIED” no debe interpretarse como “account takeover cerrado”;
- el control Z-212 es el que cierra la reescritura de identidad, y lo hace por cuarentena, no inventando una prueba criptográfica.

---

## 6. Inventario de decisiones y restricciones

| Restricción | Cumplimiento |
|---|---|
| No usar `git reset --hard`, `git clean`, `git checkout --` | Cumplido |
| No borrar archivos, migraciones ni tests | Cumplido |
| No aplicar migraciones en producción | Cumplido |
| No commit / push / deploy | Cumplido |
| No exponer secretos | Cumplido (sin `.env`, tokens ni claves en los reportes) |
| No deshabilitar RLS/TLS/cripto para pasar tests | Cumplido |
| No afirmar tests ejecutados sin ejecutarlos | Cumplido; cada resultado indica comando y estado |
| Preservar trabajo previo del usuario | Cumplido |

---

## 7. Matriz de estado

| Elemento | Estado | Evidencia |
|---|---|---|
| Repo/rama/commit identificados | **VERIFIED** | `git status`, `git log -1` |
| Trabajo previo inventariado | **VERIFIED** | `git status --short`, `git diff --stat` |
| `flutter analyze` | **VERIFIED** | `No issues found!` |
| Suite completa verde | **FAILED** | `+219 -21` |
| Fallos por `isar.dll` | **BLOCKED** | error 126 en 21 tests |
| SQL Z-212 validado localmente | **VERIFIED** | PostgreSQL 18.4, ver Fase 2 |
| SQL Z-212 aplicado en remoto | **NOT VERIFIED** | sin credenciales/autorización |
| RLS real de Supabase ejercitado | **NOT VERIFIED** | stubs locales sin RLS |
| Dispositivos físicos | **NOT VERIFIED** | no disponibles |
| Release firmado | **NOT VERIFIED** | firma debug en Gradle |
| Secretos en el diff | **VERIFIED (sin hallazgos)** | revisión manual + patrones |

---

## 8. Comandos de evidencia

```powershell
git -C D:\Proyectos\Zone status --short
git -C D:\Proyectos\Zone diff --stat
git -C D:\Proyectos\Zone log -1 --format='%H %s'

C:\flutter\bin\flutter.bat --version
C:\flutter\bin\flutter.bat analyze --no-pub
C:\flutter\bin\flutter.bat test --no-pub
C:\flutter\bin\flutter.bat test --no-pub test\identity

git -C D:\Proyectos\Zone grep -n 'UPDATE public.users u SET id = v_uid' HEAD -- supabase_schema.sql
git -C D:\Proyectos\Zone grep -n 'Resolver token BT' HEAD -- supabase_schema.sql
git -C D:\Proyectos\Zone grep -n 'Actualizar mensaje con match aceptado' HEAD -- supabase_schema.sql
git -C D:\Proyectos\Zone grep -n 'Aceptar o rechazar match' HEAD -- supabase_schema.sql
```

---

## 9. Limitaciones de esta fase

1. **Sin acceso remoto a Supabase.** No se verificó el estado real de producción ni se aplicó ninguna migración.
2. **Sin dispositivos físicos.** No se validó BLE/Nearby, mesh multi-salto, receipts ni reinstalación.
3. **Sin keystore de release.** No se pudo probar un AAB firmado.
4. **Windows sin `isar.dll`.** 21 tests de identidad quedan bloqueados; se necesita CI Linux/macOS o el binario nativo correcto.
5. **La validación SQL local usa stubs.** No habilita RLS; prueba funciones y triggers, no el enforcement de políticas.

---

## 10. Conclusión

El baseline es **honesto y reproducible**: análisis estático limpio, 219 tests verdes y 21 bloqueados por una dependencia nativa ausente. La seguridad de `HEAD` **no era aceptable para beta**: el account takeover vía `claim_zone_id`, la mutabilidad de mensajes y matches, la exposición de `bt_tokens` y la auto-modificación de columnas de moderación estaban presentes en el SQL canónico.

La Fase 2 documenta los controles implementados localmente y su validación. El gate de beta se emite en `BETA_READINESS_GATE.md` como **NO-GO / BLOCKED**.
