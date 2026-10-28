# IDENTITY MIGRATION THREAT MODEL

> FASE 2.1.1 — Integration Readiness & Migration Bridge Design.
> READ-ONLY. Modelado de amenazas de la futura migración, anclado al código real.

## 0. Criterio de valoración (sin números arbitrarios)

- **Impact**: Alto = exfiltración de claves/secrets, suplantación total, pérdida de historial
  E2EE, corrupción irreversible. Medio = confusion de identidad recuperable, indisponibilidad
  temporal. Bajo = ruido, fugas de metadatos públicos.
- **Likelihood**: Alto = vector activo sin mitigación y alcanzable hoy. Medio = viable solo con
  condiciones (reinstalación, red, versión). Bajo = requiere acceso local físico o condición rara.
- **Blocking**: True = impide iniciar 2.2 sin mitigación previa.

## 1. Trust boundary map actual (adaptado al código)

```
User ─▶ UI (screens/auth/login) ─▶ ZoneIdService (genera zone_id, keys, registra users)
                                      │                                │
                                      ▼                                ▼
                               SecureStorage (legacy keys + sk_*)    Supabase (auth.uid / users / RPC)
                                      │
                                      ▼
                              Isar (perfiles/mensajes)
                                      │
                                      ▼
                       Nearby/BLE ──▶ PAIR(payloads)  ══ FRONTERA 1 (radio, sin auth)
                       Supabase ─────▶ BACKEND (RLS auth.uid) ═══════ FRONTERA 2 (JWT anónimo)
```

- **Entra información no confiable**: payloads Nearby/BLE (perfiles de otros) y respuestas
  del backend. Nunca se valida con firma en producción.
- **Se valida identidad**: solo formato de zone_id (validación) y RLS (backend). No hay
  verificación criptográfica de propiedad.
- **Se generan identificadores**: `ZoneIdService._generateZoneId` (`:558-565`);
  UUIDs de mensajes/matches (`supabase_service.dart:17,251`).
- **Se almacenan claves**: SecureStorage legacy (`zone_id_service.dart:23-26`,
  `p2p_security_service.dart:20-21`); nuevo `zid1.*` (`secure_key_store.dart:55-64`).
- **Se transmiten identificadores**: zone_id + public_key a pares (`nearby_service.dart:177-182`);
  uid/zone_id/public_key a Supabase.
- **Se transforma información sensible**: ECDH → session keys (`p2p_security_service.dart:52-64`);
  AEAD → ciphertext (`chat_e2ee_service.dart:60-79`).

## 2. Tabla de amenazas T1–T12

| Threat | Attack Surface | Impact | Likelihood | Existing Mitigation (código) | Required Mitigation (diseño para 2.2) | Blocking? |
| --- | --- | --- | --- | --- | --- | --- |
| **T1 — Identity spoofing** | Emitir zone_id ajeno por radio (`nearby_service.dart:177-182`) o reclamar `claim_zone_id` con un zone_id robado (`supabase_schema.sql:656-666`) | Alto | Alto (hoy: bearer, sin firma, sin proof-of-possession criptográfico) | RLS self-scoped + rate-limit de claims; tokens BT efímeros (`bt_tokens`, `:56-63`); formato estricto | Fingerprints ACC/DEV + firma del dispositivo en presencia; prueba de posesión por firma Ed25519 en claims | **True** (sin firma no se cierra spoofing) |
| **T2 — Identity substitution** | Sustituir `users.id` tras `claim_zone_id` (UPDATE `:673`) → mensajes/matches se re-anclan a un UID nuevo | Alto | Medio (requiere conocer zone_id) | Índice UNIQUE zone_id; auditoría `zone_claim_attempts` (`:625-635`) | Marcar bind `account_id↔uid`; el bridge no re-crea account_id al cambiar uid | **True** (dual/confusión de identidad si se mantiene uid como canónico) |
| **T3 — Identity collision** | Dos `account_id` para el mismo zone_id; colisión índices (`LocalProfile.zoneId` UNIQUE, `isar_models.dart:12-13`; users.zone_id UNIQUE) | Alto | Bajo (índices únicos) | Índices únicos en ambos stores | Bridge valida 1:1 y prohibe `FINALIZED` con duplicados | False |
| **T4 — Replay** | Reenvío de presence/firma vieja o mensajes dedup (TTL `mesh_policy.dart:64-123`) | Medio | Medio | Dedup LRU+TTL de `msgId` (Z-005) | Nonces/timestamps en presencias firmadas; anclaje a epoch de sesión | False |
| **T5 — Downgrade** | Cliente nuevo cae a legacy (claves sin envelope, sin firma) o firmware viejo ignora fingerprints | Alto | Medio (solo si la app no fuerza migración) | Envelope `zidk1:` fail-closed (`secure_key_store.dart:138-163`) | Marca de migración obligatoria y rechazo de operaciones no firmadas tras single-writer | **True** |
| **T6 — Legacy bypass** | Flujo legacy (`ZoneIdService.getOrCreate`, `ensureAuth` regenera clave `:268-294`) continúa tras migrar | Alto | Medio (hoy el flujo legacy es el único) | Z-001 preserva `public_key` remota (`:358-368`) | Single-writer switch + bloqueo de regenerate (usar `InconsistentIdentityStateError`) | **True** (sin switch hay dual-source de hecho) |
| **T7 — Unauthorized migration** | Rearranque que re-ejecuta el bridge (recupera estado mynte) o app modificada | Medio | Bajo | Idaempotencia de `ensureAccountIdentity` (`identity_registry.dart:156-158`) | Marca `FINALIZED` + checksum de snapshot; segundo arranque = no-op | False |
| **T8 — Key/identity mismatch** | Usar X25519 legacy de cuenta como device encryption de un device equivocado; o ligar clave pública a la identidad errada | Alto | Medio | `KeyPurposeMismatchError` (`x25519_device_service.dart:59-78`); separación D1/D2 | Registro `device×encryption_public_key` versionado (D7) y verificación "misma seed ⇒ misma pública" en import | **True** |
| **T9 — State desynchronization** | `zone_identity` y legacy divergen (crash en BRIDGED, fallo de red) | Medio | Medio | `putBy*` idempotente (`identity_persistence.dart:87,151`) | Máquina de estados persistente (`IDENTITY_MIGRATION_STATE_MACHINE.md`) con reconciliación | **True** (necesita máquina) |
| **T10 — Partial migration** | Algunos consumidores quedan en legacy sites | Alto | Medio | — (no existe control) | Checklist de consumidores + `VERIFIED` requiere 100% convertido | **True** |
| **T11 — Rollback abuse** | Reintentar rollback tras FINALIZED o re-migrar | Medio | Bajo | — | Máquina terminal; `rollback` prohibido desde FINALIZED | False |
| **T12 — Local database tampering** | Modificar `zone_identity` o filas Isar legacy sin acceso a keystore | Alto | Bajo (requiere acceso local/root) | Fall-closed ante estado corrupto (`identity_persistence_test.dart`) | Checksums de metadatos públicos; validación inter-store | False |

## 3. Threats críticos (requieren mitigación antes de 2.2)

**T1 (spoofing), T2 (substitution), T5 (downgrade), T6 (legacy bypass), T8 (key/identity
mismatch), T9 (sync de estado), T10 (migración parcial).**

Ninguno puede mitigarse en esta fase (read-only). Todos tienen **diseño** de mitigación en
`IDENTITY_MIGRATION_BRIDGE.md`/`IDENTITY_MIGRATION_STATE_MACHINE.md`; su **implementación** es
condición de entrada de 2.2.

## 4. Observabilidad (qué loggear / qué NUNCA loggear)

Debe poderse observar (eventos públicos, I-004):
- `migration_state` (legacy→discovered→…→finalized), resultado de validación, `rollback_cause`.
- `fingerprint_acc`, `fingerprint_dev` (públicos), versión de esquema, hashes de snapshot.
- ids de sesión/claims (nunca el JWT, nunca el *Valor de la clave*).

NUNCA en logs: **seeds, claves privadas, `zidk1:`/`zid1.*` values, tokens de sesión, JWT,
envelopes, payloads cifrados de terceros**. El código legacy ya evita filtrar secretos en
errores tipados (`identity_errors.dart:5-8`); corroborar que los `debugPrint` de servicios
legacy (`zone_id_service.dart:204-206` loggea uid/zone_id públicamente, **no** claves) no
expandan material sensible en 2.2.

## 5. Riesgo de identidad doble (dual-source of truth)

Hoy **no existe en runtime**: la fundación está aislada (0 importadores de producción,
verificado). El riesgo nace en el instante de integrar sin bridge. Mitigación de diseño:
única fuente canónica (`account_id`), marca de migración, single-writer switch, y
prohibición de regenerar. Ver `IDENTITY_MIGRATION_BRIDGE.md` §2 y §10.