# FASE F — Login de usuario existente: decisión de producto

**Fecha:** 2026-10-23
**Estado:** análisis y recomendación. **NO se implementa ninguna alternativa.**
**Actualización 2026-10-27:** dirección de producto = **Alternativa A** (§10);
**se conservan los bloqueos de implementación de §3.2.5 — no se implementa.**
**Decisión pendiente:** producto/CTO sobre variante (A1 shim vs A2 objetivo) y §3.2.5.
**Z-001:** **ABIERTO** (cuarentena activa).
**Beta:** **NO-GO**.

---

## 1. Qué está pasando hoy

### 1.1 El claim está en cuarentena total

- `supabase_schema.sql:743-756`: `claim_zone_id(p_zone_id)` conserva firma y grants
  pero **siempre lanza** `'Reclamo de ZONE-ID deshabilitado temporalmente por
  seguridad (Z-212).'`
- `lib/services/same_account_claim_policy.dart`: `allowSameAccountClaim = false`
  y `ensureAllowed()` lanza `SameAccountClaimBlockedError` **antes** de cualquier
  efecto secundario.
- `lib/screens/login_screen.dart:34-62`: la UI muestra que la migración no está
  disponible y sugiere crear cuenta nueva con "Comenzar".

**Consecuencia:** hoy no existe login de usuario existente. Un usuario que
reinstala o cambia de dispositivo **no puede recuperar su cuenta**.

### 1.2 Por qué no basta con "pedir el ZONE-ID"

El ZONE-ID es un handle público de 8 caracteres (`ZONE-XXXXXXXX`, ~41 bits). Se
muestra en el radar y en la malla. **Conocerlo no prueba posesión.** El diseño
anterior movía `users.id` al `auth.uid()` del solicitante:

```sql
UPDATE users SET id = auth.uid() WHERE zone_id = p_zone_id;
```

Con `users.id` como PK y decenas de FKs `ON UPDATE CASCADE`, esto transfería
perfil, encuentros, matches, mensajes, bloqueos y reportes a cualquier atacante
que conociera el handle. Es **Z-001 (P0)**.

### 1.3 Un defecto adicional a corregir en cualquier alternativa

`lib/services/zone_id_service.dart:146-199` (`_loginWithExistingIDInternal`):

1. Hace `signInAnonymously()`.
2. **Escribe `zone_id` y `uid` locales (líneas 154-158).**
3. Valida el formato (162-165).
4. Llama al RPC (173-176).
5. Persiste el perfil y llama a `ensureAuth()`.

Si el RPC falla, el dispositivo ya sobrescribió su identidad local. Además, el
`catch` de `loginWithExistingID` (129-144) hace `_storage.deleteAll()` ante
errores de descifrado, lo que puede borrar material local legítimo.

**Regla para A y B:** ninguna escritura local de identidad puede ocurrir antes de
que la prueba de posesión y el RPC hayan tenido éxito. El orden actual es un bug
independiente de la alternativa elegida.

---

## 2. Restricciones que ninguna alternativa puede violar

1. El ZONE-ID **no** es credencial por sí mismo.
2. No se mueve `users.id` sin prueba criptográfica de posesión.
3. No se restaura la X25519 v1 ni el historial v1
   (`PHASE_2_RECOVERY_POLICY.md`, I-025, CTO APPROVED).
4. No se pone material privado en el servidor.
5. No se borra ni se reescribe la identidad de un usuario existente como
   "reparación".
6. No se habilita un claim inseguro para "desbloquear" la beta.
7. La decisión debe respetar la regla anti-lockout para usuarios legacy
   (`PHASE_2_LEGACY_ACCESS_POLICY.md`, REGL-1).

---

## 3. Alternativa A — Recuperación con prueba de posesión

**Modelo:** la cuenta es una identidad Ed25519 estable. Un dispositivo nuevo
puede autorizarse ante esa cuenta sin mover la fila de usuario por conocimiento
del handle.

### 3.1 Flujo propuesto

```
Dispositivo nuevo                         Servidor
  │ signInAnonymously() ──────────────────▶ auth.uid() nuevo
  │ request_recovery_challenge(zone_id) ──▶ challenge single-use + TTL 10 min
  │ ◀────────────────────────────────────── challenge
  │ usuario ingresa código de recuperación
  │ deriva recovery_key (HKDF/Argon2id según política)
  │ recover_account(challenge, proof) ────▶ valida hash single-use
  │ ◀────────────────────────────────────── blob envuelto (AES-256-GCM)
  │ descifra blob localmente
  │ restaura account_sk_Ed25519
  │ genera device Ed25519 + X25519 nuevos
  │ register_device(firma de cuenta) ─────▶ verifica firma contra
  │                                          account_identity.identity_public_key
  │ ◀────────────────────────────────────── device ACTIVE
  │ notificación a devices activos
```

Puntos clave:

- El servidor **nunca** ve la clave privada ni el código en claro: solo
  `argon2id(code, salt)` y el blob cifrado.
- `register_device` exige firma Ed25519 de la identidad de cuenta recuperada.
- El dispositivo nuevo **no** hereda la X25519 v1; genera claves nuevas.
- El historial v1 queda ilegible (decisión ya aprobada).
- Los devices activos reciben aviso de "device añadido tras recovery".

### 3.2 Variantes de vinculación (decisión técnica dentro de A)

El esquema actual tiene `users.id UUID REFERENCES auth.users PRIMARY KEY` y FKs
`ON UPDATE CASCADE`. Hay tres formas de integrar A:

| Variante | Qué hace | Ventaja | Coste/riesgo |
|---|---|---|---|
| **A1. Rebind de `users.id`** | Tras prueba de posesión, mueve la fila al nuevo `auth.uid()` | Conserva FKs y queries actuales | Repite el patrón "mover identidad"; invalida sesiones del device viejo; auditoría delicada |
| **A2. `account_id` estable** | Añade columna `account_id`; `users.id` deja de ser la identidad de cuenta | Arquitectura correcta; no mueve filas | Migración grande; RLS y queries deben pasar a `account_id`; riesgo de regresión |
| **A3. Device bridge** | La cuenta sigue en su `auth.uid` original; el device nuevo actúa en su nombre vía RPC firmados | No mueve identidad; multi-device natural | RLS por device; token exchange; más superficie server-side |

**No se elige variante en esta fase.** A1 es la más rápida pero conserva el
riesgo estructural; A2/A3 son más limpias pero son un proyecto de migración.

### 3.2.1 Evidencia del esquema real (2026-10-23)

La comparación anterior era conceptual. Contra el esquema canónico
(`supabase_schema.sql`) y el código actual:

| Hecho verificado | Evidencia | Consecuencia |
|---|---|---|
| `users.id` es la PK y referencia `auth.users` | `supabase_schema.sql:13-14` | La identidad de cuenta y la sesión Auth son la misma columna |
| 9 columnas FK apuntan a `users.id` en 6 tablas | `bt_tokens`, `encounters`, `matches` (2), `messages`, `reports` (2), `blocked_users` (2) | A1 puede preservarlas con `ON UPDATE CASCADE`; A2 debe reapuntarlas |
| 21 políticas RLS y 38 referencias a `auth.uid()` | `grep` sobre `supabase_schema.sql` | A2/A3 no son un parche: hay que reescribir la autorización |
| No existen `account_identity`, `devices`, `device_keys`, `device_challenges`, `device_revocations` ni `recovery_*` | búsqueda sobre `supabase_schema.sql`, `supabase_deploy.sql` y `supabase_migrations/*.sql` | La fundación de identidad es **solo local** (Isar `zone_identity`) |
| `IdentityBootstrap` crea cuenta + `device_1` en `pending` localmente | `lib/identity/identity_bootstrap.dart`, `initial_loading_screen.dart` | No hay sincronización server-side; el servidor no conoce devices |
| `claim_zone_id` sigue en cuarentena | `supabase_schema.sql:743-756`, `same_account_claim_policy.dart` | El login existente está bloqueado, no "a medias" |
| `_loginWithExistingIDInternal` escribe `zone_id`/`uid` antes de validar formato y RPC | `lib/services/zone_id_service.dart:146-199` | Un fallo deja estado local inconsistente; debe corregirse antes de A |
| `loginWithExistingID` puede llamar `_storage.deleteAll()` ante errores de descifrado | `lib/services/zone_id_service.dart:129-143` | Puede borrar identidad/almacén seguro; no es aceptable en A |

### 3.2.2 A1 — Rebind de `users.id` (evaluación real)

**Qué haría falta:** un RPC `recover_account` que, tras consumir el código y
verificar la firma Ed25519, ejecute en una sola transacción:

```sql
UPDATE public.users SET id = :new_auth_uid WHERE id = :old_auth_uid;
```

Las 9 FK con `ON UPDATE CASCADE` siguen el cambio; las 21 políticas RLS siguen
funcionando porque `auth.uid()` del dispositivo nuevo coincide con el nuevo
`users.id`.

**Ventajas reales**

- No reescribe RLS, queries ni FKs.
- Conserva matches, encuentros, perfil y grafo.
- Es la única variante que puede entregarse en una fase corta.

**Riesgos reales**

- **Identidad mutable:** `users.id` deja de ser la identidad de cuenta y pasa a
  ser un binding de sesión. Cualquier bug de rebind mueve todo el grafo social.
- **Sesión vieja:** el `auth.users` antiguo sigue existiendo. El dispositivo
  viejo conserva un JWT válido para el uid antiguo; las RLS fallan cerradas
  porque ya no hay fila en `users`, pero cualquier RPC que solo compruebe
  `auth.uid()` (sin unirse a `users`) podría seguir operando. Hay que auditar
  todos los RPC.
- **Auditoría stale:** `zone_claim_attempts.uid` no es FK; los registros
  históricos apuntan al uid antiguo.
- **Carrera de recovery:** dos dispositivos podrían reclamar a la vez. El RPC
  debe bloquear la fila (`SELECT ... FOR UPDATE`), consumir el código una sola
  vez y rechazar el segundo intento.
- **Revocación de sesiones:** las sesiones anónimas no se listan/revocan sin
  Admin API. La revocación efectiva depende de que no exista fila `users` para
  el uid viejo, no de un `signOut` remoto.

**Veredicto:** A1 es un **shim de beta** aceptable solo si el CTO registra
explícitamente que `users.id` pasa a ser mutable y fija un criterio de salida
hacia A2. No debe presentarse como arquitectura final.

### 3.2.3 A2 — `account_id` estable (evaluación real)

**Qué haría falta:**

1. `account_identity(account_id UUID PK, zone_id TEXT UNIQUE, identity_public_key, ...)`.
2. `devices(auth_uid UUID PK REFERENCES auth.users, account_id, device_id, status, ...)`.
3. `current_account_id()` como función `STABLE` que resuelve `auth.uid() → account_id`
   y devuelve `NULL` si el device no existe o no está activo (fail-closed).
4. Reescribir las 21 políticas y las 38 referencias a `auth.uid()` para usar
   `current_account_id()`.
5. Reapuntar las 9 FKs de `users.id` a `account_identity.account_id` (o mantener
   `users` como perfil y añadir `account_id`).
6. Migrar las queries del cliente que filtran por `user_id`/`sender_id`.

**Ventajas reales**

- `account_id` es inmutable: un recovery no mueve el grafo.
- Multi-device natural: cada device tiene su `auth.uid`, todos resuelven al
  mismo `account_id`.
- Revocación por device sin tocar la cuenta.
- Es la arquitectura que ya describen `PHASE_2_IDENTITY_ARCHITECTURE.md` y
  `PHASE_2_DEVICE_MODEL.md`.

**Riesgos reales**

- Es una migración grande y mecánica, no un parche.
- `current_account_id()` mal implementada puede **sobre-conceder** acceso; debe
  devolver `NULL` ante cualquier duda y tener índice por `auth_uid`.
- Cambiar `messages.sender_id` de device a account altera la semántica de
  autoría y el AAD de Fase G. Es una decisión de modelo, no solo de esquema.
- Requiere staging con datos representativos y pruebas P/N de RLS.

**Veredicto:** A2 es la **arquitectura objetivo**. No es implementable en esta
fase sin resolver las ambigüedades de §3.2.5.

### 3.2.4 A3 — Device bridge (evaluación real)

**Qué haría falta:** la cuenta permanece en su `auth.uid` original; el
dispositivo nuevo tiene su propio `auth.uid` y actúa "en nombre de" la cuenta
mediante RPC firmados.

**Problema estructural:** las políticas RLS de `SELECT` se evalúan contra el
`auth.uid()` del llamante. El uid del dispositivo nuevo **no** es el uid de la
cuenta, así que no puede leer directamente `matches`, `messages`, `encounters`
ni el perfil. Habría que:

- enviar **todas** las lecturas y escrituras por RPC `SECURITY DEFINER` que
  verifiquen una firma de device y luego actúen como la cuenta, o
- emitir un JWT con el uid de la cuenta para el dispositivo nuevo.

La segunda opción exige emisión de JWT con `service_role` o un custom auth hook;
Supabase Auth anónimo no ofrece un endpoint soportado para "crear sesión de un
usuario anónimo existente". La primera convierte cada query en superficie
server-side y duplica la lógica de autorización.

**Veredicto:** A3 tiene **más** superficie que A2, no menos. Se rechaza como
objetivo. Solo tendría sentido si el producto renunciara a RLS directa y
adoptara un backend de autorización propio, que no es el caso.

### 3.2.5 Ambigüedades que bloquean la implementación

Estas decisiones cambian el modelo de seguridad. Mientras no se respondan, **no
se implementa A1 ni A2**:

1. **Generación de `account_id`:** ¿UUID server-side (como dice
   `PHASE_2_DEVICE_MODEL.md`) o derivado de la clave pública Ed25519? Un UUID
   server-side es sustituible en creación; uno derivado de la clave es
   autocertificante pero añade linkabilidad. La política de recovery asume que
   la identidad de cuenta es la Ed25519.
2. **Semántica de `messages.sender_id`:** ¿device o account? Afecta autoría,
   AAD de Fase G y el destino de la FK.
3. **Binding del primer device:** ¿cómo se establece `auth_uid → account_id` en
   el bootstrap, antes de que exista una cadena de firmas? Es el mismo problema
   de primer contacto que Z-004; no puede resolverse con TOFU silencioso.
4. **Backfill legacy:** ¿`account_id = users.id` para filas existentes (preserva
   el grafo sin migración de datos) o un UUID nuevo con tabla de mapeo?
5. **Propagación de revocación:** ¿tabla server-side, lista firmada descargable
   o ambas? ¿Cómo la consulta el P2P offline?

### 3.2.6 Recomendación

| Criterio | A1 | A2 | A3 |
|---|---|---|---|
| Identidad de cuenta inmutable | ❌ | ✅ | ✅ |
| Preserva grafo sin migración de datos | ✅ | ⚠️ (backfill) | ✅ |
| Reescribe RLS | ❌ | ✅ (21 políticas) | ✅ + RPC de lectura |
| Multi-device real | ⚠️ | ✅ | ⚠️ |
| Revocación por device | ⚠️ | ✅ | ✅ |
| Superficie server-side nueva | Media | Media | **Alta** |
| Riesgo de implementación | Medio | Alto (migración) | Muy alto |
| Apto para beta corta | ✅ (shim) | ❌ | ❌ |
| Arquitectura final | ❌ | ✅ | ❌ |

**Recomendación técnica:** adoptar **A2 como objetivo** y **rechazar A1 como
modelo permanente**. Si el CTO necesita desbloquear la beta antes de terminar
A2, A1 solo es aceptable como shim temporal con estas condiciones:

- `users.id` se documenta como binding mutable, no como identidad.
- El rebind es una única transacción con `FOR UPDATE`, consumo single-use y
  auditoría.
- Se añade `account_identity` desde el primer día, aunque las FKs todavía
  apunten a `users.id`.
- Existe un criterio de salida firmado (fecha o hito) hacia A2.
- Las pruebas R-01…R-12 de §3.2.7 se ejecutan en staging antes de abrir el login.

Sin esa decisión, la cuarentena actual se mantiene.


### 3.2.7 Matriz de aceptación (a implementar, no implementada)

Estas pruebas son el contrato mínimo para abrir el login de usuarios existentes.
Ninguna se ha ejecutado todavía; no hay código de recovery.

| ID | Escenario | Preparación | Resultado esperado |
|---|---|---|---|
| R-01 | Recovery legítima | Cuenta con Ed25519 + 12 códigos; dispositivo perdido | Código single-use consumido; blob descifrado; `register_device` firmado; device nuevo `active`; device viejo `revoked`; historial v1 ilegible |
| R-02 | Suplantación solo con ZONE-ID | Atacante conoce el handle, no tiene código | Rechazo; sin sesión, sin rebind, sin fila nueva; rate-limit y auditoría |
| R-03 | Código incorrecto | Handle válido + código erróneo | Rechazo; intento contabilizado; sin oráculo de "código válido pero blob malo" |
| R-04 | Dispositivo perdido sin códigos | Cuenta sin recovery emitido | Sin acceso; ruta de soporte documentada; **sin puerta trasera** |
| R-05 | Almacenamiento corrupto | Isar/secure storage corruptos | Fail-closed; no se regenera identidad; **no** `deleteAll()`; error tipado y recuperación explícita |
| R-06 | Replay de challenge | Challenge capturado y reenviado | Rechazo por single-use/TTL/binding a `account_id`/`zone_id` |
| R-07 | Recovery concurrente | Dos dispositivos compiten | Uno gana; el otro rechazado; sin split-brain; auditoría de ambos |
| R-08 | Claim legacy acotado | `mode=legacy`, sin devices, dentro de ventana | Permitido solo con rate-limit y auditoría; retirado en M5 |
| R-09 | Claim de cuenta segura | `mode=secure` o con devices | Rechazo (REGL-2); no se reabre el claim |
| R-10 | Blob manipulado | Un byte alterado en ciphertext/tag | AES-256-GCM falla; no se deriva clave; no se filtra si el código era correcto |
| R-11 | Blob movido entre cuentas | Blob de A con AAD de B | Falla de autenticación; no se descifra |
| R-12 | Revocación de device | `revoke_device` firmado por cuenta | Device revocado no puede firmar ni registrarse; P2P lo rechaza (`revokedDevice`) |
| R-13 | Orden fail-closed del cliente | Formato inválido / RPC caído | No se escribe `zone_id`/`uid` antes de validar; no queda estado parcial |
| R-14 | Downgrade de recovery | Cliente viejo intenta v1 sin Ed25519 | Rechazo; no se acepta blob sin firma de cuenta |

**Criterio de salida:** R-01…R-14 en verde en staging con dos dispositivos
físicos, más revisión CTO del modelo de amenazas. Hasta entonces, Z-001 sigue
abierto y el login sigue en cuarentena.

### 3.3 Modelo de amenazas

| Amenaza | Mitigación | Residual |
|---|---|---|
| Adivinar el ZONE-ID | Sin códigos de recuperación no hay acceso; rate-limit + auditoría | Enumeración del handle (ya pública) |
| Robo de códigos de recuperación | Single-use, hash Argon2id, TTL, notificación, revocación de devices | Quien tenga código + blob controla la cuenta (igual que un password manager) |
| Replay del challenge | Challenge single-use + TTL + binding a `zone_id`/`account_id` | Reloj/estado server-side |
| MITM en `recover_account` | TLS + blob cifrado; el servidor no puede descifrar | Compromiso del dispositivo |
| Servidor comprometido | Solo hashes + blob cifrado; sin clave privada | Puede denegar servicio o intentar phishing |
| Device perdido | Revocación de `device_keys`; notificación | Mensajes dirigidos a ese device no se recuperan |
| Rotación de identidad maliciosa | `register_device` firmado por cuenta; contador de rotación | Robo de la clave de cuenta = compromiso total |
| Usuario legacy sin códigos | Ventana de upgrade/bounded claim (ver §3.5) | Requiere decisión de transición |

### 3.4 Implicaciones

**Producto**

- Mantiene la promesa "Entrar a mi Zone" en un dispositivo nuevo.
- Mantiene contactos, matches y perfil (no el historial v1).
- Exige educar: "recuperar cuenta ≠ recuperar chats".
- Exige códigos de recuperación y una pantalla de custodia.

**Ingeniería**

- Nuevos RPC: `request_recovery_challenge`, `recover_account`,
  `register_device`, `revoke_device`, `list_devices`.
- Nuevas tablas/columnas: `account_identity`, `device_keys`, `recovery_*`,
  `identity_rotation_counter`, auditoría.
- Cliente: generación/almacenamiento de identidad Ed25519, UI de recovery,
  migración de cuentas legacy, feature flag.
- Tests: recovery, single-use, replay, device revocation, rotación, lockout.

**Operación/soporte**

- Proceso de soporte para códigos perdidos (sin puerta trasera).
- Auditoría de recovery y de devices.
- Comunicación de pérdida de historial v1.

**Plazo/riesgo:** alto. Es un proyecto de varias fases (M1-M5 del plan ya
aprobado), no un parche.

### 3.5 Usuarios legacy

`PHASE_2_LEGACY_ACCESS_POLICY.md` (CTO APPROVED) exige que ningún usuario
`mode=legacy` sin devices quede sin ruta de acceso entre M0 y M5. Eso implica:

- Ventana de transición con **claim acotado** (solo `mode=legacy`, sin devices,
  rate-limit, auditoría), o
- Emisión obligatoria de recovery en el primer arranque post-M1.

La cuarentena total actual es más estricta que esa política porque el puente aún
no existe. A debe definir cómo se migra a los usuarios legacy **sin** reabrir el
claim inseguro para cuentas seguras (REGL-2).

---

## 4. Alternativa B — Nueva identidad por dispositivo (permanente)

**Modelo:** cada instalación/dispositivo es una cuenta nueva. El ZONE-ID no se
reclama nunca. La cuarentena actual se convierte en política permanente.

### 4.1 Flujo

```
Dispositivo nuevo → "Comenzar" → nueva cuenta + nuevo ZONE-ID
Dispositivo viejo → conserva su cuenta mientras exista
Reinstalación → cuenta nueva; la anterior queda inaccesible
```

No hay recovery, no hay `register_device`, no hay multi-device. El botón
"Entrar A Mi Zone" se retira o se muestra como no disponible de forma permanente.

### 4.2 Modelo de amenazas

| Amenaza | Mitigación | Residual |
|---|---|---|
| Account takeover por conocer el ZONE-ID | **Eliminada**: no existe claim | — |
| Robo de códigos de recuperación | **Eliminada**: no hay códigos | — |
| Servidor comprometido | No hay blob de recovery que robar | El servidor sigue viendo metadata |
| Device perdido/robado | El atacante no puede reclamar la cuenta en otro device | La cuenta original queda inaccesible para el dueño |
| Suplantación P2P | Fuera de alcance (Z-004/Fase G) | Sin cambios |
| Usuario que reinstala | — | **Pérdida permanente de cuenta, contactos y matches** |

### 4.3 Implicaciones

**Producto**

- Seguridad máxima con mínimo código nuevo.
- Rompe la promesa de continuidad de cuenta.
- Un cambio de teléfono o una reinstalación = empezar de cero.
- Puede aumentar abandono y soporte ("perdí mi cuenta").

**Ingeniería**

- No requiere criptografía nueva ni RPC de recovery.
- Requiere retirar/ocultar el flujo de login y eliminar la deuda del claim.
- Requiere copy de producto claro y telemetría de reinstalación.
- **No** requiere tocar `users.id` ni las FKs.

**Operación/soporte**

- Menos superficie de ataque y menos casos de recuperación.
- Más casos de "no puedo volver a entrar".

**Plazo/riesgo:** bajo técnicamente, alto en producto/retención.

### 4.4 Conflicto con la política aprobada

`PHASE_2_LEGACY_ACCESS_POLICY.md` REGL-1 prohíbe dejar sin ruta de acceso a un
usuario legacy sin devices entre M0 y M5. B permanente **contradice** esa regla
para usuarios que reinstalan. Para adoptar B hay que:

1. Aceptar explícitamente la excepción a REGL-1, o
2. Mantener una ventana de transición con claim acotado solo para legacy
   (lo que en la práctica es un híbrido B+A para legacy).

Sin esa decisión, B no puede declararse "cerrado" sin violar la política
aprobada.

---

## 5. Comparación

| Criterio | A — Prueba de posesión | B — Nueva identidad |
|---|---|---|
| Account takeover por handle | Cerrado con prueba criptográfica | Cerrado por eliminación |
| Continuidad de cuenta | ✅ | ❌ |
| Contactos/matches tras reinstalar | ✅ (perfil y grafo) | ❌ |
| Historial v1 | ❌ (ya aprobado) | ❌ |
| Multi-device | ✅ (objetivo) | ❌ |
| Usuarios legacy | Requiere transición M1-M5 | Requiere excepción a REGL-1 |
| Criptografía nueva | Ed25519 + HKDF/AES-GCM (ya aprobados) | Ninguna |
| Cambios server | Altos (RPC/tablas/RLS) | Nulos |
| Complejidad cliente | Alta (recovery UI, device keys) | Baja |
| Riesgo de implementación | Alto | Bajo |
| Riesgo de producto | Medio | Alto (pérdida de cuenta) |
| Reversible | Sí, con feature flag | Difícil: usuarios ya perdieron cuentas |
| Cumple políticas aprobadas | ✅ (RECOVERY_POLICY_V1) | ⚠️ (contradice REGL-1) |
| Desbloquea el gate | Solo tras implementar y validar | Solo si producto acepta B |

---

## 6. Recomendación

**A es la única alternativa coherente con la arquitectura y las políticas ya
aprobadas** (`PHASE_2_RECOVERY_POLICY.md` Opción A, `PHASE_2_LEGACY_ACCESS_POLICY.md`).
B es una salida segura **temporal**, pero como política permanente acepta pérdida
de cuenta y contradice la regla anti-lockout.

Recomendación técnica:

1. **Mantener la cuarentena actual (B como estado interim)** mientras A no esté
   implementada y validada. No reabrir el claim.
2. **Adoptar A2 (`account_id` estable) como arquitectura objetivo.** A1 se
   rechaza como modelo permanente; solo se acepta como shim de beta con las
   condiciones de §3.2.6. A3 se rechaza por superficie y por romper las lecturas
   RLS del dispositivo nuevo.
3. **Resolver las cinco ambigüedades de §3.2.5 antes de escribir código.**
   Cambian el modelo de seguridad; no son detalles de implementación.
4. **Corregir primero el orden fail-closed del cliente** (`zone_id_service.dart`):
   validar formato antes de `signInAnonymously`, no escribir `zone_id`/`uid`
   antes del RPC y no llamar `deleteAll()` ante corrupción. Es un prerrequisito
   de A, no parte de la variante.
5. **Definir la transición legacy** antes de escribir código: ventana de claim
   acotado o emisión obligatoria de recovery.
6. **No implementar A ni B en esta fase.** La decisión es de producto/CTO.

Si producto elige B permanente, debe aprobar explícitamente la excepción a
REGL-1 y el copy de pérdida de cuenta; aun así, el gate seguirá NO-GO hasta
retirar el flujo de login y validar la UX.

---

## 7. Decisión solicitada

Responder, como mínimo:

1. **¿ZONE promete continuidad de cuenta entre dispositivos/reinstalaciones?**
   - Sí → Alternativa A.
   - No → Alternativa B (con excepción explícita a REGL-1).
2. **Si A:** ¿se autoriza **A2** como objetivo y **A1 solo como shim temporal**
   con criterio de salida firmado? (Recomendación: sí a A2; A1 condicionado.)
3. **Si A:** resolver §3.2.5:
   - generación de `account_id` (UUID server-side vs derivado de Ed25519),
   - semántica de `messages.sender_id` (device vs account),
   - binding del primer device,
   - backfill legacy (`account_id = users.id` vs UUID nuevo),
   - propagación de revocación (tabla, lista firmada o ambas).
4. **Si A:** ¿se acepta que el historial v1 no se recupera? (Ya está aprobado en
   I-025; se pide confirmación de producto.)
5. **Si A:** ¿cómo se trata a los usuarios legacy sin recovery?
   - Ventana de claim acotado o emisión obligatoria de recovery.
6. **Si B:** ¿se acepta la pérdida permanente de la cuenta al reinstalar y cómo se
   comunica?
7. **Plazo y apetito de riesgo:** ¿A2 se planifica como proyecto M1-M5 o se
   prioriza A1 como shim de beta? ¿Cuál es la fecha/hito de salida de A1?
8. **Presupuesto de staging:** ¿se autoriza ejecutar R-01…R-14 en el proyecto
   staging con dos dispositivos físicos antes de abrir el login?

Hasta que exista esta decisión:

- No se toca `SameAccountClaimPolicy`.
- No se reabre `claim_zone_id`.
- No se implementa recovery ni `register_device`.
- No se modifica la identidad persistida de ningún usuario.

---

## 8. Evidencia y referencias

- `lib/services/same_account_claim_policy.dart` — cuarentena fail-closed.
- `lib/services/zone_id_service.dart:129-199` — flujo actual y orden inseguro.
- `lib/screens/login_screen.dart:27-62` — UX actual.
- `supabase_schema.sql:13-14, 56-133, 719-761` — `users.id`, 9 FKs, 21 políticas,
  38 `auth.uid()` y claim.
- `docs/PHASE_2_RECOVERY_POLICY.md` — Opción A aprobada (sin X25519 v1).
- `docs/PHASE_2_LEGACY_ACCESS_POLICY.md` — REGL-1/REGL-2, claim acotado.
- `docs/PHASE_2_IDENTITY_ARCHITECTURE.md` — modelo cuenta/device objetivo.
- `docs/PHASE_2_DEVICE_MODEL.md` — `account_identity`, `devices`, rotación.
- `docs/CRYPTO_CTO_REVIEW.md` §7 — recovery y blob envuelto.
- `docs/BUG_REGISTER.md` Z-001 — estado abierto.

---

## 9. Impacto en el gate

- **Z-001:** abierto; la cuarentena evita el takeover pero no existe login.
- **Decisión:** A2 recomendada; A1 solo como shim condicionado; A3 rechazada.
- **Implementación:** **no iniciada**; bloqueada por §3.2.5 y por la decisión
  CTO sobre A1/A2.
- **Beta:** **NO-GO** hasta que producto decida, A se implemente y R-01…R-14 se
  validen en staging con dos dispositivos físicos.
- Sin cambios remotos, sin commits, HEAD
  `7f59b776c62cc131fd05dc999e99cbb7804385e8`.

---

## 10. Actualización 2026-10-27 — dirección de producto: Alternativa A

**Origen:** instrucción de producto/CTO (gate de decisión de implementación
local). Producto prefiere **A: continuidad de cuenta mediante prueba de
posesión**, coherente con `PHASE_2_RECOVERY_POLICY.md` (CTO APPROVED, I-025) y
con el anti-lockout REGL-1 de `PHASE_2_LEGACY_ACCESS_POLICY.md`.

### 10.1 Verificación del código real (2026-10-27)

Confirma que el análisis de las secciones 1–3 sigue vigente; nada relevante ha
cambiado:

| Hecho verificado | Evidencia 2026-10-27 |
|---|---|
| Cuarentena activa y fail-closed | `same_account_claim_policy.dart:49` (`allowSameAccountClaim = false`); `ensureAllowed` sin I/O; `zone_id_service.dart:130` la invoca como primera sentencia |
| RPC `claim_zone_id` en cuarentena server-side | `supabase_schema.sql` lanza el error Z-212; guardas estáticas PASS en la suite |
| Orden inseguro del cliente (1.3) vigente | `_loginWithExistingIDInternal` escribe `zone_id`/`uid` locales (`zone_id_service.dart:157-158`) **antes** de validar formato (162) y RPC (173); el `catch` de `loginWithExistingID` puede ejecutar `_storage.deleteAll()` (139) |
| Esquema sin fundación server-side | `account_identity`/`devices`/`device_keys`/`recovery_*`: **0 coincidencias** en `supabase_schema.sql` |
| Fundación de identidad local existente | `lib/identity/` (cuenta Ed25519 + `account_id` UUID + device X25519 en `pending`); solo local (Isar `zone_identity`), sin sincronización server |
| Suite de referencia | **289/289 PASS** + `flutter analyze` limpio (línea base reportada 271/271 del 2026-10-23 más las pruebas añadidas después, incluidas 18 de integración del handshake) |

### 10.2 A1/A2/A3 contra el esquema real (re-verificado)

| # | Hecho | Dato verificado 2026-10-27 | Consecuencia |
|---|---|---|---|
| 1 | `users.id` es PK y referencia `auth.users` | `supabase_schema.sql:13-14` (sin cambios) | A1 re-liga la identidad; A2 exige separar esa identidad dual |
| 2 | FKs a `users.id` | **9** columnas `REFERENCES users` | A1 las preserva con `ON UPDATE CASCADE`; A2 debe reapuntarlas |
| 3 | `ON UPDATE CASCADE` | **10** definiciones en el esquema | igual que (2) |
| 4 | Políticas RLS | **21** `CREATE POLICY` | A2/A3 reescriben la autorización; A1 no la toca |
| 5 | `auth.uid()` | **45** referencias (creció desde 38, auditadas el 2026-10-23, por políticas añadidas después) | la superficie de reescritura de A2/A3 es **mayor** que la auditada |
| 6 | Tablas de identidad server-side | ninguna | tanto A1 como A2 exigen RPC/DDL nuevos |

Conclusión sin cambios: **A2 = arquitectura objetivo (identidad inmutable,
multi-device); A1 = shim condicionado con criterio de salida; A3 = rechazada**
(3.2.4).

### 10.3 Recomendación con consecuencias (paquete listo para decisión CTO)

Con la dirección de producto fijada en A, la decisión restante es única:
**aprobar cuál de estas rutas se ejecuta.**

- **Ruta A2 (objetivo):** `account_id` server-side inmutable + tabla `devices` +
  códigos de recovery + `register_device`/`recover_account` firmados.
  Consecuencias: reescritura de 21 políticas RLS y 45 referencias `auth.uid()`,
  backfill del grafo, staging obligatorio, proyecto de varias fases (M1–M5 del
  plan de migración ya aprobado).
- **Ruta A1 (solo si se autoriza como shim):** rebind transaccional con
  `SELECT … FOR UPDATE` + código single-use + auditoría + `account_identity`
  creada desde el primer día. Consecuencias: `users.id` pasa a ser mutable por
  diseño (riesgo estructural que solo la salida a A2 cierra), revocación de la
  sesión antigua frágil (depende de que no exista fila `users` para el uid
  viejo) y exige fecha/hito de salida firmado. Aceptable **únicamente** como
  desbloqueo temporal con las cinco condiciones de 3.2.6.
- **Pre-requisito común (obligatorio en ambas):** el fix fail-closed de la
  sección 1.3 (formato antes de `signInAnonymously`; ninguna escritura de
  identidad local antes del RPC exitoso; prohibido `deleteAll()` ante
  corrupción — es el escenario R-13) y el bloqueo de carrera del RPC (3.2.2,
  `FOR UPDATE` + consumo single-use).

**Consecuencia de NO decidir (estado actual):** la cuarentena se mantiene, el
login sigue bloqueado y el gate NO-GO. Es una decisión consciente y válida; se
declara explícitamente para que no se confunda con omisión.

### 10.4 Las cinco ambigüedades de 3.2.5 siguen abiertas → SE DETIENE LA IMPLEMENTACIÓN

Las cinco siguen sin resolver y **cada una cambia el modelo de seguridad**.
Por mandato del gate, se detiene la implementación de A antes de escribir
código. Para acelerar la decisión se registra una resolución propuesta por
ítem (fail-safe por omisión); **ninguna está aprobada**:

| # | Ambigüedad | Resolución propuesta (default) | Cuándo podría revisarse |
|---|---|---|---|
| 1 | Generación de `account_id` | **UUID server-side** (`gen_random_uuid()`), no derivado de la clave pública Ed25519 | Si el P2P exige autocertificación (Fase G), re-evaluar |
| 2 | Semántica de `messages.sender_id` | **device** para autoría y RLS granular, con lectura por `account_id` como vista | La Fase G fija el AAD; cambiarlo reescribe autoría e historial |
| 3 | Binding del primer device | Bootstrap de cuenta con anclaje por **fingerprint OOB** + señuelos + evento de auditoría (decisión D3); **no** TOFU silencioso | La UI OOB (Fase G) habilita el flujo real |
| 4 | Backfill legacy | `account_id = users.id` para cuentas existentes (grafo intacto) | Solo si (1) elige UUID nuevo; entonces con tabla de mapeo |
| 5 | Propagación de revocación | **Tabla server-side** (`device_revocations`, acceso RLS + lectura al abrir la app); lista firmada diferida hasta que el P2P offline la necesite | Fase G (revocación en P2P) |

**Qué no se toca mientras tanto:** `SameAccountClaimPolicy`, `claim_zone_id`,
ningún RPC nuevo (`recover_account`/`register_device`/`revoke_device`) y
ninguna escritura de identidad de usuarios. La implementación solo empieza
cuando el CTO registre: variante (A2, o A1 shim con fecha de salida) y
respuesta a cada fila de la tabla anterior.

### 10.5 Pruebas de aceptación de recuperación: preparadas (0 ejecutadas)

Las R-01…R-14 de 3.2.7 siguen siendo la lista única (no se duplican). Se
clasifica su ejecutabilidad para que "preparadas" sea verificable:

**A. Automatizables localmente** (harness Dart puro: RPC sustituidos por
test doubles con firma Ed25519 real, sin mocks criptográficos; colocación en
`test/recovery/`): **R-03** (código incorrecto), **R-05** (almacenamiento
corrupto, orden fail-closed, sin `deleteAll()`), **R-10** (blob manipulado),
**R-11** (blob movido entre cuentas), **R-13** (orden cliente), **R-14**
(downgrade de recovery).

**B. Solo staging / dos dispositivos físicos:** **R-01** (recovery legítima
E2E), **R-02** (suplantación solo con handle, contra RLS/JWT reales),
**R-06/R-07** (replay/concurrencia con estado server), **R-08/R-09** (claim
acotado legacy / cuenta segura), **R-12** (revocación con registro real), y el
criterio de salida de 3.2.7 (14/14 en staging + revisión CTO).

**Estado: 0/14 ejecutadas — no existe código de recovery.**

### 10.6 Impacto en el gate

- Dirección de producto **registrada** (A). Estado del gate: sin cambio,
  **NO-GO**.
- Las cinco ambigüedades de 3.2.5 siguen bloqueando la implementación; las
  secciones 10.3 y 10.4 componen el paquete completo de decisiones que el CTO
  puede firmar en una sola sesión.
- Cambios de esta sesión: solo documentación. Sin commits, sin remoto.
