# ADR — X25519 Ownership & Cryptographic Identity

**ADR-0001** · FASE 2.1.2 · Estado: **DECIDED (accepted — pending CTO ratification)** ·
Fecha: 2026-09-25 · READ-ONLY (no implementa nada).

## Context

PHASE 2.1.1 reportó una ambigüedad crítica: en la app **legacy** coexisten dos lecturas de
la clave X25519 (`users.public_key`), mientras la fundación de identidad autorizada
(FASE 2.1) la modela como identidad **por dispositivo**. Esta ADR resuelve, con evidencia:

- quién es el propietario arquitectónico de las claves X25519;
- cómo se relacionan account identity, device identity y messaging identity;
- qué hacer con la X25519 legacy durante la migración.

## Current State

Topología criptográfica actual (evidencia en código):

```
USER ─▶ ACCOUNT (fila public.users; auth.uid mutable; zone_id "ZONE-XXXXXXXX" bearer)
          ├── public_key  X25519  ──▶ FROZEN en remoto (Z-001, zone_id_service.dart:358-369)
          ├── private_key X25519  ──▶ por instalación; REGENERABLE (ensureAuth, :268-294)
          └── (sin account_id, sin device_id, sin firma, sin fingerprint en producción)
                     ▼
          INSTALACIÓN/DEVICE (sin modelo backend; implícito)
          ├── X25519 keypair (local) ──▶ ECDH con clave pública del peer
          ├── session key sk_<peerZoneId> (p2p_security_service.dart:52-94) — TOFU
          └── almacén seguro: private_key/public_key/sk_*/pseudo_*
                     ▼
          MESSAGING
          ├── ChaCha20-Poly1305 AEAD, clave = ECDH shared (chat_e2ee_service.dart:60-79)
          ├── chat: _sharedSecret en memoria derivado de users.public_key
          │         (chat_screen.dart:194-207)
          ├── mesh: sk_<zoneId> persistido (nearby_service.dart:1022-1044)
          └── ratchet / prekeys / ephemeral: NO EXISTEN (grep lib/ sin resultados)
```

## Problem

La X25519 es tratada simultáneamente como:

1. clave de **cuenta** (`users.public_key` — una fila por usuario;
   `supabase_schema.sql:13-33`), **congelada** por Z-001
   (`zone_id_service.dart:358-369`), usada como identidad E2EE de chats
   (`chat_screen.dart:194-207`) y difundida por radio (`nearby_service.dart:900-901`);
2. clave de **instalación** (cada instalación genera la suya; `ensureAuth` regenera si no
   hay clave local, `zone_id_service.dart:268-294`).

Consecuencia estructural: si el usuario tiene 2 dispositivos, solo el dispositivo cuyo
private seed coincide con la `users.public_key` congelada puede descifrar los chats
server-side; los demás fallan con "Mensaje cifrado con llaves anteriores"
(`chat_e2ee_service.dart:105-109`). No hay manera de enrutar E2EE a un dispositivo
específico: no existe tabla de devices ni distribución de claves por dispositivo en el
backend (`supabase_multi_device_fix.sql` es solo rendimiento: índices/vistas).

## Constraints

- **D1/D2** (PHASE_2_CRYPTO_DECISIONS): Ed25519 firma, X25519 ECDH; prohibida toda
  coerción de rol (`keys.dart:65-82`, `x25519_device_service.dart:59-78`). ⇒ no se puede
  derivar un ECDH de cuenta desde la seed Ed25519 de cuenta.
- **I-004**: ningún material privado fuera del almacén seguro (`models.dart:143-155`).
- **I-013/I-030**: un dispositivo nace `pending` y no se activa implícitamente
  (`keys.dart:104-131`, `identity_registry.dart:191-234`).
- **D4/D7**: la X25519 es identidad de cifrado **del dispositivo**, versionada
  (`models.dart:77-81,105-109`).
- No romper la continuidad E2EE de chats/mesh existentes (los peers conocen la clave
  legacy actual).
- Multi-device debe ser correcto: si Bob lee `public_key` de Alice, debe poder cifrar a
  *un dispositivo* de Alice, no a la "cuenta" opaca.

## Considered Architectures

### Architecture A — Account owns X25519 (reality legacy)

- Una X25519 por cuenta; todos los dispositivos comparten el secreto, o solo uno puede
  descifrar.
- Evidencia de su forma actual: `users.public_key` congelada (`zone_id_service.dart:358-369`).
- Problema: imposible multi-device correcto sin compartir seeds entre dispositivos
  (vulnera I-004 / portar secretos), y regenerarla rompe la continuidad. Contradice la
  fundación (D4/D7).

### Architecture B — Device owns X25519

- Cada dispositivo tiene su X25519 como identidad de cifrado; la cuenta NO posee clave ECDH.
- Correcto para multi-device; la distribución de claves por dispositivo es un servicio
  futuro (keyserver/mentions en perfiles).

### Architecture C — Account identity + device cryptographic identity (RECOMENDADA)

- **Cuenta** = identidad lógica: `account_id` + Ed25519 de firma (autorización/claim) +
  handle `zone_id` + perfil. No posee clave de cifrado estática.
- **Dispositivo** = actor criptográfico: `device_id` + Ed25519 de firma (identity del
  device) + X25519 de cifrado (E2EE) + secreto local + estado de sesión.
- **Mensajería**: identidad del *remitente* de un mensaje = cuenta (verificable por firma
  de dispositivo ligada a la cuenta); extremo E2EE = claves de dispositivo; sesión =
  derivada por par (device-sender, device-recipient).

Esta es EXACTAMENTE la arquitectura ya aprobada e implementada en FASE 2.1
(`keys.dart:71-82`, `models.dart:82-162`, `identity_persistence_models.dart:49-83`),
véase además PHASE_2_DEVICE_MODEL.md y PHASE_2_CRYPTO_DECISIONS.md.

### Architecture D — otra (derivar ECDH de cuenta desde Ed25519, o claves en servidor)

- Derivar ECDH de la seed Ed25519 de cuenta: viola D1/D2 e I-002.
- Claves E2EE en servidor: rompe el modelo extremo-a-extremo. Rechazadas ambas.

## Security Analysis

| Criterio | A (account-X25519) | B (device-X25519) | C (account-id + device-crypto) |
| --- | --- | --- | --- |
| Ataque de superficie | 1 clave comprometida = toda la cuenta | compromiso por device, aislable | por device, aislable + firma para autorizar |
| Revocación de device | imposible (sin modelo device) | posible simbólicamente (D7 versionado) | posible vía `revoke_device` firmado (I-030) |
| Reinstalación | rompe descifrado (clave local regenerada vs remota congelada) | recuperable con respaldo de seeds del device | recuperable con respaldo por device + recovery de cuenta |
| Multi-device | sólo 1 descifrador | correcto (por device) | correcto (por device) |
| Aislamiento de compromiso | total (comparte) | parcial | parcial + fingerprints para identificar device comprometido |
| Alineación D1/D2/I-002 | consistente ECDH | consistente | consistente |

Evidencia de que A falla en práctica: `zone_id_service.dart:268-294` (regenera local) +
`:358-369` (remota congelada) + `chat_screen.dart:194-207` (cifra con la remota) ⇒
dispositivos ≠ el de la seed congelada quedan fuera de los chats.

## E2EE Analysis

Flujo actual Alice→Bob (evidencia):

```
Identity (UID de Alice) ─▶ perfil users.public_key (chat_screen.dart:194-207)
        ─▶ ECDH(alice.private, bob.public) = sharedSecret (chat_e2ee_service.dart:39-45)
        ─▶ AEAD ChaCha20-Poly1305 por mensaje (chat_e2ee_service.dart:60-79)
```

- El extremo criptográfico que *cifra* es la X25519 de instalación de Alice; el extremo que
  *descifra* es la X25519 (frozen) de la cuenta de Bob. Son conceptos distintos mezclados.
- Continuidad: `chat_e2ee_service.dart:105-109` ya reconoce que si cambia la clave del
  otro extremo, el historial deja de descifrarse. En la arquitectura C esto se convierte en
  "cambio de clave de **dispositivo**", con versión D7 y renegociación por sesión.
- Futuro conceptual (NO implementar en esta fase): X3DH + Double Ratchet deben operar
  sobre **identity keys de dispositivo** (Ed25519 de device para autenticar la diffie;
  X25519 de device para los DH ratchets; prekeys y ephemerals por device). La jerarquía de
  identidad de esta ADR es el prerequisito de ese diseño: identity de cuenta para
  autorización, identity de device para autenticación de extremo, claves de sesión para
  tráfico.

## Multi-Device Analysis

Ver `X25519_CRYPTOGRAPHIC_IDENTITY_MODEL.md` §5 (escenarios A–H). Resumen de los casos límite:

- **B (2 devices)**: con C, cada device publica su propia X25519; Bob cifra al device que
  Alice elige/reparto por device; ambos descifran sus mensajes. A rompe B (solo el device
  de la seed congelada descifra).
- **C/D (reinstalación / pérdida)**: en A es irrevocable (sin respaldo de la seed solo una
  instalación descifra). En C hay respaldo de seeds por device + recovery de cuenta por
  firma.
- **E (device posterior)**: en C se materializa como device nuevo (bootstrap, pending→active).
- **F (revocación)**: en A no existe; en C existe `revoked` (I-030) + revocación firmada
  (`device_lifecycle.dart:95-96`, `keys.dart:111-112`).
- **H (device falso)**: en A, conocer el ZONE-ID basta para reclamar la cuenta
  (`supabase_schema.sql:673` claim reescribe users.id). En C, requerir prueba de posesión
  por firma Ed25519 de cuenta cierra el vector.

## Migration Impact

Ver `PHASE_2_1_2_CRYPTOGRAPHIC_MIGRATION_IMPACT.md`. Núcleo:

- La X25519 legacy (`users.public_key` + seeds locales) define quién puede descifrar el
  historial E2EE y con quién Bob tiene sesión establecida (TOFU). **Importarla** (validado)
  como encryption key del device 1 preserva esa capacidad; **regenerarla** la destruye.
- `users.public_key` deja de ser identidad de la cuenta y pasa a ser un valor *heredado*
  de device_1 durante la transición; la arquitectura target no mantiene clave ECDH de cuenta.

## Decision

**Se adopta la Architecture C: la cuenta es la identidad (autorización, firma Ed25519,
ownership de dispositivos); los dispositivos son los actores criptográficos (X25519 de
cifrado por dispositivo, Ed25519 de firma por dispositivo). La X25519 legacy se importa
—una sola vez y tras validación— como identidad de cifrado del dispositivo 1 para
preservar la continuidad E2EE, y queda vetada cualquier regeneración silenciosa de nivel
cuenta.**

Consecuencias formales:

1. La cuenta **no posee** clave ECDH estática. `account identity = firma (Ed25519)`,
   `device identity = firma + cifrado` (X25519 únicamente para ECDH, D2).
2. Toda rotación de clave X25519 es **por dispositivo** y versionada (D7:
   `encryptionKeyVersion`, `models.dart:108-109`).
3. Session keys (`sk_*` legacy) son **estado derivado**, nunca identidad; no se migran
   como material de identidad (se re-derivan).
4. `users.public_key` deja de ser la identidad E2EE remota de la cuenta; durante la
   transición refleja la clave de device_1 (import) y en el target se distribuye claves
   por dispositivo.
5. Trust anchor: **account Ed25519 public key + fingerprints ACC/DEV** (identidad);
   firma de dispositivo (presencia); X25519 de device (cifrado de transporte). El anchor
   NUNCA es un secreto tipo bearer (elimina la dependencia de `zone_id` como prueba).

## Consequences

- La fundación actual ya implementa esta decisión → **ningún cambio de código en
  `lib/identity/`** para adoptarla.
- El trabajo neto está en: (a) bridge de import para device_1 (FASE 2.2), (b) supresión
  definitiva de la regeneración silenciosa de clave de cuenta (`ensureAuth` →
  `zone_id_service.dart:268-294`), (c) distribución de claves por dispositivo y
  recuperación, (d) capa de sesión E2EE futura anclada en estas identidades.
- La continuidad E2EE legacy se preserva **solo** si la import se ejecuta antes de
  cualquier regeneración o fallo de MAC en historial.

## Rejected Alternatives

1. **Architecture A (account owns X25519)** — rechazada por evidencia de fallo multi-device
   y de reinstalación; contradice D4/D7.
2. **Regenerar la X25519 legacy (Option B de §10)** — destruye la continuidad E2EE
   (historial y mesh con peers que conocen la clave anterior) sin ganancia de seguridad
   frente a la import validada; solo es válida como rotación *por dispositivo* posterior a
   un compromiso, nunca como decisión de migración por defecto.
3. **Derivar ECDH de cuenta desde Ed25519** — viola D1/D2 (I-002, `x25519_device_service.dart:59-78`).
4. **Claves E2EE en servidor** — rompe el modelo extremo-a-extremo.

## Open Questions

Ver sección separada en `PHASE_2_1_2_FINAL_DECISION_REPORT.md` §21. Destacan:

- Formato concreto de distribución de claves de dispositivo (2.2+): ¿keyserver en
  `devices`/`device_keys`, o derivación de sesión por profile?
- Esquema de respaldo/recovery de seeds de device (import de seed legacy implica
  política de export cifrado).
- Relación `users.public_key` vs tabla de devices en el backend (decisión backend).

## Implementation Preconditions

1. Ratificación CTO de esta ADR (ownership device-scoped + import de device_1).
2. Cierre de la máquina de estados de migración (diseñada en PHASE 2.1.1) para que la
   import ocurra en `BRIDGED` y nunca tras `FINALIZED`.
3. Tests exigidos en §20 (KTEST-03 import, KTEST-09 continuidad E2EE, KTEST-04 ownership,
   KTEST-05/06 multi-device/revocación) antes de tocar producción.
4. Plan de invalidación de `ensureAuth` y de `zone_id_service.dart:268-294` (regeneración
   silenciosa) — no implementar en esta fase.