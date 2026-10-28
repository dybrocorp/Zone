# PHASE 2.1.2 — CRYPTOGRAPHIC MIGRATION IMPACT

> FASE 2.1.2 · READ-ONLY · Impacto de la decisión de `ADR-0001-X25519-OWNERSHIP.md`
> sobre el diseño de migración de PHASE 2.1.1 (los documentos de 2.1.1 quedan intactos
> como evidencia histórica; este documento es su actualización conceptual).

## 1. Qué cambia (respecto al diseño de PHASE 2.1.1)

- **La decisión de keys deja de ser una opción abierta**: `IDENTITY_MIGRATION_BRIDGE.md` §5
  ofrecía "import vs rotate" sin preferencia; ahora queda **decidido**: import validado de
  la X25519 legacy como encryption key de **device_1**. La rotación solo es posible como
  operación de **dispositivo** (D7), nunca silenciosa de cuenta.
- **El objeto de la migración es más preciso**: no se migra "una clave de cuenta", sino una
  *clave de extremo* que hoy vive en una fila de cuenta (`users.public_key`). El bridge
  pasa a modelar: legacy key → `SecureKeyStore zid1.device.<deviceId>.deviceEncryption` +
  metadatos `DeviceDbo.deviceEncryptionPublicKeyBase64` (`identity_persistence_models.dart:64-69`).
- **`users.public_key` cambia de semántica**: de "identidad E2EE de la cuenta" a "valor
  heredado de device_1 durante la transición". No se elimina durante la migración (lo
  consumen peers y el chat), pero deja de anclarse como canónico en el target.
- **Trust anchor formalizado**: ya no es la server assertion ni el bearer; el ancla es la
  cuenta Ed25519 + fingerprints ACC/DEV. El estado de migración `AUTHORIZED`/`MIGRATED`
  queda vinculado a la confirmación I-030 del device_1, no a la posesión de `zone_id`.

## 2. Qué permanece

- Máquina de estados de migración (`IDENTITY_MIGRATION_STATE_MACHINE.md`): intacta. La
  import se ejecuta en el estado `BRIDGED`; la eliminación de claves legacy solo tras
  `VERIFIED → FINALIZED`.
- Rollback (`IDENTITY_MIGRATION_ROLLBACK.md`): intacto en su orden de destrucción; la
  import no borra nada antes de FINALIZED ⇒ rollback sigue siendo no destructivo.
- Validaciones fail-closed del bridge: se mantienen y se **refuerzan** con la verificación
  `misma seed ⇒ misma pública` (requisito de import).
- Fronteras NO tocadas (`IDENTITY_INTEGRATION_BOUNDARY.md` §5): boot, persistencia legacy,
  identidad legacy, backend y tests existentes siguen vetados en esta fase.

## 3. Qué debe congelarse

| Ítem | Motivo | Evidencia |
| --- | --- | --- |
| Semántica de `users.public_key` | es la ancla de compatibilidad E2EE durante la transición | `zone_id_service.dart:358-369` (Z-001) |
| Formato de `zone_id` (`^ZONE-[A-Z0-9]{8}$`) | contrato compartido con backend y malla | `zone_id_service.dart:553-556`, `supabase_schema.sql:641-700` |
| RLS y RPC actuales (`claim_zone_id`, `delete_own_account`, `resolve_bt_token`) | la autorización de transporte se sustituye, no se muta a medias | `supabase_schema.sql:162-186,641-700,753-793` |
| Comportamiento Z-001 (no sobrescribir `public_key` sin prueba) | evita rotación silenciosa durante la ventana | `zone_id_service.dart:358-369` |
| Algoritmos de cifrado de transporte (X25519/ECDH + ChaCha20-Poly1305) | compatibilidad de mensajes | `chat_e2ee_service.dart:12-13,60-79` |

## 4. Qué debe migrarse

1. X25519 legacy (seed local `private_key` + `public_key`) → `SecureKeyStore` under
   `zid1.device.<deviceId>.deviceEncryption` (verificado: 32 bytes; `misma seed ⇒ misma pública`).
2. Metadatos que materializan device_1: `DeviceDbo` con `encryptionKeyVersion = 1`
   (D7) y `AccountIdentity.zoneId = valor legacy`.
3. (Documentado, no implementado) vínculo `account_id ↔ último auth.uid` como bind de
   sesión, para absorber la mutabilidad de `users.id` (`supabase_schema.sql:673`).

## 5. Qué NO debe migrarse

- **Session keys `sk_<zoneId>`**: son estado derivado, no identidad; se re-derivan
  (reutilizar `DeviceKeyMaterial.sharedSecretWith`, `identity_registry.dart:84-89`). No se
  copian, no se renombran, no se versionan.
- **`pseudo_*` (pseudónimos offline)**: no-identity; se conservan tal cual en el almacén
  legacy o se descartan, no participan del puente.
- **Ciphertext de mensajes**: jamás se re-cifra en migración; los mensajes existentes
  siguen siendo válidos porque el extremo (device_1) conserva la clave.
- **`users` (fila completa)**: no se re-crea; solo se vincula. `zone_id` y `public_key`
  intactos durante la transición.
- **Account private key legacy como identidad nueva**: la X25519 importada no se convierte
  en identidad de cuenta (la identidad es Ed25519 de firma).

## 6. Qué debe preservarse

| Concepto | Mecanismo | Evidencia |
| --- | --- | --- |
| Descifrado del historial E2EE | import preserva el extremo device_1 | `chat_e2ee_service.dart:105-109` (sin import: pérdida) |
| Sesiones mesh TOFU existentes de peers hacia la cuenta | misma clave para device_1 | `nearby_service.dart:917-931,1022-1044` |
| Continuidad de identidad de cuenta | account Ed25519 + fingerprints ACC | `models.dart`, `fingerprint_service.dart:102-112` |
| Rollback no destructivo | no borrado antes de FINALIZED | `IDENTITY_MIGRATION_ROLLBACK.md` |

## 7. Qué debe invalidarse

1. **Regeneración silenciosa de clave local de cuenta** (`ensureAuth`,
   `zone_id_service.dart:268-294`): pasa a ser un *vetado*; cualquier ausencia de clave se
   resuelve por recovery o re-enrollment firmado, nunca generando un extremo nuevo sin
   marca.
2. **Auto-sanación destructiva del almacén seguro** (`_storage.deleteAll()`,
   `zone_id_service.dart:76-81`): incompatible con la transición; el bridge nunca debe
   escalar borrando todo.
3. **Interpretación de `users.public_key` como identidad canónica": pierde vigencia (queda
   como valor heredado, ver §1).
4. Una vez `FINALIZED`, **cualquier claim/registro que sobrescriba `public_key` sin firma**
   debe rechazarse (control futuro).

## 8. Actualización conceptual del estado de la máquina (2.1.1) bajo esta ADR

```
LEGACY ── DISCOVERED ── VALIDATED ── BRIDGED ── AUTHORIZED ── MIGRATED ── VERIFIED ── FINALIZED
                        │              │ import X25519 → device_1 (D7 v1, verificado)
                        │              │ users.public_key = heredado de device_1
                        │              └ sk_* / pseudo_* NO se migran
                        ▼
                  MIGRATION_FAILED → rollback (LEGACY intacto)
```

- `BRIDGED` ahora **garantiza**: device_1 Encryption = legacy key (import verificado).
- `AUTHORIZED` ahora **garantiza**: confirmación I-030 firmada (nunca implícita).
- `VERIFIED`: incluye (a) fingerprints ACC/DEV estables, (b) un mensaje legacy descifrado
  con la clave importada (KTEST-09), (c) ausencia de regeneración silenciosa.

## 9. Interacción con PHASE 2.1.1 (referencias, sin modificación)

- `IDENTITY_MIGRATION_BRIDGE.md` §5 (import vs rotate) → ahora **decidido** (ver §1).
- `IDENTITY_MIGRATION_THREAT_MODEL.md` → el nuevo threat model K1–K12
  (`X25519_CRYPTOGRAPHIC_IDENTITY_MODEL.md` §11) refina T1/T2/T5/T6/T8/T9/T10 con el foco
  en ownership de claves; no contradice el anterior, lo especifica.
- `IDENTITY_DEPENDENCY_MATRIX.md` §4.2 (X25519 CONFLICTING) → resuelto por esta ADR:
  la X25519 legacy es (y solo puede ser) identidad de cifrado de **dispositivo** en el target.