# PHASE 2.0.2 — Bootstrap Security Policy v1 (BOOTSTRAP_SECURITY_POLICY)

> **Tipo:** Política formal del bootstrap (primer dispositivo / upgrade legacy) — **NO IMPLEMENTAR**
> **Fecha:** 2026-09-24 · **Estado:** RESOLVED — CTO PROPOSED (pendiente firma humana)
> **Resuelve:** R-004 (C3) · R-005 (C3) · R-013 (C3) · OPEN-003 · OPEN-004
> **Afecta:** `PHASE_2_IDENTITY_ARCHITECTURE.md` §5.A-C · `PHASE_2_DEVICE_MODEL.md` §2 ·
> `PHASE_2_THREAT_MODEL.md` T4 · `PHASE_2_CRYPTO_DECISIONS.md` D3
> **Invariantes:** I-013 (revisado) · I-027 (nuevo) · I-029 (nuevo)

---

## 1. Ámbito

Bootstrap = registro del **primer** dispositivo de una cuenta **sin devices previos**
(necesario para cuentas legacy sin Ed25519 y para cuentas nuevas prescindibles de ancestro
firmado). El alta de un **segundo** dispositivo NO usa bootstrap: usa el flujo D4
(autorización firmada por un device activo).

## 2. Casos formales (FIRST_DEVICE_BOOTSTRAP)

### Caso A — Cuenta fría, sin dispositivos (sin actividad > 30 días)
| Atributo | Valor |
|---|---|
| Quién autoriza | **Nadie** hasta verificación fuera de banda: correo verificado registrado por el titular o contacto con soporte |
| Factor que demuestra autorización | OTP/correo fuera de banda (canal segregado) + sesión (si existe) |
| Qué ocurre si no existe dispositivo | No hay notificación push posible ⇒ pendiente con espera + timeout |
| Evento | `bootstrap_cold_blocked` (audit) |
| Quién recibe la alerta | Soporte / correo registrado (si existiera) |
| Atacante con solo ZONE-ID | Bloqueado: fail-closed (sin puerta abierta) |
| Sesión robada | No suficiente por sí misma: exige el canal fuera de banda |
| Dos enrolls simultáneos | Segundo rechazado (único `bootstrap_attempt` activo por cuenta, I-027) |

### Caso B — Cuenta legacy activa, sin dispositivo seguro (caso normal M1)
| Atributo | Valor |
|---|---|
| Quién autoriza | El enroll pendiente se abre con: **sesión** ligada a la fila `users` (factor 1) + **código de 1 uso** del servidor (factor 2, §3) |
| Factor que demuestra autorización | Session (auth.uid() = users.id) + one-time code + confirmación **firmada** con la Ed25519 recién generada por el cliente |
| Qué ocurre si no existe dispositivo | **No hay push**: el "evento anti-apropiación" se reemplaza por: state `PENDING` (sin derechos) + canal de cancelación (sesión o soporte) + **registro audit** + (si hay correo) aviso de `bootstrap_initiated` |
| Quién recibe la alerta | Correo registrado (si existe); soporte (siempre, audit); los demás devices (**no aplica**: no hay) |
| Atacante con solo ZONE-ID | Rechazado: conocer ZONE-ID no produce sesión (claim eliminado para cuentas con devices; y para legacy el claim queda acotado — LEGACY_ACCESS_POLICY) |
| Sesión robada | La sesión es un **factor**, no la prueba definitiva: *ZONE-ID + sesión básica ≠ ownership* (regla formal). El pending + cancel + audit limitan el daño; se acepta el riesgo residual de sesión robada pre-M1 (documentado en THREAT_MODEL, residual) |
| Dos enrolls simultáneos | Second `bootstrap_account` recibe 409 + audit `bootstrap_concurrent_denied` (I-027) |

### Caso C — Cuenta con dispositivo existente activo
No aplica bootstrap: va por **D4** (authorize_device firmado por el device activo). Si la
cuenta está en `secure`, `bootstrap_account` es **denegado** (solo D4/recovery).

### Caso D — Intento concurrente de enrollment
Ver Casos A/B: **una** fila `bootstrap_attempt` activa por cuenta; la re-solicitud de código
cancela la anterior (rotación, §3 "REISSUE"); el segundo enroll concurrente es rechazado
siempre. Audit + rate-limit por uid/IP.

## 3. Parámetros del código (BOOTSTRAP_SECURITY_POLICY)

| Parámetro | Valor | Justificación |
|---|---|---|
| **TTL** | 10 min | Ventana acotada; suficiente para flujo guiado |
| **ONE_TIME_USE** | Sí | Consumido en `confirm_bootstrap` (single-use) |
| **RATE_LIMIT** | 3 emisiones/15 min por account y por uid/IP | Frena enumeración y abuso |
| **MAX_ATTEMPTS** | 5 confirmaciones fallidas por código → código invalidado + cool-down 15 min + audit `bootstrap_confirm_fail_lock` | Riesgo de fuerza bruta |
| **NONCE** | El código es el factor ocasional (secreto aleatorio); la confirmación usa además `request_challenge` (nonce 32B single-use) firmado en `canonical_payload_v1` | Anti-replay y binding |
| **BINDING** | Código ligado a `account_id` + `bootstrap_attempt` + device (la fila created durante `bootstrap_account`); en confirm: code + payload firmado + sesión aún ligada a `users` | Evita transferencia del código a otra cuenta |
| **ISSUER** | Servidor (`bootstrap_account`, RPC SECURITY DEFINER) | Nunca el cliente |
| **RECIPIENT** | El dispositivo que ejecuta el enroll (pantalla); mostrado brevemente, re-display permitido dentro de TTL con contador | Anti shoulder-surfing parcial |
| **REVOCATION** | `bootstrap_cancel` (soporte o titular con sesión legítima) → estado KILLED + audit | Salida controlada |
| **REISSUE** | Solicitar otro código **invalida el anterior** (rotación del attempt; audit `bootstrap_code_revoked`) | Mata replay de un código interceptado viejo |
| **CONCURRENT_REQUESTS** | 1 activo por cuenta (I-027); segundo → 409 | Serialización |
| **AUDIT_EVENT** | `bootstrap_code_issued` · `bootstrap_confirm_success` · `bootstrap_confirm_fail` · `bootstrap_code_expired` · `bootstrap_code_revoked` · `bootstrap_cancelled` · `bootstrap_concurrent_denied` · `bootstrap_cold_blocked` | Trazabilidad |

**Entropía × TTL × intentos (riesgo real):**
- Código: **8 caracteres** del alfabeto unambiguo de BOOTSTRAP (32 símbolos) = **40 bits**.
  (No se "aumentan los bits" por inercia: 40 bits es suficiente dados los otros controles.)
- Ventana: 10 min, ≤ 5 intentos ⇒ P(fuerza bruta online en ventana) ≈ 5 / 2^40 ≈ 5e-12.
  Combinado con el TTL y el single-use, el código **no es** una credencial persistente y
  expira siempre.
- 12 dígitos (≈40 bits, propuesta previa de IDENTITY §5.A) se sustituye por 8 chars de 32
  símbolos = misma entropía con menos fricción de tipeo (redundancia en display).

## 4. Máquina de estados del primer dispositivo (R-013)

```
                 bootstrap_account          confirm_bootstrap (code + firma)
  (ninguno) ──────────────────▶ PENDING ────────────────────────────────▶ ACTIVE
                                    │   (sesión inválida canal OOB frío)
                                    ├── timeout TTL ─▶ (artefactos GC; vuelve a
                                    │                   legacy sin pérdida — IDENTITY §5.A.3)
                                    ├── MAX_ATTEMPTS ─▶ LOCKED (cool-down 15 min)
                                    └── bootstrap_cancel/cold_block ─▶ KILLED
 ACTIVE ── revoke_device ──▶ REVOKED        ACTIVE ── detección compromiso ──▶ COMPROMISED
```

| Estado | Puede | NO puede |
|---|---|---|
| PENDING | Mostrar estado en UI; firmar su confirmación; ser cancelado | Autorizar otro device · leer/sincronizar mensajes · recibir secretos · enviar mensajes (mesh/cloud) · listarse como activo para peers |
| ACTIVE | Todo lo del device (mensajes, autorización D4, rotación device_keys) | Actuar en nombre de otro device |
| LOCKED / KILLED / REVOKED / COMPROMISED | Nada (operaciones denegadas en RPC por `devices.status`) | Re-entrar por sí mismo |

- **Cuándo se genera la identidad:** al inicio del enroll (client-side): account Ed25519 +
  device Ed25519 + device X25519; las públicas suben en `bootstrap_account`; solo el
  `confirm_bootstrap` activa derechos.
- **Cuándo se permite acceso a datos:** tras ACTIVE.
- **Cuándo puede enviar mensajes:** tras ACTIVE.
- **Cuándo puede autorizar otro dispositivo:** solo si ACTIVE (D4/DR-5).
- **Cuándo recibe secretos:** tras ACTIVE (device_keys públicas en registro; privadas nunca
  salen del cliente).
- **Cómo se revoca:** `revoke_device` (firma de cuenta) o eliminación de cuenta; PENDING se
  revoca con `bootstrap_cancel`.

## 5. Reglas formales

1. **ZONE-ID + sesión básica ≠ ownership.** La sesión es un factor entre otros; ningún estado
   con derechos se alcanza sin `confirm_bootstrap` (código + firma). (I-013, R-013)
2. **Sin push en el primer enroll:** el "evento anti-apropiación" se sustituye por la
   combinación pending/sin-derechos + cancel + audit + (correo opcional). (R-004)
3. **bootstrap_account solo para cuentas sin devices y mode ∈ {legacy, none}.**
4. **Una sola secuencia de enrollment por cuenta** (I-027).
5. Todo intento emite audit event (tabla de auditoría, sección §3).

## 6. Invariantes

- **I-013** (primer enroll no otorga estado activo sin confirmación): **VALID** — ahora la
  máquina de estados §4 es autoridad; refuerza "PENDING no autoriza ni envía".
- **I-027 (NUEVO):** *Única secuencia de bootstrap por cuenta en curso; re-solicitud de
  código cancela la anterior; enrolls concurrentes son rechazados.*
- **I-029 (NUEVO):** *Toda emisión/confirmación/cancelación de bootstrap cumple
  BOOTSTRAP_SECURITY_POLICY (TTL 10 min, single-use, rate-limit 3/15, max 5 intentos,
  reissue-revoca, audit).*

## 7. Estado

> **RESOLVED — CTO PROPOSED** (máquina PENDING→ACTIVE; parámetros §3; casos A-D §2).
> Aprobación final: humano/CTO.