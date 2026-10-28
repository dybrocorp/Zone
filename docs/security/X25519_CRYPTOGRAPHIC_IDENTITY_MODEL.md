# X25519 CRYPTOGRAPHIC IDENTITY MODEL

> FASE 2.1.2 · READ-ONLY · Análisis criptográfico de identidad y ownership de claves X25519.
> Complementa y ancla con evidencia la decisión de `ADR-0001-X25519-OWNERSHIP.md`.

## 1. Scope

Modelar, con evidencia, quién posee cada clave, qué representa cada identidad y cómo se
deben relacionar account / device / messaging. NO asumir equivalencias entre `account_id`,
`zone_id`, device identity, X25519 account key, X25519 device key, messaging identity,
session keys y ratchet keys: se demuestran sus diferencias a continuación.

## 2. Current Cryptographic Topology (evidencia)

```
USER
 ▼
ACCOUNT = fila public.users (supabase_schema.sql:13-33)
 ├── id ........... auth UID (auth.uid) — MUTABLE por claim (supabase_schema.sql:673)
 ├── zone_id ...... "ZONE-XXXXXXXX" UNIQUE (supabase_schema.sql:15) — bearer público
 ├── public_key ... X25519 — UNA por cuenta; FROZEN remoto (Z-001, zone_id_service.dart:358-369)
 ├── private_key .. X25519 seed — POR INSTALACIÓN; regenerable (zone_id_service.dart:268-294)
 └── (sin account_id/device_id/firma/fingerprints)
       ▼
DEVICE = instalación (SIN modelo en backend; supabase_multi_device_fix.sql = solo índices)
 ├── X25519 keypair local (chat_e2ee_service.dart:21-24) ──▶ ECDH
 ├── session key sk_<peerZoneId> (p2p_security_service.dart:70-94) — TOFU, persistida
 └── secure storage: private_key/public_key/sk_*/pseudo_* (zone_id_service.dart:23-26,
     p2p_security_service.dart:20-21, nearby_service.dart:279-282)
       ▼
MESSAGING
 ├── chat: sharedSecret en memoria = ECDH(myPriv, peerPub vía users.public_key)
 │         (chat_screen.dart:194-207; chat_e2ee_service.dart:39-45)
 ├── mesh: sk_<zoneId> → AEAD (nearby_service.dart:1022-1044, 1194-1203)
 ├── cifrado: ChaCha20-Poly1305 AEAD (chat_e2ee_service.dart:60-79)
 └── ratchet / prekeys / ephemeral / X3DH: NO EXISTEN (grep sin matches en lib/)
```

## 3. Key Ownership Matrix

| Key / Material | Current Owner | Scope | Lifetime | Storage | Consumer | Security Purpose | Future Owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| X25519 keypair legacy (pub+priv) | instalación (semántica dual) | cuenta (`users.public_key`) + local por instalación | indefinido; remoto congelado, local regenerable | secure storage `private_key`/`public_key` | ChatE2EEService, P2PSecurityService, NearbyService, SupabaseService (radar) | ECDH estático para E2EE y mesh | **device_1 (device encryption, import validado)** |
| `users.public_key` (X25519) | cuenta | fila `users` | indefinido (congelado Z-001) | Supabase | chat_screen (:194-207), radar (:642,674), peers radio | identidad E2EE (hoy) | valor heredado de device_1 durante transición; luego distribution per-device |
| session key `sk_<zoneId>` | instalación | device↔peer(account) | indefinido; borrado por `deleteAllSessionKeys` (:104-115) | secure storage | mesh send/recv | AEAD mesh | estado derivado re-derivable (sesión por par de devices) |
| `_sharedSecret` (chat) | pantalla | device↔peer | ventana del chat; en memoria | memoria | chat_screen | AEAD chat | sesión de transporte por device |
| account Ed25519 (fundación) | cuenta | account | inmutable (v1) | `SecureKeyStore` `zid1.account.*` | `IdentityRegistry.sign` | firma/autorización (identidad) | cuenta (sin cambio) |
| device Ed25519 (fundación) | device | device | versionable | `zid1.device.<id>.deviceIdentity` | `DeviceKeyMaterial.sign` | identity/firma de device + DEV fingerprint | device (sin cambio) |
| device X25519 (fundación) | device | device | versionada (D7, `models.dart:108-109`) | `zid1.device.<id>.deviceEncryption` | `DeviceKeyMaterial.sharedSecretWith` | ECDH de sesión E2EE | device (sin cambio) |
| `pseudo_*` | instalación | radio offline | indefinido | secure storage | nearby | pseudónimo no-identity | no migra (no es identidad) |

Ningún valor ha sido inventado: cada fila cita el código que genera/consumo/almacena el
material.

## 4. Account vs Device Identity

### ACCOUNT — la identidad lógica persistente

| Pregunta | Respuesta (target) | Evidencia |
| --- | --- | --- |
| ¿Posee account_id? | Sí, inmutable (UUID v4) | `models.dart:33-38` |
| ¿Posee profile? | Sí (handle zone_id + perfil) | `AccountIdentity.zoneId`, `models.dart:36-38` |
| ¿Posee authorization? | Sí — por firma Ed25519 de cuenta | `keys.dart:71-82`, `DeviceLifecycle`/`revoke_device` |
| ¿Posee public identity? | Sí — fingerprint ACC (derive de account Ed25519) | `fingerprint_service.dart:102-112` |
| ¿Posee cryptographic identity? | Sí — **firma**, NO cifrado | D1 (Ed25519), `ed25519_identity_service.dart` |

### DEVICE — instancia autorizada

| Pregunta | Respuesta (target) | Evidencia |
| --- | --- | --- |
| ¿Posee device_id? | Sí, inmutable (UUID v4) | `models.dart:96-97` |
| ¿Posee device key? | Sí — Ed25519 de firma + X25519 de cifrado | `models.dart:102-109`, `keys.dart:71-82` |
| ¿Posee fingerprint? | Sí — DEV | `fingerprint_service.dart:119-130` |
| ¿Posee X25519? | **Sí — es SU actor ECDH** | `KeyPurpose.deviceEncryption` |
| ¿Posee signing key? | Sí (device Ed25519) | `KeyPurpose.deviceIdentitySigning` |
| ¿Posee local storage? | Sí — seeds en `SecureKeyStore` | `secure_key_store.dart:130-201` |
| ¿Posee session state? | Sí — sesiones derivadas por (device,device) | target (hoy `sk_*` legacy por zoneId) |

**Conclusión**: account = sujeto de identidad (firma/autorización/ownership de devices);
device = actor criptográfico (firma de presencia + ECDH de transporte).

## 5. Multi-Device Analysis (escenarios A–H)

### Scenario A — Cuenta A con un único Device 1

- Identidad: account_id + zone_id + fingerprints. Device_1 pending→active (I-030).
- Claves: account Ed25519 + device_1 (Ed25519+X25519). Con la import, X25519 del device_1
  = X25519 legacy.
- Authorización/E2EE: sin fricción; equivale al estado actual con un solo extremo.

### Scenario B — Cuenta A con Device 1 y Device 2

- Legacy (evidencia): solo el device cuya seed coincide con `users.public_key` descifra
  chats (`chat_screen.dart:194-207`; `zone_id_service.dart:358-369`); Device 2 generaría
  clave local distinta (`:268-294`) y quedaría fuera (falla MAC, `chat_e2ee_service.dart:105-109`).
- Target: cada device publica su X25519; la sesión se deriva por par de devices; ambos
  descifran los mensajes dirigidos a ellos. La distribución por device es prerequisito de 2.2+.

### Scenario C — Device 1 reinstala la app

- Legacy: `ensureAuth` regenera clave local (`:268-294`) → el device reinstalado ya no
  coincide con la remota congelada → pierde descifrado del historial.
- Target: restauración desde respaldo de seeds del device (recovery) o re-enrolamiento
  firmado; la identidad de cuenta (Ed25519 + fingerprints) NO cambia; la X25519 del device,
  al rotar, se anuncia bajo su versión (D7).

### Scenario D — Device 1 pierde sus claves

- Legacy: irrevocable (sin respaldo; `zone_id_service.dart:76-81` hasta borra todo el
  almacén ante corrupción). Target: recovery por device/cuenta sin pérdida de identidad de
  cuenta; el historial cifrado al device perdido requiere política de respaldo de session
  keys o re-distribución.

### Scenario E — Device 2 se agrega posteriormente

- Legacy: se degenera al caso B (outlier de descifrado).
- Target: bootstrap de device (pending→active con `confirm_bootstrap`, I-030), nuevo par de
  claves de device, fingerprint DEV propio, sin afectar la identidad de cuenta.

### Scenario F — Device 1 queda revocado

- Legacy: NO existe revocación por dispositivo (no hay modelo device; solo account:
  shadowban/delete_own_account, `supabase_schema.sql:162-186`).
- Target: `revoke_device` firmado por la cuenta (I-030; `device_lifecycle.dart:95-96`);
  la sesión derivada de la X25519 revocada deja de ser servida; fingerprints DEV permiten
  identificar trazas.

### Scenario G — Cuenta igual, dispositivo cambia

- Legacy: el cambio de dispositivo rompe descifrado (C/D).
- Target: identidad de cuenta conservada (account_id, fingerprints ACC); nuevo device =
  Scenario E; continuidad E2EE condicionada a respaldo/re-derivación de session keys.

### Scenario H — Atacante registra un dispositivo falso

- Legacy: conocer el `zone_id` (bearer) es suficiente para reclamar la cuenta
  (`supabase_schema.sql:641-700`, claim reescribe `users.id`). También puede publicar
  `public_key` bajo su UID y esperar tráfico cifrado a esa clave.
- Target: el claim requiere prueba de posesión por firma Ed25519 de cuenta (o recovery
  codes); los fingerprints (ACC/DEV) y el device signing cierran la suplantación de
  extremo. Motivo: T4/K5/K11.

## 6. Legacy X25519 (`users.public_key`) Analysis

1. **Quién la genera**: la 1ª instalación, dentro de `_registerInSupabase` vía
   `ChatE2EEService.generateKeyPair()` (`zone_id_service.dart:196-202`).
2. **Quién la consume**: chat (`chat_screen.dart:194-207`), radar/activos
   (`supabase_service.dart:642,674`), radio Nearby (`nearby_service.dart:900-901`), mesh
   (vía `sk_<zoneId>`, `nearby_service.dart:917-931`).
3. **Qué representa**: hoy, la "identidad E2EE de la cuenta" (Z-001,
   `zone_id_service.dart:358-369`).
4. **¿Cuenta o dispositivo?**: la fila es de cuenta (1 por usuario), pero la semilla que
   la origina es de instalación → **respuesta: dual/ambiguo (el conflicto que esta fase resuelve)**.
5. **Protocolos dependientes**: chat E2EE (ECDH+AEAD), mesh (derivación de `sk_*`), sync
   de perfiles (LWW).
6. **¿Puede migrarse?**: sí, como export validado → import en `SecureKeyStore`
   (`zone_id1.device.<id>.deviceEncryption`), verificación `misma seed ⇒ misma pública`
   (procedimiento de `IDENTITY_MIGRATION_BRIDGE.md` §6).
7. **Si se importa**: device_1 conserva la capacidad de descifrar historial y sesiones;
   `users.public_key` no cambia (continúa sirviendo a peers).
8. **Si se regenera**: todo historial cifrado con la clave antigua deja de descifrarse
   (`chat_e2ee_service.dart:105-109`) y los peers que conocen la antigua no pueden
   re-sincronizar sin sesión nueva (meshes TOFU offline).
9. **Si cambia, ¿qué pasa con mensajes existentes?**: quedan cifrados con la clave vieja;
   sin import, son "mensajes cifrados con llaves anteriores" (no recuperables).
10. **Peers que conocen la clave anterior**: con import, no se ven afectados; su session
    key derivada sigue siendo válida para device_1.

## 7. Import vs Regeneration (formal)

| Criterio | OPTION A — Import (validado) | OPTION B — Regenerate |
| --- | --- | --- |
| E2EE continuity | ✅ historial y mesh intactos | ❌ historial ilegible |
| Peer trust | ✅ sesiones TOFU ya derivadas siguen valiendo para device_1 | ❌ peers deben re-derivar con clave nueva (offline: imposible hasta nuevo contacto) |
| Existing ciphertext | ✅ descifrable | ❌ perdido |
| Identity continuity | ✅ device_1 = mismo extremo | ⚠️ mismo account, extremo nuevo |
| Forward secrecy | ⚠️ igual que hoy (una sesión estática); la FS real llega con ratchet, independiente de esta elección | ⚠️ igual |
| Compromise recovery | ⚠️ si la clave legacy estaba comprometida, device_1 rotará con D7 tras sanear (rotación *de device*, no silenciosa) | ✅ clave nueva, pero sin prueba de que la antigua era segura; coste: todo el historial |
| Migration complexity | media (import validado + marca) | baja | 
| Rollback | trivial (no se tocó nada hasta FINALIZED) | irreversible (historial perdido) |
| Multi-device behavior | device_1 conserva; devices nuevos con claves frescas | todos los devices sin historial previo |

**Conclusión por evidencia**: la continuidad de conversaciones y mallas existentes hace
la **import la única opción compatible con E2EE continuity y con rollback no destructivo**;
regenerate solo es admisible como rotación **por dispositivo** posterior a compromiso, o
para cuentas nuevas. Es lo que fija `ADR-0001`.

## 8. Key Continuity — qué significa

Conceptos DISTINTOS (no intercambiables):

- *misma cuenta*: account_id/zone_id perdura — no implica misma clave.
- *mismo dispositivo*: device_id perdura — no implica misma clave.
- *misma clave*: misma seed/X25519 — implica mismo extremo ECDH.
- *misma identidad*: fingerprints/firma de cuenta — perdura aunque rote la X25519 del device.
- *misma sesión*: deriva de un par (device privado × peer pública) — cambia si rota cualquier extremo.
- *misma conversación*: match/messages — perdura independiente de las claves.
- *mismo peer trust*: ancla TOFU (hoy) o fingerprints+firma (target).

La "continuidad criptográfica" que se preserva con la import es **misma clave/device_1**
para no romper *sesiones y ciphertext existentes*. La identidad (cuenta) no depende de esa
clave.

## 9. E2EE Analysis (Alice → Bob)

Cadena actual (evidencia):

```
Identity (UID Alice) ─▶ public_key de Bob (users.public_key / LocalProfile / radio)
        ─▶ ECDH(alice_priv_device, bob_pub_account) = sharedSecret  (chat_e2ee_service.dart:39-45)
        ─▶ AEAD ChaCha20-Poly1305 por mensaje                        (chat_e2ee_service.dart:60-79)
```

Mapeo a la arquitectura target:

```
Identity (ACCOUNT, firma Ed25519 + fingerprints)
   ↓
Public Key (DEVICE de Bob: X25519 de cifrado + Ed25519 de firma para autenticar)
   ↓
Peer (device de Bob identificado por fingerprint DEV + registro device→account)
   ↓
Session (derivada por par (device_alice, device_bob) — target; hoy sk_<zoneId>)
   ↓
Message Encryption (AEAD + ratchet en target; hoy AEAD reutiliza sharedSecret)
```

Relación conceptual con X3DH / Double Ratchet / prekeys / ephemerals (NO implementar aquí):
debe operar en la capa de device: identity keys de dispositivo (Ed25519 de device para
autenticar; X25519 de device como base DH), prekeys y ephemerals emitidos por device, y el
ratchet por conversación entre devices. La jerarquía de esta ADR es el prerequisito.

## 10. Authorization Boundary

| Nivel | Legacy (hoy) | Evidencia | Target |
| --- | --- | --- | --- |
| ACCOUNT autorización | auth.uid (RLS) + `claim_zone_id` bearer (formato+rate-limit) | `supabase_schema.sql:641-700,201-224` | firma Ed25519 de cuenta + recovery codes |
| DEVICE autorización | **NO EXISTE** (cualquier instalación se vuelve device) | sin tabla devices | enrollment firmado por cuenta; device_1 pending→active (I-030) |
| MESSAGE autorización | RLS de match + AEAD MAC | `supabase_service.dart` matches/messages | misma + sender bound a device firmado |

**Confusión detectada**: la validación de identidad (UID/zone_id) ocurre **sin** validación
de ownership del dispositivo; `users.public_key` se acepta sin prueba de posesión (un
atacante puede publicar una clave bajo su UID) y `ensureAuth` regenera claves sin
autorización (`zone_id_service.dart:268-294`). Esto cierra las amenazas K4/K5/K7.

## 11. Threat Model (K1–K12)

| Threat | Attack Surface | Impact | Existing Control | Required Control | Blocking |
| --- | --- | --- | --- | --- | --- |
| K1 Key substitution | public_key publicada bajo UID ajeno (`users.public_key`, `nearby_service.dart:900-901`) | Alto | RLS self-scoped (solo tu row) | firma de posesión + fingerprints en registro | Sí |
| K2 Key reuse | misma X25519 account para todos los devices (congelada, `zone_id_service.dart:358-369`) | Alto | — | claves por device + versionado D7 | Sí |
| K3 Account/device confusion | `users.public_key` tomada como identidad de cuenta E2EE | Alto | — | jerarquía de esta ADR (account=sujeto, device=actor) | Sí |
| K4 Unauthorized device enrollment | reclamar zone_id conocida (`claim_zone_id`) y usar la cuenta | Alto | rate-limit de claims | proof-of-possession por firma de cuenta | Sí |
| K5 Device impersonation | difundir clave pública ajena por radio (TOFU mesh, `nearby_service.dart:917-931`) | Alto | — | fingerprint DEV + firma de presencia | Sí |
| K6 Key downgrade | regeneración silenciosa (`zone_id_service.dart:268-294`) degrada a extremo nuevo no autorizado | Medio | Z-001 preserva la remota | forzar versión/marca; blocked regeneration | Sí |
| K7 Legacy key bypass | cliente legacy sigue usando `users.public_key` congelada tras migración | Medio | — | single-writer + `users.public_key` = device_1 heredado | Sí |
| K8 Key orphaning | seeds de devices huérfanos (historial cifrado sin extremo descifrador) | Medio | — | respaldo de session keys / recovery por device | No |
| K9 Identity/key mismatch | fingerprint de cuenta generado con clave equivocada / par roto | Medio | validación seed↔pública en fundación | verificación de import + fingerprints desde metadatos | No |
| K10 Multi-device trust confusion | Bob confía en una clave de cuenta que solo sirve a un device | Alto | — | distribución por device + fingerprints | Sí |
| K11 Reinstallation impersonation | reinstalar y regenerar clave local (C/D) → extremo falso descifrador | Alto | Z-001 protege remota pero bloquea device nuevo | recovery firmado; fingerprints DEV | Sí |
| K12 Revoked device continued access | device revocado sigue usando la sesión derivada | Alto | (no existe revocación) | `revoke_device` + invalidación de sesiones/device keys | Sí |

## 12. Trust Model — qué confía el peer

- HOY: el peer confía en (a) `zone_id` de un perfil de radio o payload (TOFU) y (b) la
  `public_key` adjunta, sin verificación de que quien la publica la posee ni de que la
  cuenta la autoriza. El anchor es la **server assertion** (fila `users`) y el **contacto
  físico** (mesh) — ambos insuficientes (K1/K5/K11).
- TARGET: el peer confía en la **cadena de identidad**:
  `fingerprint ACC ↔ account Ed25519 pública` (identidad), `fingerprint DEV ↔ device Ed25519`
  (extremo), `X25519 de device` (cifrado), todo autenticado por firma del device y
  ownership por firma de cuenta. El **trust anchor = account Ed25519 public key + fingerprints**.

## 13. Cryptographic Identity Hierarchy (target)

```
ACCOUNT (sujeto de identidad)
 ├── account_id (inmutable)
 ├── ACCOUNT IDENTITY = Ed25519 firma (authorization, claims, recovery)
 ├── handle público zone_id (compat)
 └── DEVICES
      ├── DEVICE 1
      │    ├── device_id
      │    ├── DEVICE IDENTITY = Ed25519 firma (presencia, fingerprints DEV)
      │    └── DEVICE ENCRYPTION = X25519 (ECDH/ratchet) [vía import: = legacy, D7 versionado]
      └── DEVICE 2 (futuro)
           ├── device_id
           ├── DEVICE IDENTITY = Ed25519 firma
           └── DEVICE ENCRYPTION = X25519 (generada por enrollment)
```

Justificación por evidencia: es la única estructura que (a) coincide con FASE 2.0/2.1
aprobada (D1/D2, D4/D7, I-030), (b) hace correcto el multi-device (cada device es extremo
E2EE), (c) permite revocación/reinstalación/recovery sin reasignar la identidad de cuenta,
y (d) sienta la base del ratchet sin violar la separación de roles.

## 14. Conclusion

La propiedad de las claves X25519 se resuelve como:

> **account no posee clave ECDH; cada device posee la suya (X25519 de cifrado) y su firma
> (Ed25519); la identidad de la cuenta es su par de firma Ed25519. La X25519 legacy se
> importa como encryption key del device 1.** — ratificado en `ADR-0001`.