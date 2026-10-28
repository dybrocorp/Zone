# EXECUTION REPORT — DYBROCORP Master Execution (FASE F + P2P AKE + Transfers) — 2026-10-27 (II)

Informe final de la segunda sesión de ejecución del día. Baseline: `a871b886`
en `main` (ver `BASELINE_FASE_F_2026_10_27.md`). Etiquetas EXCLUSIVAS: PASS /
FAIL / BLOCKED / NOT RUN / NOT VERIFIED (sin upgrades). Nada se sobrescribe de
informes previos.

```text
A Baseline e integridad           : PASS
B Toolchain                       : PASS (2 avisos informativos)
C Login FASE F (R-05/R-13)        : PASS local / backend BLOCKED
D P2P AKE real cableado           : PASS simulado / físico NOT RUN
E Máquina transferencia (10 esc.) : PASS (14/14)
F E2EE verificación (§4)          : PASS (30/30, sin overclaim)
G APK + instalación TB305FU       : apk PASS / instalación NOT VERIFIED
H Commit + push                   : PASS (registro final abajo)
```

## A. Baseline e integridad del repositorio — PASS

- HEAD de arranque: `a871b886ee122c6e6bbe50c3a5e1a57818c2c12e` (`main`).
- El trabajo del usuario (3 PNGs `docs/device_lab/evidence/*` staged) NO fue
  tocado: commits SOLO por pathspec explícito; sin `git add -A`, sin
  `reset --hard`/`clean`/`restore`. Verificados al cierre (3 `A ` intactos).
- Remoto: `origin https://github.com/dybrocorp/Zone.git`.

## B. Toolchain — PASS (informativo)

| Chequeo | Resultado |
|---|---|
| Flutter / Dart | 3.47.2 / 3.13.2 |
| `flutter pub get` | sin cambios |
| `flutter analyze --no-pub` | **No issues found** |
| `flutter doctor -v` | cmdline-tools missing + licenses unknown (previo, informativo: los builds SÍ compilan) |
| ADB | 37.0.1 |

## C. Login FASE F — PASS (local) / BLOCKED (backend)

Sin regresiones: los tests de login (`login_recovery`, `same_account_claim`,
`zone_id` flow) siguen en verde en la suite completa (421/421). **NONE** se
ejecutó contra Supabase (staging/producción) — las 12/14 aceptaciones P0-3
quedan pendientes de staging con autorización del owner (BLOCKED, sin cambios).

## D. P2P — AKE `ZONE-P2P-AKE-1` REAL cableado — PASS (simulado) / físico NOT RUN

**Criterio de «integrado» cumplido con pruebas de transporte simulado
(criptografía real):**

1. **Conexión válida completa el handshake**: `handshake estándar` — ambos
   lados derivan la MISMA clave (32 B) y transcript; roles separados;
   sessionIds distintos (14/14 en `test/p2p_ake_coordinator_test.dart`).
2. **Una conexión INVÁLIDA no puede intercambiar protegidos`:**
   - firma manipulada ⇒ `invalidSignature` (0 derivación, 0 canal);
   - TTL vencido ⇒ `staleHandshake` (sin canal en ambos lados);
   - identidad no lista ⇒ nada se firma ni envía;
   - encuadre malformado ⇒ `frame_too_short` / rechazo del despachador;
   - frame perdido en radio ⇒ settle ASIMÉTRICO fail-closed (el lado sin
      candidatos jamás deriva ni expone canal);
   - cross-transcript (Mallory) ⇒ `decrypt_failed` / `invalid_sender_role`.
3. **Cableado de producción**: autostart al CONNECTED, despachador con orden
   fail-closed (forma → WI-6 → coordinador), `markAkeCompleted` × 1 (gate
   WI-2), material por-conexión (muere al desconectar; NO toca `sk_<zone>`;
   compatibilidad de flota Z-212 intacta — verificado por contrato de fuente
   4/4), identidad desde la fundación.
4. **Conflicto simultáneo**: fork de pista responder con `prior=H(hello_peer)`
   + settlement `min` lexicográfico ⇒ ambas partes convergen a la MISMA clave
   y al MISMO rol (test con canal cruzado funcional).
5. **Canal protegido**: ChaCha20-Poly1305; nonce 12 B (dominio-transcript ‖
   seq u64be); AAD (transcript, seq, rol); RX anti-replay estricto.

**Distinguido siempre (sin upgrades):** TODA la evidencia de D es con
transporte SIMULADO/cripto real (VM). **La demo física entre dos
dispositivos (H-01…H-15) sigue NOT RUN — 0/15**; Z-004 continúa ABIERTO
(`PHASE_E_P2P_AUTH_DESIGN.md` §7.9 actualizada: huecos + expectedZoneId +
ancla OOB documentados).

## E. Máquina de transferencia de datos — PASS (14/14)

`lib/migration/device_transfer_state_machine.dart` + spec
`docs/migration/DEVICE_TRANSFER_STATE_MACHINE.md`. Los 10 escenarios del
master prompt: interrumpida / reintento / concurrente / dispositivo no
autorizado / prueba incorrecta / datos corruptos / device viejo offline /
restauración incompleta / revocación fallida / reanudar tras reinicio — TODOS
PASS. Invariantes clave demostradas: revocación SOLO post-`completed`
(revocación fallida vuelve a `completed` auditable); fallos NUNCA dejan el
device viejo comprometido; chunks idempotentes; restauración incompleta
prohibida (fail-closed); binding de cuenta; JSON round-trip con id estable.

**NOT RUN (explícito):** driver/host que emita eventos en radio, persistencia
local del snapshot, backend de revocación (Z-213 staging BLOCKED), UI A→B.

## F. E2EE — PASS (verificación, sin cambios de protocolo)

- `test/e2ee/` — **30/30 PASS** (KAT v2 13/13 + seguridad 17/17; envelopes
  `zt2:`; error fail-closed ante AEAD inválido).
- Sin overclaim: los docs siguen diciendo la verdad del protocolo — claves
  estáticas-estáticas (NO Forward Secrecy), v1 queda como camino de lectura
  sin downgrade, cierre de FS = paso v3/v4 **BLOCKED** por revisión
  criptográfica externa (`E2EE_RATCHET_ALTERNATIVES.md`, `BUG_REGISTER.md`).
- Ningún cambio de protocolo en esta sesión.

## G. APK + dispositivo físico TB305FU

| Ítem | Resultado |
|---|---|
| `flutter build apk --debug` | **PASS** — `build/app/outputs/flutter-apk/app-debug.apk` |
| Tamaño | 207,962,053 bytes |
| SHA-256 | `9CAD4F45EC6ACDF4CA0B848AFC0C53951F98A822F871969E27C4615953EBD7F1` |
| Package / versión | `com.dybrocorp.zone` 1.0.4+5 |
| Claves | debug build (no release con debug keys) |
| `adb devices` (x3, tras restart) | **ningún dispositivo listado** |
| Instalación en TB305FU + launch | **NOT VERIFIED** — dispositivo no visible por ADB al momento de ejecutar (no hubo upgrade de etiqueta ni retry indefinido) |

El APK queda disponible en `build/app/outputs/flutter-apk/app-debug.apk`
(HASH arriba) para instalar manualmente. Una instalación ulterior y la demo
H-01…H-15 requieren el dispositivo conectado (NOT RUN). **Nunca se afirma**
AKE físico.

## H. Commits y push

Commit único atómico por pathspec explícito (14 archivos — ver lista en el
mensaje), push a `origin/main` sin force. Los 3 PNGs staged del usuario
quedan intactos (no incluidos, no des-stageados). Registro final: ver `git
log`/`git show --stat` de `main` tras el push.

## Estado de bloqueos heredados (sin cambios)

| Bloqueo | Estado |
|---|---|
| Z-212/Z-213 staging exec (§0 sin firmar) | BLOCKED — **NONE aplicado remoto** |
| Demo física H-01…H-15 (AKE radio real) | NOT RUN — 0/15 |
| v3/v4 ratchet (revisión externa) | BLOCKED |
| Keystore release (P0-4) | BLOCKED |
| A2 server rewrite | BLOCKED |
| Ancla OOB / tienda de anclas (Z-004 cierre) | NOT RUN |

---

*Sesión DYBROCORP/OpenCode 2026-10-27 (II). Sin secretos en este informe ni
en logs; sin migraciones remotas (NONE).*
