# PHASE 2.0 — Decisiones Criptográficas (D1–D14)

> **Tipo:** Decisiones de diseño cerradas en FASE 2.0 (puerta CTO) — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** REVISIÓN PENDIENTE DE CTO · **FASE 2.0.2**: notas de
> ajuste en D3/D5/D7/D9/D11/D12 (ver `PHASE_2_DECISION_RESOLUTION.md`).
> **Formato:** cada decisión con respuesta, fundamento y referencia cruzada a los otros documentos.

---

## D1 — ¿Ed25519 = identidad de cuenta?

**SÍ.** Ed25519 pública (`identity_public_key`) es la **Account Identity**: firma
operaciones de la cuenta (transfer, recovery, alta de devices, rotación de X25519).
La privada vive SOLO en SecureStorage del dispositivo.
- **Razones:** soporte nativo en `cryptography: ^2.9.0` (ya en pubspec), curvas
  estándar RFC 8032, dominio de separación claro con X25519.
- **Ref:** IDENTITY_ARCHITECTURE §3; CRYPTO_CTO_REVIEW §4.1.

## D2 — ¿X25519 = identidad de cifrado de dispositivo?

**SÍ.** X25519 pública (`device_keys.encryption_public_key`) es la **Device
Encryption Identity**: ECDH para sesiones E2EE. **Jamás firma.**
- **Razones:** el algoritmo ECDH actual es correcto y auditable; solo falta KDF/AAD
  (v3) y ratchet (v5).
- **Regla reforzada:** no existe ninguna firma creada sobre X25519; toda firma es Ed25519.
- **Ref:** IDENTITY_ARCHITECTURE §3; CRYPTO_CTO_REVIEW §4.1 (D2 del doc anterior).

## D3 — ¿Cómo se registra el primer dispositivo?

> **FASE 2.0.2 (OPEN-003/004):** device_1 nace **`pending`** (I-013/I-030); el "evento
> anti-apropiación" no notifica por push en el primer enroll (no hay dispositivo que
> notificar); los parámetros del código de 1 uso y los controles de abuso viven en
> `PHASE_2_BOOTSTRAP_POLICY.md`.

**Bootstrapping de cuenta legacy con código de 1 uso + señuelos de actividad** (sesión
activa sobre la fila `users`), más **evento de apropiación** notificado al dueño:
- `bootstrap_account(zone_id, device_pub_ed25519, device_fp, enc_x25519)` → crea
  `account_identity` + `devices(device_1)` + emite one-time code (TTL 10 min);
- confirmación firmada por el nuevo dispositivo.
- Cuentas frías (sin actividad > 30 días) → **fail-closed** (canal fuera de banda;
  no se permite bootstrap sin verificación adicional).
- **Ref:** IDENTITY_ARCHITECTURE §4-5; DEVICE_MODEL §2.

## D4 — ¿Cómo se registra un segundo dispositivo?

**Opción F combinada: autorización firmada por un device activo + QR con challenge +
verificación de fingerprint**.
- Mecánica: device_1 genera `challenge` de autorización; device_2 escanea el QR (o
  recibe el código por proximidad), firma `register_device(op, device_2)` con su
  Ed25519 **y** devuelve el challenge firmado; device_1 firma `authorize_device`.
- Sirve también **offline parcial** en mesh (paquetes firmados entre pares; el
  servidor valida al sincronizar).
- **Ref:** DEVICE_MODEL §3 (F) y DR-5.

## D5 — ¿Cómo se recupera una cuenta?

**Recovery codes de alta entropía + wrapped private key client-side** (nunca en claro):
- 12 códigos de 16 caracteres alfanuméricos (120 bits) o 1 recovery key de 32 chars.
- Server guarda SOLO `argon2id(secret, salt)` (hash) + `recovery_blob` cifrado con
  clave derivada del recovery key (blob E2EE wraps la privada). Sin claves privadas
  en claro.
- Presentación única, rotación re-envuelve y revoca, revocación posible.
- **Pérdida garantizada del historial v1** si se pierden claves privadas: el servidor
  NO es custodio de claves privadas (regla inviolable).
- **FASE 2.0.2 (OPEN-001/009):** blob = identidad Ed25519 de cuenta **sin X25519 v1**;
  single-use por código + rate-limit 5/15 + rotación del juego —
  `PHASE_2_RECOVERY_POLICY.md` (I-025).
- **Ref:** CRYPTO_CTO_REVIEW §7; IDENTITY_ARCHITECTURE §5.E; DEVICE_MODEL §1.6.

## D6 — ¿Cómo se revoca un dispositivo?

**RPC `revoke_device` con firma de cuenta + reason + auditoría**:
- `sig(revoke_device ‖ device_id ‖ reason ‖ ts)`; status → `revoked`; `device_keys`
  → `retired|compromised`; mesh propaga `revocation_notice` firmado.
- La sesión E2EE del device revocado deja de sincronizarse; las ya entregadas son
  irreversibles (documentado).
- **Ref:** DEVICE_MODEL §6; THREAT_MODEL T11/T14.

## D7 — ¿Cómo se rota la X25519 (device)?

**Rotación firmada y versionada** (`device_keys.key_version++`):
- Lo autoriza el device activo (**firma `device_sk`** + challenge single-use — FASE 2.0.2,
  OPEN-008: es una **op de dispositivo**; `account_sk` solo para ops de cuenta:
  transfer/recover/revoke/rotación de identidad).
- La anterior pasa a `retired` **y se conserva para descifrar historial** hasta
  `retired-legacy` (M5).
- Los mensajes nuevos usan la nueva; los viejos la retirada (igual que hoy con la
  archivada, pero con integridad de autorización).
- **Ref:** DEVICE_MODEL §4; MIGRATION_PLAN M2/M5, riesgo 1.

## D8 — ¿Qué ocurre con usuarios legacy?

**Modo `legacy` se mantiene como soporte total hasta su retiro planificado**:
- Pueden seguir usando la app (v1) mientras el par no exija upgrade; el upgrade es
  opcional y reversible (cada fase compatible: MIGRATION_PLAN §3-4).
- El cultivate de la base (2 usuarios reales en producción) no se perjudica: bootstrap
  M1 con señuelos no bloquea el uso actual.

## D9 — ¿Qué ocurre si se pierde el dispositivo original?

- Sin recovery/tarjetas: el historial cifrado con la X25519 local se pierde
  (irrecuperable — el servidor no tiene la privada). El usuario recupera la **cuenta**
  (ZONE-ID + recovery) y continúa con claves nuevas; el historial viejo queda ilegible
  (placeholder `🔒` ya existente).
- Con recovery: igual recuperación de cuenta; NUNCA recupera privadas viejas.
- **FASE 2.0.2 (OPEN-001):** confirmado — `PHASE_2_RECOVERY_POLICY.md` (I-025).
- **Ref:** IDENTITY_ARCHITECTURE §5.E; THREAT_MODEL T14.

## D10 — ¿Qué ocurre si se pierde recovery?

- Si el usuario pierde códigos y el dispositivo: **pérdida de acceso real** (sin
  puerta trasera) — mitigado por UX (campaña in-app, guardado offline, mock). Es una
  decisión deliberada de seguridad (fail-closed).
- **Ref:** DEVICE_MODEL §1.6; CRYPTO_CTO_REVIEW §7.4.

## D11 — ¿Cómo se evita apropiación mediante conocimiento de ZONE-ID?

Por **tres capas** (ninguna sola es suficiente):
1. **Eliminar `claim_zone_id`** como camino de adueñarse (se sustituye por
   `bootstrap`/`register_device`/`recover_account` con firma).
2. **`account_id` inmutable** separado de `auth.uid()` efímero.
3. **Evento anti-apropiación**: bootstrap pendiente + notificación al dueño + señuelos
   de actividad; fail-closed para cuentas frías.
- **Ref:** IDENTITY_ARCHITECTURE §5.C, §6; THREAT_MODEL T1-T4.
- **FASE 2.0.2 (OPEN-011):** la eliminación del claim se fases en el tiempo: **acotado**
  (`mode=legacy` sin devices) hasta M5, retirada solo bajo condiciones —
  `PHASE_2_LEGACY_ACCESS_POLICY.md` (I-028).

## D12 — ¿Cómo se autentica el primer contacto mesh?

**Handshake v4 (firma + transcript) + fingerprint por pantalla/QR** (CRYPTO_CTO_REVIEW
§5): `profile_exchange` v2 incluye `identity_pk` (Ed25519) y fingerprint v1; el par
verifica la firma sobre el transcript canónico y compara fingerprint fuera de banda.
- **Ref:** MIGRATION_PLAN M3; THREAT_MODEL T16; IDENTITY_ARCHITECTURE §7.
- **FASE 2.0.2 (OPEN-002/016):** el handshake compara el **DEVICE_FINGERPRINT** del
  emisor — `PHASE_2_FINGERPRINT_SPEC.md` (sin X25519 en el input).

## D13 — ¿Cómo se prepara el Double Ratchet?

1. **Interfaces definidas** (MIGRATION_PLAN §5.1): SessionState/RootKey/ChainKey/
   MessageKey/RatchetPublicKey/SkippedMessageKeys/MessageCounter.
2. **Base:** Double Ratchet (Signal) evaluado frente a propios/naïve:
   `CRYPTO_CTO_REVIEW.md` §6.2/6.3 (cumple todos los criterios: FS, PCS,
   out-of-order, multi-device, coste BLE).
3. **Solo en M4**, después de M3; estado por par de devices en SecureStorage; header
   versionado dentro del campo cifrado (schema `messages` no cambia).
- **Ref:** MIGRATION_PLAN §5; CRYPTO_CTO_REVIEW §6.

## D14 — ¿Cómo se migra sin romper historial?

**Fases compatibles y reversibles (M0-M5)** con:
- `key_version`/footer de versión dentro del cifrado → selección de derivación por mensaje.
- Conservación de la clave retirada para historial hasta el cutover.
- Modos legacy/transition/secure con downgrade explícito.
- Nunca se reescribe/descifra el historial; solo se añade.
- Condición de parada por fase tras aprobación CTO.
- **Ref:** MIGRATION_PLAN §1-4.

---

> ⚠️ **Nota de estado:** D1-D14 quedan **propuestas cerradas a nivel de diseño**.
> La aprobación final del CTO se registra en `PHASE_2_CTO_REVIEW_REQUIRED.md`; nada se
> implementa hasta entonces.