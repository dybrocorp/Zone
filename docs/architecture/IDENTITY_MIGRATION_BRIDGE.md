# IDENTITY MIGRATION BRIDGE

> FASE 2.1.1 — Integration Readiness & Migration Bridge Design.
> READ-ONLY: este documento es un **diseño arquitectónico**. La implementación queda vetada
> hasta autorización CTO (FASE 2.2 o superior).

## 1. Contexto: dos sistemas de identidad coexisten (hoy, sin acoplarse)

```
LEGACY IDENTITY (producción, activa)              AUTHORIZED IDENTITY (FASE 2.1, aislada)
──────────────────────────────────────────        ─────────────────────────────────────────
- auth UID (auth.uid()) mutable por login         - account_id (UUID v4, inmutable)
- zone_id "ZONE-XXXXXXXX" (bearer, UNIQUE)        - device_id (UUID v4, inmutable)
- X25519 de CUENTA (users.public_key)             - Ed25519 de cuenta (firma)
- X25519 de sesión ECDH (sk_*, TOFU)              - Ed25519 de dispositivo (firma)
- persistencia: secure storage + Isar unnamed     - X25519 de dispositivo (cifrado, versionado)
- registro: supabase users + claim_zone_id        - persistencia: secure storage (zid1.) +
                                                    Isar zone_identity
- sin fingerprints, sin verificación de firma     - fingerprints ACC/DEV v1 (KAT verified)
- importadores: 23 servicios/screens              - importadores: 0 en producción (verificado)
```

## 2. Decisión canónica que fija el diseño

- **Fuente canónica de identidad = `account_id`** (UUID v4 generado una vez por cuenta,
  persistido en `zone_identity`). Evidencia de por qué NO son canónicos los alternativos:
  - `auth.uid()` es **mutable**: `claim_zone_id` reescribe `public.users.id`
    (`supabase_schema.sql:673`) → un login cambia el UID del usuario.
  - `zone_id` es un **handle público bearer** (`isValidZoneIdFormat` `:553-556`): su
    conocimiento basta para reclamar la cuenta (`claim_zone_id` solo valida formato +
    rate-limit, `supabase_schema.sql:656-666`).
- `zone_id` se conserva como **handle público de compatibilidad** dentro de `AccountIdentity`
  (campo `zoneId`, `models.dart:36-38`). El bridge garantiza biyección 1:1 cuenta↔zone_id.

## 3. Entrada del bridge (dónde lee)

| Entrada | Fuente | Evidencia |
| --- | --- | --- |
| `zone_id` | secure storage key `zone_id` | `zone_id_service.dart:23,87-96` |
| `private_key`/`public_key` (X25519 de cuenta legacy) | secure storage keys homónimas | `zone_id_service.dart:25-26,229-230`; `p2p_security_service.dart:20-21,28-47` |
| `supabase_uid` / sesión | secure storage `supabase_uid`; `Supabase.instance.client.auth` | `zone_id_service.dart:24,139,194` |
| Perfil local | Isar unnamed `LocalProfile` (userId/zoneId/publicKey) | `isar_models.dart:9-23` |
| Estado de fila remota | `users` (id, zone_id, public_key) vía `v_profile` | `supabase_schema.sql:231-261` |
| Registro canónico previo | Isar `zone_identity` (`AccountIdentityDbo`/`DeviceDbo`) | `identity_persistence_models.dart:19-83` |
| Session keys derivadas | `sk_*` (secure storage) | `p2p_security_service.dart:70-74` |
| Pseudónimos offline | `pseudo_*` | `nearby_service.dart:279-282` |

## 4. Salida del bridge (dónde escribe)

| Salida | Destino | Notas |
| --- | --- | --- |
| `AccountIdentity` (accountId, zoneId, identityEd25519 b64, v1, active) | Isar `zone_identity` + seeds bajo `zid1.account.*` | vía `IdentityRegistry.ensureAccountIdentity` |
| `DeviceProfile` (deviceId, accountId, device ed25519 + device x25519, **pending**) | Isar `zone_identity` + seeds `zid1.device.*` | vía `IdentityRegistry.registerDevice`; nace `pending` (I-013/I-030) |
| Marca de migración (estado, versiones, checksums públicos, fecha) | Isar `zone_identity` (colección nueva en 2.2) o metadata dedicada | Impiden re-migración y migraciones parciales |
| (Recomendado) semilla X25519 legacy IMPORTADA | `zid1.device.<id>.deviceEncryption` | Ver §5 decisión de keys |

## 5. Decisión de keys: importar vs rotar (a ratificar por CTO)

### 5.1 Opción A — IMPORTAR (recomendada)
La X25519 legacy (`private_key`/`public_key`) se importa como **device encryption identity**
del primer dispositivo (verificación: 32 bytes, decode base64, semilla válida). Motivos:
- Continuidad E2EE de sesiones/mensajes existentes (la X25519 legacy ya está en manos de pares
  y en `users.public_key`, `supabase_schema.sql:17`).
- Sin importar, todo historial cifrado con la clave legacy deja de descifrarse
  (`chat_e2ee_service.dart:105-109` ya maneja este caso como "llaves anteriores", pérdida).
- Coste criptográfico nulo (misma primitiva X25519, `x25519_device_service.dart`).

### 5.2 Opción B — ROTAR
Generar device encryption nueva. Cohérente con "device-scoped", pero rompe compatibilidad E2EE
y exige propagar nueva clave a pares/backend (out of scope de migración 1:1).

### 5.3 Condición obligatoria (ambas opciones)
La clave privada legacy se elimina del namespace legacy **solo después** de `VERIFIED → FINALIZED`
y tras confirmar que `zid1.*` contiene las seeds válidas. Nunca antes (rollback seguro, §9).

## 6. Validaciones del bridge (fail-closed)

1. Formato zone_id: `^ZONE-[A-Z0-9]{8}$` (`zone_id_service.dart:553-556`).
2. Unicidad: máximo 1 account en `zone_identity` (índice único `accountId`,
   `identity_persistence_models.dart:24-25`); máximo 1 `zoneId` por cuenta (la fila `users`
   ya lo garantiza en backend, `supabase_schema.sql:15`).
3. Coherencia seed↔metadatos: si `AccountIdentityDbo` existe pero falta seed (o viceversa),
   `InconsistentIdentityStateError` (`identity_registry.dart:160-164`) — el bridge ABORTA y
   no regenera.
4. Verificación de la X25519 legacy: `public_key` decodificable, 32 bytes, y derivable del
   `private_key` (mismo seed ⇒ misma pública). Si no cuadra ⇒ `SecureKeyCorruptError`
   (fail-closed, `secure_key_store.dart:138-163`).
5. Fingerprint de control: al cerrar el bridge, `FingerprintService.accountFingerprintText`
   sobre el account creado (`identity_registry.dart:305-314`) se contrasta con la evidencia
   KAT (vector ACC) para detectar desviaciones de implementación.

## 7. Ownership y lifecycle

- `account_id`/`device_id` son inmutables una vez materializados (I-015).
- El primer dispositivo nace `pending`; su **activación** ocurre solo por `confirm_bootstrap`
  (código de un uso + firma, I-030; `device_lifecycle.dart:91-92,137-138`).
- Durante la migración el device_1 NO debe quedar `active` implícitamente (regla FASE 2.1).
- El `zoneId` del account se mantiene sincronizado con el legacy mientras dure la transición
  (un único fuente: `AccountIdentity.zoneId` actualizado por el bridge; el valor legacy se
  considera derivado).

## 8. Compatibilidad y fallback durante la ventana de transición

- **Dual-write controlado**: durante la ventana, `ZoneIdService`/`P2PSecurityService` siguen
  funcionando (modo legacy) y el `SecureKeyStore` escribe `zid1.*` en paralelo **sin borrar**
  las claves legacy. Sin esto, el cliente anterior no arranca.
- **Leer con prioridad canónica**: los consumidores nuevos leen `zone_identity`; los legacy
  siguen leyendo sus claves. El punto único de verdad (single-writer) se activa por la marca
  de migración cuando todo consumidor está migrado.
- **Fallback**: si la validación del bridge falla, retorno total a estado `LEGACY` (ver
  `IDENTITY_MIGRATION_ROLLBACK.md`) — ningún dato legacy se destruyó porque borrar es el último
  paso de `FINALIZED`.

## 9. Errores, observabilidad y rollback

- Errores del bridge: reutilizar la jerarquía `IdentityFoundationError`
  (`identity_errors.dart:14-126`), nunca exponer material privado en mensajes.
- Observabilidad: migración solo pública como `migration_state`, `fingerprint_acc`, `zone_id`,
  timestamps, versiones y resultados de validación. **Prohibido** loggear seeds, claves,
  envelopes `zid1.`/`zidk1:`, tokens de sesión o payloads.
- Rollback: ver `IDENTITY_MIGRATION_ROLLBACK.md` (§9/§10).

## 10. Condiciones de bloqueo del bridge (no implementar mientras existan)

1. Sin autorización CTO de FASE 2.2 → **no implementar**.
2. Decisión de keys (import vs rotate) no ratificada por CTO → **no implementar**.
3. Ausencia de tests de migración (gap crítico, ver TEST GAP MATRIX) → **no implementar**.
4. `claim_zone_id` mutando `users.id` (backend) es un riesgo de confusión de identidad → el
   bridge y la UI de login recaban el nuevo UID como bind de sesión, sin re-crear `account_id`.

## 11. Principio rector (encargo §25)

El sistema NO se diseña para que sea fácil migrar; se diseña para
**security + correctness + identidad canónica + mantenibilidad a largo plazo**. La migración
se adapta a esta arquitectura — no al revés.