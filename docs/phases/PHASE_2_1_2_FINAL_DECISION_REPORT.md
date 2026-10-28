# PHASE 2.1.2 — FINAL DECISION REPORT

> X25519 Ownership & Cryptographic Identity Decision.
> FASE 100% READ-ONLY · 2026-09-25 · Branch `main` @ `7f59b776c62cc131fd05dc999e99cbb7804385e8`.

## Repository Baseline

| Ítem | Valor |
| --- | --- |
| Branch | `main` |
| HEAD | `7f59b776c62cc131fd05dc999e99cbb7804385e8` |
| Working tree | sin cambios rastreados (`git diff`/`--cached` vacíos); solo untracked (docs FASE 2.x + `lib/identity` + `test/identity` + docs nuevos de 2.1.1/2.1.2) |
| Flutter / Dart / SDK | 3.47.2 stable · Dart 3.13.2 · SDK `^3.10.8` |
| Zone | v1.0.4+5 |
| Evidencia de estado | `flutter analyze` 0 issues (9.0s) · `flutter test test` 96/96 |

## PHASE 2.1 Status

VERIFIED (2026-09-25): fundación aislada, 0 importadores de producción, tests 73/73 de
identidad + KAT 3/3, invariantes I-004/I-013/I-030/D1/D2 implantadas. Documentación:
`docs/PHASE_2.1_*`, `lib/identity/`, `test/identity/`.

## PHASE 2.1.1 Status

VERIFIED / **NO-GO** para implementar 2.2 (gate razonado): diseño de boundary, puente,
estado de migración, rollback, compatibilidad y threats; condiciones B1–B9 mapeadas;
«identity canónica = account_id» propuesta.

## Current Cryptographic Topology

Ver `X25519_CRYPTOGRAPHIC_IDENTITY_MODEL.md` §2. Resumen con evidencia:

- El almacén seguro legacy guarda `zone_id`, `supabase_uid`, `private_key`, `public_key`,
  `sk_*`, `pseudo_*` (`zone_id_service.dart:23-26`). La `public_key` remota se congela
  (Z-001, `:358-369`); la local se regenera silenciosamente (`:268-294`).
- Chat: sharedSecret = ECDH(myPriv, peerPub){`chat_screen.dart:194-207`} → AEAD
  ChaCha20-Poly1305 (`chat_e2ee_service.dart:60-79`).
- Mesh: `sk_<zoneId>` TOFU persistida (`p2p_security_service.dart:52-94`;
  `nearby_service.dart:917-931` → `:1022-1044`).
- Sin ratchet/X3DH/prekeys/ephemerals (grep sin matches).

## Key Ownership Matrix

Ver §3 del modelo criptográfico. Conclusiones destacadas:

- **X25519 legacy**: hoy dual (fila de **cuenta** congelada, seed de **instalación**,
  regenerable). Target: **device_1 encryption key (import validado)**.
- **Ed25519 account/device** (fundación): propiedad intacta (`keys.dart:71-82`).
- **Session keys `sk_*`**: estado derivado, NO identidad; no se migran.
- **Ratchet**: no existe; se define como tráfico futuro derivado de claves de device.

## Account Identity

- Sujeto de identidad lógica: `account_id` (inmutable, `models.dart:33-38`) + handle
  `zone_id` (compat, `models.dart:36-38`).
- Autorización por **firma Ed25519** (no por secreto bearer): `keys.dart:71-82`,
  claims por `revoke_device`/`confirm_bootstrap`.
- **NO posee clave ECDH**: derivar ECDH desde la seed de firma violaría D1/D2 (I-002,
  `x25519_device_service.dart:59-78`).

## Device Identity

- Actor criptográfico: `device_id` + Ed25519 de firma (device identity, DEV fingerprint)
  + X25519 de cifrado (device encryption, D7 versionada) — `models.dart:82-162`,
  `identity_persistence_models.dart:49-83`.
- Ciclo de vida I-030: `pending→active` solo por `confirm_bootstrap`
  (`keys.dart:104-131`, `device_lifecycle.dart:65-156`).
- **Es el único propietario válido de claves X25519 en el target.**

## Legacy X25519

- Génesis: 1ª instalación (`zone_id_service.dart:196-202` → `:209-214`).
- Consumidores: chat, radar, peers radio, mesh (ver §6 del modelo).
- **Importable**: sí, con validación `misma seed ⇒ misma pública`; import == preserva
  historial y sesiones; regenerate == rompe continuidad de forma irreversible.
- `users.public_key` deja de ser identidad canónica; deviene valor heredado de device_1
  durante la transición.

## E2EE Continuity

- Preservable **solo con import** (device_1 = extremo legacy). Regenerar provoca
  "Mensaje cifrado con llaves anteriores" en todo el historial (`chat_e2ee_service.dart:105-109`).
- Forward secrecy real (ratchet) es independiente de esta elección; llega en la capa de
  sesión futura anclada a identidades de device.

## Multi-Device Model

Escenarios A–H analizados en `X25519_CRYPTOGRAPHIC_IDENTITY_MODEL.md` §5. Resumen:

- Legacy: solo el device con la seed congelada descifra; reinstalación y device posterior
  rompen continuidad; revocación por device inexistente; suplantación por bearer posible.
- Target (device-scoped): multi-device correcto, revocación I-030, reinstalación con
  recovery firmado, enrollment controlado; identidad de cuenta estable.

## Authorization Boundary

Legacy mezcla niveles: auth.uid (sesión) + zone_id (bearer) + public_key sin prueba de
posesión; **device authorization no existe**. Target separa account/device/message
authorization (firma de cuenta para claims; enrollment y device signing para dispositivos;
RLS de match + sender bound para mensajes). Detalle: §10 del modelo.

## Threat Model

K1–K12 analizadas (§11 del modelo). **Blocking**: K1 (key substitution), K2 (key reuse de
cuenta), K3 (cuenta/device confusion), K4 (unauthorized enrollment), K5 (device
impersonation), K6 (downgrade por regeneración), K7 (legacy bypass), K10 (multi-device
trust confusion), K11 (reinstallation impersonation), K12 (revoked device continued
access). No-blocking: K8 (key orphaning), K9 (identity/key mismatch, ya cubierto por
validaciones de la fundación).

## Architecture Alternatives

A (account owns X25519) · B (device owns X25519) · C (account identity + device crypto) ·
D (derivar ECDH de cuenta / claves server-side). Comparadas por criterios técnicos en
`ADR-0001` («Security Analysis»). A/D rechazadas; B es subconjunto de C (C añade firma y
autorización de cuenta); C elegida.

## Architectural Decision

**ARCHITECTURE C — ACCOUNT IDENTITY + DEVICE CRYPTOGRAPHIC IDENTITY**

- Account: `account_id` + Ed25519 firma (authorization) + `zone_id` (handle). Sin ECDH.
- Device: `device_id` + Ed25519 firma + X25519 cifrado (device encryption, D7) + storage.
- Messaging: identidad del remitente = cuenta (via firma de device); extremo E2EE = device.
- Legacy: X25519 → **import validado** en device_1.
- Ratificado en `docs/architecture/ADR-0001-X25519-OWNERSHIP.md` (estado: DECIDED,
  pendiente ratificación CTO).

## Migration Impact

`docs/migration/PHASE_2_1_2_CRYPTOGRAPHIC_MIGRATION_IMPACT.md`: qué cambia (ownership
decidido; `users.public_key` = heredado), qué permanece (máquina/rollback/validaciones),
qué se congela (semántica de claves, RLS, Z-001, formatos), qué se migra (solo la X25519
legacy → device_1 + metadatos + bind de sesión), qué no (sk_*, pseudo_*, ciphertext, fila
users), qué se preserva (historial E2EE, sesiones mesh, identidad de cuenta) y qué se
invalida (regeneración silenciosa, deleteAll, public_key como canónico).

## Test Requirements

Diseñados (NO implementados): ver `PHASE_2_1_2` §20 — KTEST-01..KTEST-12:

| ID | Test |
| --- | --- |
| KTEST-01 | Account identity consistency (account_id inmutable; fingerprints ACC estables) |
| KTEST-02 | Device identity consistency (device_id, fingerprints DEV, encryption se mantiene) |
| KTEST-03 | Legacy key import (misma seed ⇒ misma pública; 32 bytes; envelope `zidk1:`) |
| KTEST-04 | Key ownership enforcement (device_1 ≠ account; no ECDH de cuenta; KeyPurpose) |
| KTEST-05 | Multi-device enrollment (device_2 pending→active firmado; sin afectar device_1) |
| KTEST-06 | Device revocation (revoke_device ⇒ sesiones derivadas de la X25519 revocada inutilizables) |
| KTEST-07 | Reinstallation (recovery flow; sin extremo falso; identidad de cuenta intacta) |
| KTEST-08 | Key substitution resistance (publicar clave ajena ≠ descifra; MAC falla; fingerprints denuncian) |
| KTEST-09 | E2EE continuity (mensaje legacy descifrado tras import; conversación continua) |
| KTEST-10 | Legacy compatibility (users.public_key = device_1 durante ventana; Z-001 respetado) |
| KTEST-11 | Authorization boundary (account ≠ device ≠ message; claims solo firmados) |
| KTEST-12 | Rollback (MIGRATION_FAILED → LEGACY íntegro; irrevocabilidad tras FINALIZED) |

## Open Questions

### Resolved
- Ownership de X25519 en el target (device) — por esta ADR.
- Relación account/device/messaging — Architecture C.
- Import (Opción A) para continuidad E2EE.
- Trust anchor (cuenta Ed25519 + fingerprints).

### Architecturally determined
- Jerarquía criptográfica (account sujeto / device actor).
- `sk_*` como estado derivado no migrable.
- Consecuencias de migración (impact doc).

### Requires implementation evidence
- Rendimiento/coste real de la red de distribución de claves por device en malla con
  N × M peer (diseño 2.2+).
- Experiencia de re-derivación de sesiones mesh tras la ventana de dual-write.

### Requires CTO decision
- Ratificación de ADR-0001 (ownership device + import de device_1).
- Alcance y secuencia de FASE 2.2 dentro del plan de migración aprobado en 2.1.1.

### Requires backend decision
- Modelo de datos para keys por dispositivo (¿tabla `devices`/`device_keys`? ¿extensión de
  `users`? conservando RLS).
- Política de `users.public_key` tras `FINALIZED` (deprecación ordenada vs freeze permanente).
- `claim_zone_id` con proof-of-possession por firma (reemplazo del bearer), coordinado con
  Z-001 Fase B y los códigos de recuperación.

## Blocking Conditions

| # | Condición | Estado |
| --- | --- | --- |
| M1 | X25519 ownership ambiguo | ✅ resuelto por esta ADR (device) — pendiente ratificación CTO |
| M2 | Account/device boundary ambiguo | ✅ Architecture C |
| M3 | Trust anchor indefinido | ✅ cuenta Ed25519 + fingerprints ACC/DEV |
| M4 | Migration continuity indefinida | ✅ import de device_1 (KTEST-03/09) |
| M5 | Multi-device behavior indefinido | ✅ escenarios A–H + modelo por device |
| M6 | Revocation indefinida | ✅ I-030 `revoke_device` (requiere implementación en 2.2) |
| M7 | Authorization boundary ambiguo | ✅ separación account/device/message |
| M8 | Legacy key semantics desconocidas | ✅ análisis completo (§6 del modelo) |

Resueltas a nivel **arquitectónico**. Ninguna implementada (fase read-only). El único
bloqueo de decisión material pendiente es la **ratificación CTO** de esta ADR.

## GO / NO-GO

**GO para PHASE 2.2** — bajo la definición estricta del encargo:

> GO solo significa que la decisión arquitectónica está suficientemente definida.

NO significa autorización para implementar. La implementación de PHASE 2.2 sigue
sujeta a la autorización CTO (independiente y posterior), que debe ratificar ADR-0001,
el import de device_1 y el alcance/secuencia del plan de migración (PHASE 2.1.1 B1).

## Documentación de soporte

- `docs/architecture/ADR-0001-X25519-OWNERSHIP.md` — la decisión formal.
- `docs/security/X25519_CRYPTOGRAPHIC_IDENTITY_MODEL.md` — modelo criptográfico completo
  (topología, ownership matrix, E2EE, multi-device, threats K1–K12, trust model).
- `docs/migration/PHASE_2_1_2_CRYPTOGRAPHIC_MIGRATION_IMPACT.md` — consecuencias sobre el
  diseño de 2.1.1 (sin modificarlo).
- Documentos PHASE 2.0/2.1/2.1.1 intactos como evidencia histórica.