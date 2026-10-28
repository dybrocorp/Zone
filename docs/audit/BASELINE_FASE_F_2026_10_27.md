# BASELINE — Ejecución DYBROCORP 2026-10-27 (FASE F + E2EE + P2P + Migración + APK)

Documento de baseline del arranque de esta sesión. **No reemplaza** informes
previos (`EXECUTION_REPORT_*`, `PHASE_*`): es un inventario del estado REAL al
iniciar, tomado con verificaciones de trabajo (no asumido de reportes anteriores).

## 1. Repositorio

| Chequeo | Resultado |
|---|---|
| `git rev-parse --show-toplevel` | `D:/Proyectos/Zone` |
| Rama | `main` |
| HEAD inicial | `a871b886ee122c6e6bbe50c3a5e1a57818c2c12e` |
| Remote | `origin https://github.com/dybrocorp/Zone.git` (fetch/push) |
| `git status --short` | 3 archivos `A ` (staged por el usuario): `docs/device_lab/evidence/SERVER_CONFIG_auth_screen.png`, `docs/device_lab/evidence/SERVER_CONFIG_final_state.png`, `docs/device_lab/evidence/WIRING_identity_bootstrap_R01.png` |
| `git diff --stat` | vacío (sin modificaciones no staged) |
| `git diff --check` | limpio |

**Decisión de preservación (regla 3 del prompt maestro):** los 3 PNGs staged
quedan tal cual (el usuario los pre-staging); esta sesión commitea SOLO por
pathspec explícito de archivos propios — jamás `git add -A`, jamás
`reset --hard`.

## 2. Toolchain

| Chequeo | Resultado |
|---|---|
| Flutter | 3.47.2 stable (rev d3b14c8769) |
| Dart | 3.13.2 |
| `flutter pub get` | ejecutado; **sin cambios** en `pubspec.yaml`/`pubspec.lock` |
| `flutter doctor` | Flutter OK; Android toolchain: `cmdline-tools` missing + licenses unknown (informativo — los builds previos funcionaron); Windows OK |

## 3. Dispositivo físico

- TB305FU (HA26RCFN) — Android 15, arm64, USB, visible por ADB antes del build
  de esta sesión. Instalación física del APK: se intentará en Gate 8 con el
  APK real generado; si no está autorizado → `NOT VERIFIED` (sin upgrades).

## 4. Estado del código leído para esta sesión (verificado en fuente)

| Componente | Estado documentado al baseline |
|---|---|
| `P2PHandshakeSession` (`ZONE-P2P-AKE-1`) | Completo y testeado aislado; encabezado declara **NOT WIRED** en `NearbyService` |
| `P2pAkeWiring` (WI-2/WI-6) | Gate + rate-limit implementados; `markAkeCompleted` existe sin llamador productivo |
| Frames `ake_hello`/`ake_cert` | Se **despachan** al recibir (registro de progreso); **nada los envía**; `validateAkeFrame` valida un shape reducido incompatible con `P2PAuthHello` |
| `DeviceIdentityBridge` | Implementado con pruebas locales; **sin llamada productiva en `lib/`** |
| `ZoneIdentityBootstrapService` | Conectado al runtime vía `initial_loading_screen.dart` (contexto con account_id/device_id/fingerprints) |
| `IdentityRegistry.loadDeviceKeyMaterial` | Existe; `DeviceKeyMaterial` NO expone los pares crudos (solo sign/sharedSecret) |
| `DeviceMigrationPending` (Z-213 flip) | draft→requested→approved→activated; **sin** máquina de transferencia de datos (§3 del prompt maestro) |
| `MigrationStateMachine` (PHASE 2.2.1) | Es legacy→fundación identidad LOCAL — distinto del §3 solicitado |
| E2EE v2 (`zt2:`) | Implementado y empujado en `a871b88`; docs truthful |
| Login FASE F (R-05/R-13) | Implementado y aprobado; R-xx restantes BLOCKED (backend staging) |

## 5. Decisiones de esta ejecución (derivan de PHASE_J + prompt maestro)

1. **Cableado AKE real** (§5): se implementa `P2pAkeCoordinator` que ejecuta el
   handshake completo sobre el transporte real (frames por `NearbyService`), con
   política de conflicto para hellos simultáneos: cuando ambos lados ya enviaron
   su hello de iniciador, cada lado crea una pista responder (**fork**) con
   sesiones/nonce/efímeros FRESCOS, responde con `prior=H(hello_peer)`; la
   selección determinista entre candidatos es `min` lexicográfico del hash final
   del transcript (ambos lados convergen a la MISMA clave). Confirmado contra la
   API: el responder DEBE aceptar sin prior y el iniciador DEBE pasar el prior.
2. **Anclaje y persistencia de clave**: la clave AKE es por-conexión; NO se
   persiste en los slots `sk_<zone>` legacy (rompería la compatibilidad de flota
   y la semántica de efímeros) — vive en memoria por endpoint y muere con la
   conexión. `identityVerified` sigue siendo `false` en primer contacto (sin
   tienda de anclas aún — OOB pendiente); el bloque Z-212 de `profile_exchange`
   permanece intacto para la flota.
3. **Migración §3**: máquina de transferencia de datos pura y persistible
   (`device_transfer_state_machine.dart`) con los estados pedidos adaptados;
   separación total de transferencia de datos vs. secretos (ninguna clave
   privada viaja — binding por device_certificate_v2); revocación SOLO tras
   `completed` confirmado.
4. **E2EE (§4)**: verificación de que docs vs. implementación siguen alineados
   (`a871b88`); sin cambios de protocolo sin revisión externa (v3/v4 BLOCKED).

## 6. Bloqueos heredados (no resueltos por esta sesión)

- Supabase staging/ejecución remota Z-212/Z-213 §0 — NONE autorizado.
- Demo física de dos dispositivos H-01…H-15 — 0/15 (esta sesión puede verificar
  instalación física de APK, no una sesión AKE con dos teams físicos).
- v3/v4 ratchet, keystore release (P0-4), A2 server rewrite — BLOCKED.

Fecha de generación: 2026-10-27 por sesión de ejecución DYBROCORP/OpenCode.
