# PHASE 2.1 — Security Evidence (invariantes, threat model, coexistencia legacy)

> **Tipo:** Evidencia de seguridad de la implementación de FASE 2.1 (masa CTO).
> **Fecha:** 2026-09-25 · **Estado:** cierre de FASE 2.1 (`IMPLEMENTATION: VERIFIED`).
> **Autoridad (invariantes):** `PHASE_2_SECURITY_INVARIANTS.md` (I-001…I-030) ·
> threat model: `PHASE_2_THREAT_MODEL.md` (T1/T3/T4/T12/T13) ·
> criptografía: `PHASE_2_CRYPTO_DECISIONS.md` (D1/D2) ·
> coexistencia: `PHASE_2_LEGACY_ACCESS_POLICY.md`, `PHASE_2_BOOTSTRAP_POLICY.md`.
> **Fuentes de prueba:** `test/identity/*` (73/73) + `flutter analyze` (0 issues) +
> `PHASE_2.1_TEST_MATRIX.md`.

---

## 1. Criterio

Las columnas usan:

- **CUBRE** — invariante activado y probado por tests de esta fase.
- **RESPETA** — sin conflicto; el diseño de la fundación lo respeta aunque la prueba
  formal corresponda a otra fase (transiciones/ops de red, migraciones).
- **FUERA** — responsabilidad de fases posteriores (servidor/UI/migración); sin
  contradicción en esta fase.

Ninguna evidencia asume pruebas inexistentes: cada fila cita el archivo de test exacto.

## 2. Tabla de invariantes I-001…I-030

| Invariante | Estado en FASE 2.1 | Evidencia |
|---|---|---|
| **I-001** — Conocer ZONE-ID no demuestra posesión | **RESPETA** | La fundación nunca autoriza ops privilegiadas por ZONE-ID: el material de firma requiere la seed del almacén seguro (`loadAccountKeyMaterial`); el fingerprint (I-026) no es credencial. El bootstrap firmado es de FASE 2.2 (servidor). |
| **I-002** — X25519 nunca firma | **CUBRE** | `crypto_separation_test.dart` #3/#4/#5: ECDH rechaza clave pública Ed25519 (`KeyPurposeMismatchError`); X25519 no expone API de firma; dominios de tipo/bytes distintos. Prohibición por tipo y por test. |
| **I-003** — Toda op. privilegiada requiere autorización criptográfica | **RESPETA** | `transitionDevice` exige eventos derivados de confirmación firmada / revocación firmada (modelo I-030). La verificación de firmas de red (challenge/código 1-uso) es de FASE 2.2. `device_lifecycle.dart` + `identity_registry_test.dart` #11-#15. |
| **I-004** — Privadas nunca salen del dispositivo | **CUBRE** | Solo `flutter_secure_storage` (backend del almacén seguro) contiene seeds; envelope `zidk1:` + namespace `zid1.`. `secure_key_store_test.dart` #9: los errores no exponen material. `models.dart`/`toJson` nunca serializa claves. Las seeds no entran en Isar ni en fingerprints. |
| **I-005** — No mensajes en claro por mesh | **FUERA** | No hay mesh en FASE 2.1 (sin integración). |
| **I-006** — No reuso de nonces | **FUERA** | Ratchet/sesiones de FASE 2.2 (la fundación no cifra mensajes v1). |
| **I-007** — No peer no-autenticado como confianza | **FUERA** | Perfil/fingerprint de red en FASE 2.2; el fingerprint v1 ya está listo (I-017) para `profile_exchange` v2. |
| **I-008** — No replay de challenges | **FUERA** | Servidor (FASE 2.2). |
| **I-009** — No downgrade silencioso secure→legacy | **RESPETA** | Sin integración: la fundación no conversa con el stack legacy; nada negocia versión. |
| **I-010** — No migración destructiva sin rollback | **RESPETA** | No se escribe en la DB legacy; la instancia `zone_identity` es nueva y aislada. |
| **I-011** — Sin afirmar FS sobre historial legacy | **FUERA** | Sin afirmaciones sobre historial. |
| **I-012** — Servidor no custodio de privadas | **RESPETA** | Nada sube a Supabase en esta fase; solo existen públicas/fingerprints en metadatos locales. |
| **I-013** — Primer enroll no otorga estado activo sin confirmación firmada | **CUBRE** | `registerDevice` nace `pending`; solo `bootstrapConfirmed` lo activa. `identity_registry_test.dart` #8/#11/#15: PENDING carece de derechos (revoke/compromiso prohibidos). |
| **I-014** — Sin acceso directo a tablas identidad/recovery | **FUERA** | Servidor (FASE 2.2). |
| **I-015** — `account_id` inmutable e irreutilizable | **CUBRE** | IDs inyectados/deterministas; sin API de cambio; persistencia rechaza dispositivos con account distinto para el mismo device (`DuplicateIdentityRecordError`). `identity_persistence_test.dart` #2/#6. |
| **I-016** — Recovery code single-use | **FUERA** | Recovery de FASE 2.2. |
| **I-017** — Fingerprint determinista y canónico | **CUBRE** | KAT oficiales integrados (ACC/DEV-A/DEV-B) contra evidencia intermedia; determinismo account/device; canonicalización UUID/base64 fija. `base32_fingerprint_kat_test.dart` #1-#10, `fingerprint_normalization_test.dart`, `identity_registry_test.dart` #6/#7. |
| **I-018** — Serialización canónica única para firmas | **RESPETA** | `canonical.dart` canonicaliza UUID/base64 para fingerprints; la firma de payloads canónicos de red es de FASE 2.2. |
| **I-019** — Migraciones idempotentes/reversibles | **FUERA** | Sin migraciones en esta fase (instancia nueva). |
| **I-020** — Sin doble keypair / fuente única de verdad | **CUBRE** | Una seed por propósito, generada una sola vez y guardada en el almacén seguro; `ensureAccountIdentity` es **idempotente**: con metadatos+seed presentes jamás regenera (I-020/I-021 en local). `identity_registry_test.dart` #1/#3/#4 (inconsistencias ⇒ error, no regeneración). |
| **I-021** — Retirada de claim no deja usuarios sin vía | **RESPETA** | Sin retirada de claims legacy; coexisten (ver §4). |
| **I-022** — `verify_zone_id` no es oráculo | **FUERA** | Servidor (FASE 2.2). |
| **I-023** — Estado del ratchet secreto local | **FUERA** | Sin ratchet en esta fase. |
| **I-024** — Recovery no degrada garantía del historial | **FUERA** | Recovery de FASE 2.2. |
| **I-025** — Recovery jamás restaura X25519 v1 | **RESPETA** | La fundación solo genera X25519 nuevas para devices nuevos; nada se restaura de legacy. |
| **I-026** — Fingerprint nunca es secreto ni credencial | **CUBRE** | El fingerprint se deriva de **metadatos públicos** (accountId, deviceId, pk pública) y no participa en ninguna autorización local; input sin X25519. Tests: KAT + fingerprints desde metadatos (`identity_registry_test.dart` #6/#7). |
| **I-027** — Única secuencia de bootstrap en curso | **RESPETA** | El modelo local es de un dispositivo en PENDING por cuenta en los tests; el control de concurrencia de red (409/rotación) es servidor (FASE 2.2). |
| **I-028** — Legacy sin devices tiene vía M0-M5 | **FUERA** | Migración/recovery (fases posteriores). |
| **I-029** — Bootstrap code cumple política | **RESPETA** | TTL/single-use/rate-limit son servidor; el estado local modela `bootstrapExpired` ⇒ GONE (GC). `identity_registry_test.dart` #18. |
| **I-030** — Estados de dispositivo siguen la máquina formal | **CUBRE** | `device_lifecycle.dart` implementa la máquina completa: PENDING→ACTIVE→REVOKED/COMPROMISED; LOCKED/KILLED/GONE; sin transiciones indefinidas; terminales fail-closed. `identity_registry_test.dart` #11-#18 (9 tests). |

## 3. Threat model (`PHASE_2_THREAT_MODEL.md`)

| Threat | Mitigación local en FASE 2.1 | Evidencia |
|---|---|---|
| **T1** (ZONE-ID como credencial) | El fingerprint y el ZONE-ID local no autentican nada; el material exige seed segura. | matriz §7 #1/#5 |
| **T3** (enumeración/`verify_zone_id`) | Nada expone existencias por red en esta fase. | — |
| **T4** (enroll sin confirmación firmada) | Device nace `pending` e inactivo; estado capturado en máquina I-030. | matriz §7 #8/#11/#15 |
| **T12/T13** (custodia de privadas / pérdida) | Privadas solo en almacén seguro; sin exportación, sin logs, sin errores con material; regeneración jamás silenciosa (inconsistencia ⇒ error + detección). | matriz §6 #3-#9 |
| **T16** (peer no autenticado) | Sin networking; fingerprint v1 listo para `profile_exchange` v2 (I-017). | matriz §3 |

## 4. Coexistencia con el sistema legacy

| Recurso | Legacy | Fundación | Colisión |
|---|---|---|---|
| Almacén seguro (claves) | `zone_id`, `private_key`, `public_key`, `supabase_uid`, `sk_*`, `pseudo_*` | namespace `zid1.` (ej. `zid1.account.accountIdentitySigning`), envelope `zidk1:` | **Ninguna** (prefijos disjuntos; test de borrado por prefijo matriz §6 #8) |
| Isar | instancia sin nombre (mensajes) | instancia **`zone_identity`** con `AccountIdentityDbo`/`DeviceDbo` | **Ninguna** (instancia y esquemas propios) |
| Claves criptográficas | `private_key`/`public_key` v1 (X25519 legacy) | material nuevo Ed25519/X25519 generado por la fundación | **Ninguna** (no se lee ni reutiliza material legacy) |
| Fingerprint | (no existía) | v1 `ZONE-FP-1` sobre metadatos públicos | **Ninguna** (input sin claves privadas) |

Verificación adicional: `git grep` de los nombres de claves legacy vs. `zid1.`/`zidk1:`
no encuentra solapamiento; `flutter analyze` global (0 issues) confirma que no hay
referencias cruzadas entre la fundación y `lib/services/`.

## 5. Estado Git exacto (evidencia documentada)

- `HEAD`: `7f59b776c62cc131fd05dc999e99cbb7804385e8` — sin cambios.
- `git diff` / `git diff --cached` (árbol rastreado): **vacíos** — cero modificaciones,
  cero staging, cero commits.
- `git status --short`: únicamente **untracked** — `lib/identity/`, `test/identity/` y
  docs FASE 2.0/2.1 (incl. los 3 reportes nuevos de esta iteración).
- Sin secretos ni claves generadas en el repositorio; la DLL nativa de Isar usada para
  tests vive en el pub cache (fuera del repo), referenciada por variable de entorno.

## 6. Veredicto

```
SECURITY EVIDENCE FASE 2.1: CONSISTENTE — sin invariantes en conflicto
INVARIANTES CUBIERTOS POR TEST: I-002, I-004, I-013, I-015, I-017, I-020, I-026, I-030
RESPETADOS SIN CONTRADICCIÓN: I-001, I-003, I-009, I-010, I-012, I-018, I-021, I-025, I-027, I-029
FUERA DE ALCANCE (fases posteriores, sin contradicción): I-005..I-008, I-011, I-014, I-016, I-019, I-022..I-024, I-028
```

**STOP.** Esta evidencia cierra FASE 2.1. No se continúa hacia FASE 2.2 ni hacia
cualquier pieza del alcance prohibido; se espera la revisión CTO.