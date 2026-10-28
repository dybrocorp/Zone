# PHASE 2.1.1 — FINAL READINESS REPORT (INTEGRATION READINESS & MIGRATION BRIDGE DESIGN)

> Análisis 100% READ-ONLY, completado 2026-09-25.
> Branch `main` · HEAD `7f59b776c62cc131fd05dc999e99cbb7804385e8` · Flutter 3.47.2 / Dart 3.13.2.
> No se modificó nada del repositorio guardado.

---

## 1. Repository state

| Ítem | Valor | Evidencia |
| --- | --- | --- |
| Branch | `main` | `git branch` |
| HEAD | `7f59b776c62cc131fd05dc999e99cbb7804385e8` | `git rev-parse HEAD` |
| Working tree | limpio de cambios rastreados; solo **untracked** (docs FASE 2.x, `lib/identity/`, `test/identity/`) | `git status --short`; `git diff`/`--cached` vacíos |
| Versión | `zone` v1.0.4+5; SDK `^3.10.8`; Flutter 3.47.2 stable, Dart 3.13.2 | `pubspec.yaml:6-7` |
| Dependencias relevantes | `supabase_flutter ^2.12.4`, `isar ^3.1.0+1`, `flutter_secure_storage ^9.2.4`, `cryptography ^2.9.0`, `uuid ^4.5.3`, `shared_preferences ^2.5.5`, `nearby_connections ^4.3.0` | `pubspec.yaml:30-54` |

**Regla de oro cumplida**: READ-ONLY estricto. `flutter analyze` y `flutter test` ejecutados
(no destructivos). Sin `dart format`, sin edits, sin autorizaciones implícitas.

## 2. PHASE 2.1 verification state

| Gate | Resultado (2026-09-25) | Nota |
| --- | --- | --- |
| `flutter analyze` | **No issues found** (9.0s) | repositorio completo |
| `flutter test test` (con `ZONE_ISAR_CORE_PATH`) | **96/96 passed** | 73 identity + 23 legacy |
| KAT fingerprint v1 | 3/3 (ACC `GSCB6GVT6DNV8C83-845`, DEV-A `3WMSUNKRR4-9WV4333FH`, DEV-B `NYAYV3MVBJP2BQCXZ4AW`) | verificado en `PHASE_2.1_KAT_VERIFICATION_REPORT.md` y en `base32_unambiguous.dart:19-22` |
| Desglose tests | identity: base32 KA T (10), fingerprint normalization (18), crypto separation (7), identity registry (19), secure key store (9), identity persistence (10) = **73**; legacy: zone_id_format (4), mesh_policy (13), friendly_errors (5), widget (1) = **23** | `test/identity/*`, `test/*_test.dart` |
| Integración en producción | **0 importadores** de `lib/identity` fuera de sí misma y de `test/identity/` | grep repo-wide |
| Estado git | sin cambios rastreados (solo untracked nuevo) | `git status` |

## 3. Identity — canonical identity

**Decisión de diseño (autorizada como propuesta, a ratificar por CTO):**

**`account_id` (UUID v4, inmutable, generado una vez por cuenta y persistido en la
instancia `zone_identity` como índice único) es la identidad canónica.**

| Identificador | Por qué NO es canónico | Evidencia |
| --- | --- | --- |
| `auth.uid` / `users.id` | **Mutable por login**: `claim_zone_id` ejecuta `UPDATE public.users u SET id = v_uid WHERE u.zone_id = p_zone_id` | `supabase_schema.sql:673` |
| `zone_id` (ZONE-XXXXXXXX) | Handle público tipo **bearer**: conocer la cadena permite reclamar la cuenta; solo valida formato + rate-limit | `zone_id_service.dart:553-556` (`isValidZoneIdFormat`), `supabase_schema.sql:656-666` |
| `account_id` (nuevo) | — es el elegido: inmutable, sin exposición pública, único por cuenta | `models.dart:33-38`, `identity_persistence_models.dart:24-25` |

`zone_id` se conserva como **handle público de compatibilidad** dentro de `AccountIdentity`
(`models.dart:36-38`, campo nullable). El bridge garantiza la biyección 1:1 cuenta↔zone_id.

## 4. Identity — lado legacy (producción activa)

| Mecanismo | Implementación | Evidencia |
| --- | --- | --- |
| Generación de ID | `_generateZoneId`: `ZONE-` + 8×[A-Z0-9] con `Random.secure()` | `zone_id_service.dart:558-565` |
| Claves (X25519 de cuenta) | generadas por `ChatE2EEService.generateKeyPair()`; guardadas como **base64 crudo sin envelope ni versión** en `private_key`/`public_key` | `zone_id_service.dart:196-202,229-230`; `chat_e2ee_service.dart:21-24,33-36` |
| Registro remoto | `signInAnonymously` + upsert en `users` con `zone_id`/`public_key` | `zone_id_service.dart:184-236,209-214` |
| Ancora de confianza | forma del ZONE-ID + RLS `auth.uid()`; **sin verificación de firma de presencia** | `supabase_schema.sql:13-33,201-224` |
| Auto-sanación | ante `BadPaddingException`, `_storage.deleteAll()` (borra TODO el almacén seguro) | `zone_id_service.dart:76-81` |
| Rotación silenciosa | `ensureAuth` regenera el par local si falta, dejando la `public_key` remota intacta (Z-001) | `zone_id_service.dart:239-306,268-294,358-368` |
| Sesiones E2EE | session keys `sk_*` por peer zoneId (TOFU ECDH) | `p2p_security_service.dart:52-74` |
| Pseudónimos offline | `pseudo_*` (HMAC-SHA256 sobre zoneId con secret = zoneId) | `nearby_service.dart:264-282` |
| Borrado de cuenta | `deleteAccount` legacy: borra storage + RPC `delete_own_account` + `clearAll` Isar + prefs | `zone_id_service.dart:571-615`; `supabase_schema.sql:162-186` |

## 5. Identity — lado fundación (FASE 2.1, aislada)

| Capacidad | Implementación | Evidencia |
| --- | --- | --- |
| Identidad de cuenta | `AccountIdentity` (accountId, zoneId opcional, Ed25519 pública) | `models.dart:21-73` |
| Dispositivos | `DeviceProfile` (deviceId, Ed25519 firma + X25519 cifrado separados) | `models.dart:82-162` |
| Custodia de secrets | `SecureKeyStore` envelope `zidk1:<b64>` fail-closed bajo namespace `zid1.` | `secure_key_store.dart:130-201`, `keys.dart:146-151` |
| Criptografía | Ed25519 firma (cuenta/device), X25519 ECDH (device); separación D1/D2 estricta | `ed25519_identity_service.dart:28-87`, `x25519_device_service.dart:24-99`, `keys.dart:71-82` |
| Fingerprints v1 | `FingerprintService` + base32 unambiguous (20 chars / display 4×5) | `fingerprint_service.dart:80-235`, `base32_unambiguous.dart:29-196` |
| Ciclo de vida device | máquina I-030 (pending→active/revoked/…), fail-closed | `device_lifecycle.dart:25-156`, `identity_registry.dart:263-291` |
| Registro | `IdentityRegistry.ensureAccountIdentity` idempotente (nunca regenera) | `identity_registry.dart:129-165,156-158` |
| Persistencia | instancia Isar `zone_identity`, `AccountIdentityDbo`/`DeviceDbo`, índices únicos | `identity_persistence.dart:43-53`, `identity_persistence_models.dart:19-83` |
| Borrado de cuenta (fundación) | `deleteAccount` borra **SOLO** el registro de cuenta, sin cascada de devices (contrato FASE 2.1) | `identity_persistence.dart:28,95-99`; test `identity_persistence_test.dart:138-144` |

## 6. Identity — representaciones y collision analysis

| Representación | Ámbito | Almacén | Riesgo de colisión |
| --- | --- | --- | --- |
| `users.id` (auth UID) | backend | Supabase `auth.users` | mutable por login (T2) |
| `zone_id ZONE-XXXXXXXX` | público | Supabase `users.zone_id` UNIQUE (`supabase_schema.sql:15`) + `LocalProfile.zoneId` UNIQUE (`isar_models.dart:12-13`) | biyección exigible; ambos índices únicos lo protegen |
| `account_id` (UUID) | canónico | `AccountIdentityDbo.accountId` UNIQUE (`identity_persistence_models.dart:24-25`) | solo 1 cuenta por instancia |
| `device_id` (UUID) | dispositivo | `DeviceDbo.deviceId` UNIQUE (`identity_persistence_models.dart:54-55`) | 1 device = 1 id |
| X25519 `public_key` legacy | **por cuenta** | `users.public_key` + `LocalProfile.publicKey` (`isar_models.dart:23`) | **conflicto de ownership** con la X25519 por-device de la fundación |
| fingerprints ACC/DEV | público derivado | no persistidos aún | no choca (namespace nuevo) |

**Hallazgo crítico (T8/§12 del encargo — Identity ≠ Key Ownership):** la X25519 legacy es
una clave de **cuenta** (una fila por usuario), mientras la fundación modela una X25519 por
**dispositivo**. El puente debe decidir (import vs rotate) — ver §8.

## 7. Trust boundary (mapa actual)

```
User ─▶ UI/screens ─▶ ZoneIdService (genera zone_id, keys, registra users)
                          │                         │
                          ▼                         ▼
                   SecureStorage (legacy + sk_*)  Supabase (auth.uid / users / RPC / RLS)
                          │
                          ▼
                        Isar (perfiles/mensajes)
                          │
                          ▼
   Frontera 1 (radio): Nearby/BLE ──▶ pares reciben zone_id + public_key SIN firma
   Frontera 2 (nube): Supabase ────▶ JWT anónimo, RLS auth.uid
```

- **Entrada no confiable**: payloads Nearby/BLE (`nearby_service.dart:177-182` transmite
  `publicKey`), respuestas de backend. Sin verificación de propiedad criptográfica.
- **Salida sensible**: uid/zone_id/public_key a Supabase; public_key + zone_id a pares.
- Detalle completo y mapa en `IDENTITY_MIGRATION_THREAT_MODEL.md` §1.

## 8. Migration — puente de migración (diseño)

Documento de referencia: `docs/architecture/IDENTITY_MIGRATION_BRIDGE.md`.

- **Entradas del bridge**: `zone_id`, `private_key`/`public_key` (X25519), `supabase_uid`,
  perfil local Isar, fila remota `users`, estado previo de `zone_identity`.
- **Salidas del bridge**: `AccountIdentity` + `DeviceProfile` (device_1 **pending**, I-030) +
  marca de migración persistente; (Opción recomendada) X25519 legacy **importada** como
  device encryption identity — garantiza continuidad E2EE (pares ya la tienen y
  `users.public_key` apunta a ella).
- **Validaciones fail-closed**: formato zone_id; unicidad 1:1; coherencia seed↔metadatos
  (`InconsistentIdentityStateError`, nunca regenerar); verificación `misma seed ⇒ misma
  pública` para la import; fingerprint de control (vector ACC).
- **Ventana de transición**: dual-write controlado (legacy sigue activo; `zid1.*` se escribe
  sin borrar); single-writer switch solo cuando todos los consumidores migraron.
- **Prohibiciones**: borrar claves legacy antes de FINALIZED; regenerar identidad;
  reasignar `account_id`.

## 9. Migration — máquina de estados (diseño)

Documento de referencia: `docs/migration/IDENTITY_MIGRATION_STATE_MACHINE.md`.

```
LEGACY ─▶ DISCOVERED ─▶ VALIDATED ─▶ BRIDGED ─▶ AUTHORIZED ─▶ MIGRATED ─▶ VERIFIED ─▶ FINALIZED
   ▲                        │  fail           │  fail       │   fail
   └──────────── MIGRATION_FAILED ◀───────────┴─────────────┴──────────── (rollback a LEGACY)
```

- Estados y transiciones válidas/inválidas tabla completa en el documento.
- Terminales: `FINALIZED` (feliz) y `MIGRATION_FAILED` (con único camino de vuelta a LEGACY).
- Idempotencia garantizada por `putBy*` (índices `replace: true`) y por
  `ensureAccountIdentity` idempotente.
- Invoca I-030 en AUTHORIZED: device_1 solo se activa por `confirm_bootstrap`
  (código de un uso + firma).

## 10. Migration — rollback (diseño)

Documento de referencia: `docs/migration/IDENTITY_MIGRATION_ROLLBACK.md`.

- **Regla de oro**: los datos legacy nunca se destruyen antes de FINALIZED. Orden de
  destrucción: 1. metadatos en `zone_identity`; 2. seeds `zid1.*`; 3. (solo FINALIZED) claves
  legacy.
- Rollback total posible desde LEGACY→MIGRATED; **prohibido** desde FINALIZED (terminal).
- Antes del primer write: **snapshot de checksums** (valores legacy, fila `users`,
  perfiles) sin copiar secretos fuera del almacén seguro (I-004).
- Fallo de autorización (confirm_bootstrap) ⇒ device_1 queda pending/locked con cool-down
  (MAX_ATTEMPTS, `device_lifecycle.dart:95-96,139-140`).
- Condiciones que hacen la migración **irrevocable** (bloquean rollback): seeds `zid1.*`
  perdidas, datos legacy ya borrados, o `users.id` reclamado por otro UID durante la ventana.

## 11. Security — threat model (resumen)

Documento de referencia: `docs/security/IDENTITY_MIGRATION_THREAT_MODEL.md`.

**Críticos (bloquean integración sin mitigación):**

| ID | Amenaza | Mitigación diseñada |
| --- | --- | --- |
| T1 | Identity spoofing (radio/claims) | fingerprints ACC/DEV + firma del dispositivo en presencia; prueba de posesión Ed25519 |
| T2 | Identity substitution (`users.id` mutado por claim) | `account_id` canónico inmutable; el bridge no recrea account_id al cambiar uid |
| T5 | Downgrade a legacy sin firma | marca de migración obligatoria; rechazo de operaciones no firmadas tras single-writer |
| T6 | Legacy bypass (regeneración silenciosa en `ensureAuth`) | single-writer switch + bloqueo de regeneración (`InconsistentIdentityStateError`) |
| T8 | Key/identity mismatch (X25519 de cuenta vs de device) | decisión import/rotate + verificación `misma seed ⇒ misma pública` |
| T9 | State desynchronization (crash/trabajo parcial) | máquina de estados persistente + reconciliación idempotente |
| T10 | Partial migration (consumidores en modo legacy) | checklist de consumidores; VERIFIED exige 100% convertido |

Observabilidad: solo eventos públicos (`migration_state`, fingerprints, timestamps);
**prohibido** loggear seeds, claves, envelopes `zid1.`/`zidk1:`, tokens/JWT.

## 12. Dependencies — matriz y conflictos

Documento de referencia: `docs/architecture/IDENTITY_DEPENDENCY_MATRIX.md`.

- **23 servicios legacy** en `lib/services/`; **0 importadores** de la fundación.
- Conflictos detectados:
  1. `ZoneIdService` y `P2PSecurityService` comparten las **mismas** keys
     (`private_key`/`public_key`) — carrera de escritura entre singletons.
  2. X25519: una clave por cuenta (legacy) vs una por device (fundación).
  3. Instancias Isar separadas (legacy unnamed vs `zone_identity`) — coexisten sin colisión.
- Clasificaciones: LEGACY owner (`zone_id_service`), LEGACY CONFLICTING
  (`p2p_security_service`, `chat_e2ee_service`), LEGACY DIRECT (transporte/persistencia:
  `supabase_service`, `nearby_service`, `isar_service`, screens), INDIRECT (`sync_service`,
  `connection_service`, `mesh_policy`, `premium_service`), OPTIONAL (`notification_service`,
  widgets), sin dependencia (`connectivity`, `permissions`, `logger`, `ble_*`).

## 13. Persistence migration impact

| Store | Contenido | ¿Requiere migración? | Diseño |
| --- | --- | --- | --- |
| FlutterSecureStorage legacy | `zone_id`, `supabase_uid`, `private_key`, `public_key`, `sk_*`, `pseudo_*` | **Sí** (núcleo) | import de X25519 a `zid1.*`; borrado SOLO en FINALIZED |
| FlutterSecureStorage `zid1.*` | seeds de cuenta/device (envelope `zidk1:`) | nuevo | creado por el bridge |
| Isar unnamed (5 colecciones) | perfiles, mensajes, encuentros, rutas, pending | **No** | convive; el puente SOLO lee LocalProfile; nunca escribe en la base de mensajes |
| Isar `zone_identity` | `AccountIdentityDbo`, `DeviceDbo` | nuevo | objetivo del bridge; índices únicos |
| Supabase | `users`, `bt_tokens`, `encounters`, `matches`, `messages`, `reports`, `blocked_users`, `zone_claim_attempts` | Columnas nuevas solo en 2.2+ | `users.public_key` congelada (import); no romper RLS |

## 14. API contract impact

| API | Módulo | Impacto | Acción |
| --- | --- | --- | --- |
| `getOrCreate`/`loginWithExistingID`/`ensureAuth`/`deleteAccount`/`clearAuth` | `zone_id_service.dart` | **HIGH** | sustituir por `IdentityRegistry` + bridge |
| `initialize`/`deriveSessionKey`/`deleteAllSessionKeys` | `p2p_security_service.dart` | **HIGH** | keys a `SecureKeyStore`; sesión desde `DeviceKeyMaterial.sharedSecretWith` |
| `generateKeyPair`/`initFromPrivateBase64`/`encrypt`/`decrypt` | `chat_e2ee_service.dart` | **HIGH** | seeds desde el store seguro; AEAD conservado como capa de mensajería |
| `saveProfile`/`getProfile` | `isar_service.dart` | LOW | solo lectura por el bridge |
| `sendConnectionRequest`/`accept`/`reject` | `connection_service.dart` | LOW | sin cambios |
| `ciphertextPacket`/`decideSend`/`decideRelay` | `mesh_policy.dart` | LOW | zone_id sigue siendo dirección de ruta |
| `resolveToken`/broadcast payload | `nearby_service.dart` | MEDIUM (2.2+) | añadir fingerprints/firma de presencia; no romper parseo |
| Boot | `initial_loading_screen.dart` | HIGH (2.2+) | inyectar inicialización `IdentityRegistry` + estado de migración (hoy **vetado**) |

## 15. Test gap analysis (existentes vs faltantes)

**Existen (96 tests):** fundación 73 (KAT, normalización, separación D1/D2, secure store,
registry lifecycle I-030, persistencia Isar + fail-closed) + legacy 23 (formato zone_id,
mesh fail-closed/dedup, friendly errors, widget smoke).

**FALTAN (críticos para la migración — se crearán en 2.2):**

| Gap | Cobertura faltante | Riesgo si no se cubre |
| --- | --- | --- |
| G1 | Detección de identidad dual/duplicada (2 accounts para 1 zone_id; 2 zone_id para 1 account) | T3 collision |
| G2 | Import de X25519 legacy (misma seed ⇒ misma pública; continuidad de descifrado de historial) | T8, pérdida E2EE |
| G3 | Máquina de migración: todas las transiciones válidas/inválidas + estados terminales | T9/T11 |
| G4 | Rollback: snapshot, rollback parcial, idempotencia de reintento, irrevocabilidad | pérdida de datos |
| G5 | Reconciliación inter-store (legacy vs `zone_identity` desincronizados) | T9 |
| G6 | Post-migración: fingerprints estables, sin huérfanos, checksum del snapshot | integridad |
| G7 | Boot integrado (inicialización del bridge en `initial_loading_screen`) | T6 |
| G8 | Cambio de UID por login (claim) no altera `account_id` | T2 |
| G9 | Session keys legacy siguen descifrando tras la migración (no recolocar `sk_*`) | retrocompat E2EE |
| G10 | `ZoneIdService`/`P2PSecurityService` actuales (solo se testea formato del zone_id hoy) | regresiones al sustituir |

## 16. Blocking conditions (verificadas en este análisis)

| # | Condición | Estado | Resultado |
| --- | --- | --- | --- |
| B1 | Autorización CTO del alcance de FASE 2.2 | No otorgada | **BLOQUEA** inicio de 2.2 |
| B2 | Identidad canónica definida | ✅ `account_id` (diseñado aquí) | pendiente ratificación CTO |
| B3 | Ownership de X25519 resuelto (import vs rotate) | Diseño recomienda **import** | pendiente decisión CTO |
| B4 | Legacy sigue controlando authorización (auth.uid + zone_id bearer) | Verdadero en producción | **BLOQUEA** (requiere 2.2) |
| B5 | Tests de migración (G1-G10) | No existen | **BLOQUEA** implementación |
| B6 | Threats T1/T2/T5/T6/T8/T9/T10 mitigados | Diseño listo, código no | **BLOQUEA** integración |
| B7 | Fuga de datos en la transición (borrado prematuro de legacy) | Riesgo eliminado por diseño (rollback §10) | resuelto a nivel diseño |
| B8 | Dependencia circular | No detectada | ok |
| B9 | Estado consistente actual (git/tests/analyze) | ✅ verificado | ok |

**Conclusión**: ninguna condición de bloqueo se ha *implementado*, por diseño (fase
read-only). Todas tienen **diseño**; solo B7 y B8/B9 quedan resueltas ya.

## 17. Gate GO/NO-GO

> Criterio: **NO** emitir GO solo porque los tests de FASE 2.1 pasen.

### Veredicto: **NO-GO** para iniciar la implementación de FASE 2.2 con este estado

**Razones (razonadas, no dogmáticas):**
1. La migración es una operación de **seguridad** que toca auth, RLS, E2EE y malla; no puede
   aislarse en una capa de datos. Implementarla sin los tests G1-G10 y sin el switch
   single-writer reintroduce el riesgo de identidad dual y de pérdida de historial E2EE.
2. La decisión de **ownership de la X25519 legacy** (import vs rotate) cambia el contrato
   remoto (`users.public_key`) y no puede improvisarse en 2.2.
3. `claim_zone_id` muta `users.id` (`supabase_schema.sql:673`): fijar `account_id` como
   canónico es correcto, pero exige acordar el bind de sesión uid↔account antes de tocar
   login.
4. Diseño sin ratificación = riesgo de malentendidos. La autorización CTO (B1) debe
   preceder cualquier commit de integración.

**Lo que SÍ está listo:** la fundación (verificada), el diseño del boundary, la matriz de
dependencias, el puente, la máquina de estados, el rollback, la compatibilidad y el threat
model. Con la autorización CTO y la resolución de B2-B6, FASE 2.2 puede arrancar.

## 18. Required actions (orden sugerido)

1. **CTO**: ratificar (a) `account_id` como identidad canónica; (b) Opción **import** de la
   X25519 legacy; (c) alcance y secuencia de FASE 2.2 (máquina de migración → bridge → boot).
2. Definir en 2.2 el módulo puro de máquina de migración (enum + función `next`, sin estado
   global) y sus tests (G3/G4).
3. Implementar y testear el import de X25519 legacy (G2/G9) con verificación
   `misma seed ⇒ misma pública`.
4. Implementar el bridge con validaciones fail-closed y marca persistente (no hay marca hoy;
   exigirá colección/metadata dedicada en `zone_identity`).
5. Implementar el single-writer switch y el despliegue ordenado de consumidores (checklist).
6. Tests de reconciliación inter-store (G5), post-migración (G6) y de boot integrado (G7).
7. Backend (solo tras lo anterior): columnas/adhesión de identidad nueva sin romper RLS;
   congelar `users.public_key` hasta sustitución coordinada.
8. Estrategia de limpieza: archivo de claves legacy (nunca borrado en caliente) y
   observabilidad conforme a I-004.
9. Re-ejecutar `flutter analyze` + `flutter test` completos tras cada hito.

## 19. Documents produced (esta fase)

| Documento | Ruta |
| --- | --- |
| Phase readiness hub | `docs/phases/PHASE_2_1_1_INTEGRATION_READINESS.md` |
| Este informe final | `docs/phases/PHASE_2_1_1_FINAL_READINESS_REPORT.md` |
| Identity boundary | `docs/architecture/IDENTITY_INTEGRATION_BOUNDARY.md` |
| Migration bridge | `docs/architecture/IDENTITY_MIGRATION_BRIDGE.md` |
| Dependency matrix | `docs/architecture/IDENTITY_DEPENDENCY_MATRIX.md` |
| Threat model | `docs/security/IDENTITY_MIGRATION_THREAT_MODEL.md` |
| Migration state machine | `docs/migration/IDENTITY_MIGRATION_STATE_MACHINE.md` |
| Migration rollback | `docs/migration/IDENTITY_MIGRATION_ROLLBACK.md` |
| Compatibility matrix | `docs/migration/IDENTITY_COMPATIBILITY_MATRIX.md` |

Todos ubicados en directorios nuevos (`docs/phases|architecture|security|migration/`),
verificados como inexistentes antes de escribir; **ningún archivo existente fue modificado**.

## 20. Declaración de cumplimiento READ-ONLY

- No se modificó: código Dart/nativo, `pubspec.yaml`/lock, esquemas SQL ni migraciones,
  pruebas, config, rutas de assets/entorno.
- No se ejecutó: `dart format`, build_runner, editores automáticos.
- Sí se ejecutó (no destructivo): `flutter analyze`, `flutter test`.
- Git: `git status --short` al cierre = igual al baseline + 9 archivos nuevos untracked.