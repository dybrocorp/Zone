# IDENTITY DEPENDENCY MATRIX

> FASE 2.1.1 — Integration Readiness & Migration Bridge Design.
> READ-ONLY — ningún artefacto de este documento implica modificación de código.
> Estado del repositorio verificado: `main @ 7f59b776c62cc131fd05dc999e99cbb7804385e8` (2026-09-25).

## 1. Propósito

Inventario exhaustivo de qué módulos **consumen** identidad, **producen** datos de identidad,
dependen de mecanismos **legacy**, y qué riesgo/accción futura corresponde a cada uno.

Regla: ninguna relación se inventa. Cada fila cita el archivo:línea que la respalda.

## 2. Clasificación de dependencias

- **DIRECT** — el módulo lee/escribe/espera un identificador de identidad como entrada o salida directa.
- **INDIRECT** — toca datos que *portan* identidad (filas, payloads) sin crear/validar identidad.
- **OPTIONAL** — identidad está presente solo en caminos alternativos.
- **LEGACY** — mecanismo antiguo que implementa identidad (debe migrarse en FASE 2.2+).
- **CONFLICTING** — contradice la arquitectura de identidad aprobada (riesgo de ownership/scope).
- **UNKNOWN** — no determinable por el código actual.

## 3. Matriz por módulo

| Módulo (archivo) | Consume Identity | Produce Identity Data | Legacy Dependency | Riesgo | Clasificación | Acción futura |
| --- | ---: | ---: | ---: | --- | --- | --- |
| `lib/identity/*` (13 dart + 1 g.dart) | — (autocontenido) | account_id, device_id, ed25519/x25519 keys, fingerprints, DeviceStatus | Ninguno | Ninguno (aislado, 0 importadores de producción) | **NEW FOUNDATION** | Mantener aislado; publicar API de consumo en 2.2 |
| `lib/services/zone_id_service.dart` | zone_id (´:69-107´), supabase_uid (´:23-26´) | Genera `ZONE-XXXXXXXX` (´:558-565´), claves X25519 (´:196-202´), registra fila `users` (´:209-214´) | Sí — owner legacy de identidad+claves+registro | Alto: dual identity, rotación silenciosa de clave (´:268-294´), auto-sanación destructiva `deleteAll` (´:78´) | **LEGACY (owner)** | Reemplazar por `IdentityRegistry` + bridge; conservar zone_id como handle |
| `lib/services/p2p_security_service.dart` | private_key/public_key (´:20-21´), session keys `sk_*` (´:70-74´) | Deriva shared secrets ECDH (´:52-64´) | Sí | Alto: comparte las MISMAS claves que `ZoneIdService`; identidad criptográfica de dispositivo duplicada | **LEGACY (CONFLICTING)** | Keys pasan al `SecureKeyStore` (namespace `zid1.`); derivación de sesión migra a `DeviceKeyMaterial.sharedSecretWith` |
| `lib/services/chat_e2ee_service.dart` | X25519 keypair singleton (´:12-13,15-17´) | Cifra/descifra AEAD ChaCha20-Poly1305 (´:60-114´) | Sí | Alto: única consumidora de material privado; `initFromPrivateBase64` acepta seed sin envelope ni versión (´:33-36´) | **LEGACY (CONFLICTING)** | Consumir seeds desde `SecureKeyStore`; mantener algoritmo AEAD como capa de mensajería |
| `lib/services/isar_service.dart` | userId, zoneId, publicKey en perfiles (´:29-63´) | Persiste datos con identidad embebida | Sí — base mensajes legacy | Medio: instancia **unnamed** con 5 colecciones (´:16-22´); coexistir con `zone_identity` | **LEGACY DIRECT (persistencia)** | No migra; convivir por instancia separada (documentado en FASE 2.1) |
| `lib/models/isar_models.dart` | LocalProfile.userId/zoneId/publicKey (´:9-13,23´), LocalMessage.senderId/receiverId (´:60-61´), MeshRoute.targetZoneId (´:86´), pending.senderId (´:112´) | — | Sí | Medio: `zoneId` UNIQUE local (´:12-13´) colisionaría si la fundación persistiera un zone_id distinto | **LEGACY** | Convivir; el bridge garantiza 1 zone_id por cuenta |
| `lib/services/supabase_service.dart` | auth `user.id` (UID), `zone_id`, `public_key` (´:209-214´ en ZoneIdService; sw: ´:642,674´) | Envía identity a backend (bt_tokens, matches, messages) | Sí | Medio: mensajería identifica por UID; RLS ancla en `auth.uid()` | **LEGACY DIRECT (transporte)** | Contratos de transporte estables; sumar columnas de identidad nueva solo en 2.2 |
| `lib/services/nearby_service.dart` | `_zoneIdService.zoneId` (´:162´), `getMyProfile` (´:164-166´) | **Transmite `zoneId` + `publicKey` X25519 a pares** (´:177-182´), pseudónimos `pseudo_*` (´:264-282´), resuelve BT tokens → perfil (´:596-599´) | Sí | **Alto**: la clave pública del dispositivo cruza a la malla sin firma; spoofing posible (TOFU) | **LEGACY DIRECT (trust boundary)** | Incluir fingerprints + firma de presencia del device en 2.2+; el bridge valida keys |
| `lib/services/sync_service.dart` | UID/zoneId en rows sync (messages ´:128´, profiles ´:196-203´, encounters) | — | Sí (transporte) | Bajo | **INDIRECT** | Sin cambios; solo consumo de repos autenticados |
| `lib/services/connection_service.dart` | myId/theirId = UIDs (´:11-12´) | — | Sí (envuelve SupabaseService) | Bajo | **INDIRECT** | Sin cambios |
| `lib/services/mesh_policy.dart` | source/target = zone_id en paquetes (´:146-163´) | — | Sí (direccionamiento lógico) | Bajo | **INDIRECT** | zone_id permanece como dirección de ruta mesh |
| `lib/screens/initial_loading_screen.dart` | — | Boot: `IsarService().initialize()` + `P2PSecurityService().initialize()` (´:57-60´), `Supabase.initialize` (´:65-68´), `SyncService().initialize()` (´:72´) | Sí (wiring legacy) | **Alto si se integra mal**: es el punto donde el puente deberá inicializarse en 2.2 | **LEGACY (boot)** | Inyectar inicialización de `IdentityRegistry` + estado de migración en 2.2 (vetado hoy) |
| `lib/screens/*` (auth ´:44-50´, login, profile_*, radar, chats ``:20-40``, chat ``:40,140-148,230``, settings…) | `ZoneIdService().zoneId/uid` | — | Sí (UI) | Medio: UI desconoce account_id/device_id | **LEGACY DIRECT (UI)** | Apis de presentación consumen fingerprints/identidad en fases de UI |
| `lib/widgets/user_avatar.dart`, `lib/config/radar_config.dart` | — (datos de perfil) | — | Parcial | Bajo | **OPTIONAL** | Sin cambios |
| `lib/services/premium_service.dart` | import `zone_id_service.dart` (´:3´) | — | Sí (indirecta) | Bajo | **INDIRECT** | Sin cambios |
| `lib/services/notification_service.dart` | matchId/senderId (eventos) — sin UID/zone_id | — | Bajo | Bajo | **OPTIONAL** | Sin cambios |
| `lib/services/connectivity_service.dart`, `permissions_service.dart`, `logger_service.dart`, `ble_service.dart`, `ble_proximity_service.dart` | — | — | — | Bajo | **Sin dependencia** | Sin cambios |
| `test/identity/*` | — | — | Ninguno (fundación) | — | **NEW FOUNDATION (tests)** | Expandir en 2.2 (véase gap matrix) |

## 4. Dependencias cruzadas críticas

### 4.1 Compartición de claves entre singletons legacy
`ZoneIdService` y `P2PSecurityService` escriben y leen las **mismas** claves del almacén seguro:
`private_key` y `public_key` (`zone_id_service.dart:23-26` vs `p2p_security_service.dart:20-21`).
Ambos son singletons (`zone_id_service.dart:14-17`, `p2p_security_service.dart:7-10`) → estado
criptográfico mutable global **fuera** de la fundación (la fundación lo prohíbe; mandato §18).
Riesgo de doble escritura / regeneración en concurrencia.

### 4.2 X25519 con doble lectura semántica (CONFLICTING)
- **Legacy (producción):** una clave X25519 **por cuenta/usuario** — persistida en
  `users.public_key` (`supabase_schema.sql:17`) y en `LocalProfile.publicKey`
  (`isar_models.dart:23`), difundida a pares (`nearby_service.dart:181-182`).
- **Fundación (FASE 2.1):** una clave X25519 **por dispositivo** (device encryption identity)
  — `DeviceProfile.deviceEncryptionPublicKeyBase64` (`models.dart:105-106`) y `DeviceDbo`
  (`identity_persistence_models.dart:63-66`).
Esto es una colisión de ownership (`Identity ≠ Key Ownership`, §12 del encargo): el bridge
debe resolver a qué identidad pertenece la X25519 legacy (ver `IDENTITY_MIGRATION_BRIDGE.md`).

### 4.3 Instancias Isar separadas
La fundación abre `zone_identity` (`identity_persistence_models.dart` + `keys.dart:156`) con
`AccountIdentityDbo`/`DeviceDbo`; producción usa la instancia **unnamed** con 5 colecciones
(`isar_service.dart:16-22`). Coexistencia verificada (sin colisión); el bridge opera sobre la
instancia `zone_identity` y **no** toca la base de mensajes (regla de FASE 2.1).

### 4.4 Zero importers de producción
Grep repo-wide (`package:zone/identity|IdentityRegistry|FingerprintService`) confirma **0
importadores fuera de `lib/identity/` y `test/identity/`**. La fundación es hoy código muerto
por diseño (frontera no integrada documentada en FASE 2.1).

## 5. Identificadores que NO existen aún

- `account_id` / `device_id` (fundación): **ningún** módulo de producción los conoce.
- Fingerprints ACC/DEV (20 chars): **ninguna** pantalla o transporte los emite hoy.

## 6. Resumen de acciones por tipo

| Tipo | Módulos | Acción |
| --- | --- | --- |
| REEMPLAZAR (2.2+) | zone_id_service, p2p_security_service, chat_e2ee_service | Bridge + single-writer |
| TRANSPORTE (sin cambio) | supabase_service, sync_service, connection_service, mesh_policy | Mantener contratos; ampliar columnas/claims cuando aplique |
| UI (2.2+) | screens | Consumir fingerprints/identidad vía servicio de presentación |
| COEXISTIR | isar_service, isar_models | Instancia `zone_identity` dedicada; 1 zone_id por cuenta |
| SIN DEPENDENCIA | connectivity, permissions, logger, ble* | Sin acción |

## 7. Evidencia no determinable

- Comportamiento exacto de `PremiumService` respecto a UID/zone_id (la lectura de `premium_service.dart`
  revela solo el import en línea 3): **UNKNOWN — requires implementation clarification** antes de 2.2.
- Uso real de fingerprints en futuras pantallas: **UNKNOWN (por diseño, no existe aún)**.