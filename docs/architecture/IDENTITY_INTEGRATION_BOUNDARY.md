# IDENTITY INTEGRATION BOUNDARY

> FASE 2.1.1 — Integration Readiness & Migration Bridge Design.
> READ-ONLY. Diseño arquitectónico; no modifica código.

## 1. Límite de la fundación de identidad (FASE 2.1)

### 1.1 Identity ES responsable de

| Responsabilidad | Artefacto en `lib/identity/` | Evidencia |
| --- | --- | --- |
| Identidad canónica (account_id UUID v4 + device_id UUID v4) | `AccountIdentity.accountId` / `DeviceProfile.deviceId` | `models.dart:33-38, 96-100` |
| Representación pública (handle `ZONE-XXXXXXXX` conservado como compat legacy) | `AccountIdentity.zoneId` (nullable) | `models.dart:36-38` |
| Fingerprints v1 (ACC/DEV, 20 chars, display 4×5) | `FingerprintService` + `base32_unambiguous` | `fingerprint_service.dart:80-235`, `base32_unambiguous.dart:29-196` |
| Generación y custodia de material privado (seeds) | `SecureKeyStore` (envelope `zidk1:`, namespace `zid1.`) | `secure_key_store.dart:34-201`, `keys.dart:146-151` |
| Separación criptográfica de roles (D1 firma Ed25519 / D2 ECDH X25519) | `Ed25519IdentityService`, `X25519DeviceEncryptionService`, `KeyPurpose` | `ed25519_identity_service.dart:28-87`, `x25519_device_service.dart:24-99`, `keys.dart:71-82` |
| Ciclo de vida de dispositivo (I-030: pending→active/revoked/…) | `DeviceLifecycle` + `transitionDevice` | `device_lifecycle.dart:65-156`, `identity_registry.dart:263-291` |
| Ownership de claves (account vs device; nunca regeneración silenciosa) | `IdentityRegistry.ensureAccountIdentity/loadAccountKeyMaterial/loadDeviceKeyMaterial` + `InconsistentIdentityStateError` | `identity_registry.dart:129-252`, `identity_errors.dart:114-120` |
| Validación/estado de identidad (estados tipados fail-closed) | `IdentityFoundationError` hierarchy | `identity_errors.dart:14-126` |
| Persistencia de metadatos públicos (instancia `zone_identity`) | `IdentityRepository` + Isar impl | `identity_persistence.dart:23-203`, `identity_persistence_models.dart:19-83` |
| Serialización canónica (UUID lowercase, base64 con padding, UTF-8 sin BOM) | `CanonicalCodec` | `canonical.dart:23-58` |

### 1.2 Identity NO es responsable de

| Fuera del límite | Quién lo gestiona hoy | Evidencia |
| --- | --- | --- |
| UI / screens | `lib/screens/*` | `auth_screen.dart`, `radar_screen.dart`, `chat_screen.dart`, … |
| Mensajería / cifrado de transporte de mensajes | `ChatE2EEService` (AEAD), `SupabaseService`, `MeshPolicy` | `chat_e2ee_service.dart:60-114`, `mesh_policy.dart:146-163` |
| Transporte / red (Nearby, BLE, Supabase Realtime) | `NearbyService`, `BleService`, `SupabaseService` | `nearby_service.dart`, `ble_service.dart` |
| Persistencia de otros dominios (perfiles, mensajes, encuentros, rutas) | `IsarService` (instancia unnamed) | `isar_service.dart:16-22` |
| Sincronización (outbox, pull LWW) | `SyncService` | `sync_service.dart:74-96` |
| Lógica de negocio ajena (matches, bloqueos, reportes, premiums) | `SupabaseService`, `ConnectionService` | `supabase_service.dart:133-236`, `connection_service.dart:11-24` |
| Reclamo de propiedad del ZONE-ID (bearer) | `claim_zone_id` (backend) + `loginWithExistingID` | `supabase_schema.sql:641-700`, `zone_id_service.dart:111-178` |

### 1.3 Contradicciones actuales con esta separación (deuda documentada, NO corregida)

1. **`ZoneIdService` es un singleton legacy que hoy concentra identidad + claves + registro +
   perfil + sesión** (`zone_id_service.dart:14-17` y métodos 44-635). Violación de la separación
   de responsabilidades que la fundación impone (mandato §9). No se toca en esta fase.
2. **`P2PSecurityService` + `ChatE2EEService` mantienen estado criptográfico mutable en
   singletons** (`p2p_security_service.dart:7-10`; `chat_e2ee_service.dart:5-17`) — la fundación
   exige estado inyectado sin singletons globales.
3. **`nearby_service.dart:181-182` transmite la clave pública X25519 del dispositivo como
   identidad de perfil** sin firma, ni fingerprint, ni verificación de propiedad.

## 2. Reglas invariantes que el límite debe preservar

- **I-004**: ningún material privado en modelos/metadatos/logs/transportes
  (`models.dart:14-15`, `identity_errors.dart:5-8`).
- **I-013/I-030**: un dispositivo nace `pending` y jamás se activa implícitamente
  (`device_lifecycle.dart:76-77`; test `identity_registry_test.dart:255`).
- **Fail-closed**: seed ausente/corrupta o estado inconsistente ⇒ error tipado; **nunca**
  regeneración silenciosa (`secure_key_store.dart:19-20`, `identity_errors.dart:114-120`).
- **D1/D2**: Ed25519 firma, X25519 ECDH; prohibida cualquier coerción de rol
  (`x25519_device_service.dart:59-78`).
- **Dual-store ok**: instancia `zone_identity` separada de la base de mensajes legacy
  (`keys.dart:156`, `identity_persistence.dart:43-53`).

## 3. Puntos de acoplamiento futuro (dónde conectará la integración)

### 3.1 Boot (FASE 2.2+)
`initial_loading_screen.dart:57-60` es el punto donde hoy se inicializan `IsarService` y
`P2PSecurityService`. La integración **deberá** añadir aquí la inicialización de
`IdentityRegistry` (keyStore + repository sobre `zone_identity`) y —una vez autorizado—
la máquina de migración (ver `IDENTITY_MIGRATION_STATE_MACHINE.md`). **Hoy vetado: NO tocar
`initial_loading_screen.dart`.**

### 3.2 Identidad de widget/bloqueo de flujo (FASE de UI)
Las pantallas que hoy usan `ZoneIdService().zoneId/uid` (`chat_screen.dart:40,140-148,230`,
`chats_list_screen.dart:20-40`, `auth_screen.dart:24,44-50`) deberán consultar la identidad
canónica vía servicio de presentación — nunca tocar `SecureKeyStore` ni `IdentityRepository`.

### 3.3 Identidad de red (FASE de red)
`nearby_service.dart` deberá emitir **fingerprints** (ACC/DEV) y **firmas de presencia** en
lugar de clave pública desnuda; `supabase_service` de ajustar a columnas de identidad nuevas.
Contratos de transporte (`mesh_policy.dart`, `supabase_schema.sql`) extensibles sin romper RLS.

### 3.4 Mensajería E2EE
`ChatE2EEService` debe tomar sus seeds desde `SecureKeyStore` (device encryption identity) y
usar `DeviceKeyMaterial.sharedSecretWith` (`identity_registry.dart:84-89`) como fuente única de
derivación de sesión, eliminando el singleton.

## 4. Lo que NO debe cruzar el límite

- NUNCA: seeds, claves privadas, envelopes, tokens de sesión, JWT — fuera de `SecureKeyStore`.
- NUNCA: `account_id`/`device_id` como credenciales de transporte (son identificadores, no
  secretos; autorización es por firma).
- NUNCA: fingerprints como secretos (I-026: dato público derivado de claves públicas).

## 5. Fronteras de producción que NO se tocan en esta fase

| Frontera | Archivo | Estado |
| --- | --- | --- |
| Boot | `lib/screens/initial_loading_screen.dart` | NO tocar (vetado) |
| Persistencia legacy | `lib/services/isar_service.dart`, `lib/models/isar_models.dart` | NO tocar |
| Identidad legacy | `lib/services/zone_id_service.dart`, `p2p_security_service.dart`, `chat_e2ee_service.dart` | NO tocar |
| Backend | `supabase_schema.sql`, RPCs | NO tocar |
| Tests existentes | `test/` (raíz e identity) | NO modificar |