# IDENTITY COMPATIBILITY MATRIX

> FASE 2.1.1 — Integration Readiness & Migration Bridge Design.
> READ-ONLY. Coexistencia temporal, no integración prematura.

## 1. Matriz por componente

| Componente | Current (producción) | Phase 2.1 (fundación) | Phase 2.2 Target (diseño) | Compatibility |
| --- | --- | --- | --- | --- |
| **Identity** | `auth.uid` + `zone_id` ("ZONE-XXXXXXXX") + X25519 de cuenta en secure storage (`zone_id_service.dart:23-26`); single-writer legacy | `account_id`/`device_id` UUID + Ed25519 (firma) + X25519 de dispositivo + fingerprints, sin escritores | `account_id` canónico; zone_id como handle; device_1 activo por I-030; single-writer nuevo | Requiere bridge; doble store temporal; **nunca** dos conjuntos activos simultáneos para el mismo usuario |
| **Auth** | Supabase anonymous + `claim_zone_id` con prueba bearer (formato+rate-limit) (`supabase_schema.sql:641-700`) | sin participación (fundación no autentica transporte) | Auth solo como **session/transport bind** del UID; autorización de identidad por firma Ed25519 + fingerprints | Auth legacy sigue operando hasta single-writer; RLS/invariantes backend no cambian |
| **Messaging** | X25519 ECDH + ChaCha20-Poly1305 vía `ChatE2EEService` (session keys `sk_*` TOFU) (`chat_e2ee_service.dart:12-13,60-114`) | `DeviceKeyMaterial.sharedSecretWith` (`identity_registry.dart:84-89`) | session keys derivadas desde la identidad de dispositivo canónica; E2EE legacy descifrable (import de X25519) | Mismo algoritmo AEAD; solo cambia la fuente de seeds y la custodia (SecureKeyStore) |
| **Persistence** | Isar **unnamed**: `LocalProfile, LocalEncounter, LocalMessage, MeshRoute, LocalPendingMessage` (`isar_service.dart:16-22`; `isar_models.dart`) + secure storage legacy | Isar **`zone_identity`**: `AccountIdentityDbo, DeviceDbo` (`keys.dart:156`, `identity_persistence_models.dart:19-83`) + secure storage `zid1.*` | Conviven las dos instancias; `zone_identity` ganadora; líneas de mensajes intactas | Sin colisión verificada entre instancias ni entre keys (`zid1.`/`zidk1:` vs legacy) |
| **Networking** | Nearby/BLE difunde `zone_id` + `public_key` (X25519) (`nearby_service.dart:177-182`); Supabase vía `auth.uid` + `users` | sin participación (aislada) | fingerprints ACC/DEV de presencia + firma del device; transporte autenticado | Evolución de payloads, no de transporte; contratos (`mesh_policy.dart:146-163`) estables |
| **Profile** | `LocalProfile` + `users` (`supabase_schema.sql:13-33`) | `AccountIdentity.zoneId` alinea el handle | perfil asociado a `account_id`; public_key de cuenta sustituida por device keys publicadas | Fila `users` temporal con ambos; migración de columnas solo en 2.2+ |
| **Sessions/E2EE keys** | `sk_*` por peer zoneId (`p2p_security_service.dart:70-74`) | — | sesiones derivadas bajo demanda desde claves de dispositivo (sin persistir secretos de sesión a largo plazo si no es necesario) | Keys `sk_*` legacy conservadas hasta FINALIZED para no romper mensajes en vuelo |

## 2. Qué puede coexistir temporalmente (reglas de convivencia)

1. **Doble store** de metadatos: permitido **solo** durante la ventana de transición, con
   marca de estado y prioridad de lectura definida (canónico primero); prohibido al terminar.
2. **Doble clave de dispositivo**: X25519 legacy (importada) + Ed25519 device nueva conviven
   en `zid1.*` con propósitos distintos (`KeyPurpose.deviceEncryption` vs
   `deviceIdentitySigning`, `keys.dart:71-82`) — sin conflicto semántico (D2 vs D1).
3. **Auth legacy + autorización nueva**: `auth.uid` sigue siendo el ancla RLS del backend;
   la autorización de identidad (firmas/fingerprints) se añade tiempo después — no se sustituye
   de golpe (evita romper RLS).
4. **Mensajería**: la misma primitiva AEAD con seeds del `SecureKeyStore` — la fuente cambia,
   el formato de mensaje no.

## 3. Qué NO puede coexistir

- **Dos `account_id` activos para un mismo usuario** (dual identity) — prohibido por índice
  único + marca `FINALIZED`.
- **Dos `zone_id` con el mismo dueño** en producción (`zone_id` UNIQUE en `users`,
  `supabase_schema.sql:15`, y en `LocalProfile.zoneId`, `isar_models.dart:12-13`).
- **Dos escritores del par `private_key`/`public_key`** (concurrencia `ZoneIdService` vs
  `P2PSecurityService`) — el single-writer elimina esta carrera.
- **Rollback después de FINALIZED** — terminal.

## 4. Compatibilidad de formatos y representaciones

| Formato | Legacy | Nueva | Compatible | Notas |
| --- | --- | --- | --- | --- |
| Handle | `ZONE-` + 8×[A-Z0-9] (`zone_id_service.dart:558-565`) | `AccountIdentity.zoneId` (idéntica forma) | ✅ Sí | Contrato compartido con backend (`zone_id_format_test.dart:7-28`) |
| Key X25519 | b64 con padding (44) en store/`users.public_key` | b64 con padding (44) (`canonical.dart:44`) | ✅ Sí | Misma serialización |
| Fingerprint | no existe | 20 chars base32 + display 4×5 (`base32_unambiguous.dart:29-40`) | a introducir | No choca: namespace nuevo |
| ID de cuenta | `auth.uid` (UUID, mutable por login) | `account_id` (UUID v4, inmutable) | ⚠️ Distintos por diseño | El bridge documenta el mapeo `account_id ↔ último uid` en metadatos |
| Envelope de secreto | base64 crudo (legacy keys) | `zidk1:<b64>` (`secure_key_store.dart:135-136`) | ✅ Sí con importación | `private_key` legacy = seed X25519 de 32 bytes, compatible con `newKeyPairFromSeed` |

## 5. Riesgo residual y mitigación de diseño

| Riesgo | Mitigación |
| --- | --- |
| Mantener legacy más allá de lo necesario (deuda) | Marca `FINALIZED` + checklist de conversión de consumidores |
| Regresión de E2EE | Import de X25519 legacy (Opción A) + tests de continuidad exigidos en 2.2 |
| Confusión UUID (account_id vs uid) | Mutable `uid` NUNCA actúa como clave de identidad; solo bind de sesión |
| Payloads de malla desactualizados durante transición | Versión explícita en payload (`isEncrypted`, `type`) y evolución sin romper parseo |