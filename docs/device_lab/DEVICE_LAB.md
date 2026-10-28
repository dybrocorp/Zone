# ZONE DEVICE LAB — Real Device Testing Environment

> DEVICE LAB / REAL DEVICE VALIDATION · creado 2026-09-25 tras TEST-R01.
> Objetivo: validación en dispositivos físicos (ADB → build → install → launch → logs →
> diagnóstico) sin depender de un dispositivo concreto (multi-device).

## 1. Entorno verificado (Windows 10.0.26200)

| Tool | Ruta / versión | Estado |
| --- | --- | --- |
| ADB | `C:\platform-tools\adb.exe` · 1.0.41 (37.0.1-15733141) | ✔ funciona (vía ruta completa) |
| ADB en PATH | **NO** presente en sesiones PowerShell nuevas | Avasar: usar `& C:\platform-tools\adb.exe` o añadir a PATH de usuario |
| Flutter | 3.47.2 stable · Dart 3.13.2 (C:\flutter) | ✔ |
| Android SDK | `C:\Users\Dybro\AppData\Local\Android\sdk` (36.1.0) | ✔ con avisos: cmdline-tools ausente; licencias desconocidas (`flutter doctor --android-licenses` pendiente) |
| Gradle wrapper | 8.13.0 (AGP 8.11.1, Kotlin 2.1.0, `android.newDsl=false`) | ⚠ Flagman Flutter exige Gradle ≥ 8.14; build OK con `--android-skip-build-dependency-validation` (sin cambiar versiones) |

## 2. Inventario de dispositivos (dinámico, nunca fijo)

```powershell
& C:\platform-tools\adb.exe devices -l
flutter devices
```

| Slot | Serial | Modelo | Android | API | ABI |
| --- | --- | --- | --- | --- | --- |
| DEVICE A (actual) | HA26RCFN | LENOVO TB305FU | 15 | 35 | arm64-v8a |

Regla §16: **no codificar `HA26RCFN`** en el proyecto. Elegir el serial desde
`adb devices -l` en cada ejecución (`DEVICE_A`, `DEVICE_B`, …).

`adb -s <SERIAL>` maquina cualquier comando al dispositivo deseado.

## 3. Datos técnicos por dispositivo (no sensibles)

```powershell
adb -s <SERIAL> shell getprop ro.product.manufacturer
adb -s <SERIAL> shell getprop ro.product.model
adb -s <SERIAL> shell getprop ro.build.version.release
adb -s <SERIAL> shell getprop ro.build.version.sdk
adb -s <SERIAL> shell getprop ro.product.cpu.abi
adb -s <SERIAL> shell wm size
adb -s <SERIAL> shell wm density
adb -s <SERIAL> shell df -h | Select-String -Pattern '/data'
adb -s <SERIAL> shell dumpsys battery | Select-String -Pattern 'level:|status:|health:|technology:'
```

## 4. Build / Install / Launch / Logs (preferencia DEBUG)

```powershell
# Build (debug). Inyecta la configuración real desde .env (incidencia resuelta 2026-09-25:
# sin el flag, EnvConfig queda sin variables y la app muestra "Falta la configuración del servidor").
# El flag --android-skip-build-dependency-validation evita el gate Gradle 8.14 de Flutter mientras
# el wrapper sea 8.13.
flutter build apk --debug --dart-define-from-file=.env --android-skip-build-dependency-validation
# APK resultante
build\app\outputs\flutter-apk\app-debug.apk

# Instalar (in-place, conserva datos). Evitar `flutter install` sin --debug: usa el
# app-release.apk STALE (built 2026-07-05) pre-existente en build/.
flutter install -d <SERIAL> --debug
# o con adb:
& C:\platform-tools\adb.exe -s <SERIAL> install -r build\app\outputs\flutter-apk\app-debug.apk

# Package / activity
#   applicationId = com.dybrocorp.zone  (android\app\build.gradle.kts)
#   MainActivity  = com.dybrocorp.zone/.MainActivity

# Launch
& C:\platform-tools\adb.exe -s <SERIAL> shell am start -n com.dybrocorp.zone/.MainActivity

# Persistencia / ausencia de crash
& C:\platform-tools\adb.exe -s <SERIAL> shell pidof com.dybrocorp.zone
& C:\platform-tools\adb.exe -s <SERIAL> logcat -d -b crash          # vacío = sin crashes

# Logs con filtros
& C:\platform-tools\adb.exe -s <SERIAL> logcat -d --pid=<PID> -v brief
& C:\platform-tools\adb.exe -s <SERIAL> logcat -d | Select-String -Pattern 'FATAL EXCEPTION|AndroidRuntime|SecurityException|MissingPluginException|Isar|Supabase'

# Run con logs en vivo
flutter run -d <SERIAL> --debug

# Evidencia
& C:\platform-tools\adb.exe -s <SERIAL> shell screencap -p /sdcard/<nombre>.png
& C:\platform-tools\adb.exe -s <SERIAL> pull /sdcard/<nombre>.png docs\device_lab\evidence\
```

## 5. Flujo DEVICE LAB (automatizable luego)

```
adb devices -l → device inventory → select device → build APK → install → launch
→ capture logs → run test → collect evidence
```

## 6. TEST-R01 — APPLICATION INSTALL & LAUNCH (2026-09-25)

| Campo | Valor |
| --- | --- |
| Device | LENOVO TB305FU |
| Device ID | HA26RCFN |
| Android / API | 15 / 35 |
| APK | `build\app\outputs\flutter-apk\app-debug.apk` (172.62 MB, debug, árbol actual) |
| Install | `adb install -r` → **Success** |
| Launch | `am start -n com.dybrocorp.zone/.MainActivity` → MainActivity resumed |
| Persistence | PID 6671 vivo a t+12s, t+20s y ~2 min (sin crash-loop) |
| Crash buffer | vacío |
| Resultado | **PASS** |
| Evidencia | `docs/device_lab/evidence/TEST-R01_zone_tb305fu_first_launch.png` y `..._persistence.png` |

### Hallazgos no fatales del primer arranque (diagnóstico, sin corrección)

1. `[FLUTTER_ERROR] Zone mismatch` (dev-check de Flutter): `main.dart:13` usa
   `runZonedGuarded` y la Binding se inicializa en una zona distinta a `runApp`.
   Advertencia de debug no fatal; no crash. — Capa: arranque (UI/main).
2. `Skipped 276 frames!` — jank de cold start en debug (JIT + extracción de assets en
   dispositivo de gama baja). No fatal.
3. `[Startup] Configuración de Supabase ausente` — esperado sin `.env`/`--dart-define`
   (dev fallback verificado por tests). No fatal.
4. `Resource version mismatch` (plataforma) y `HWUI: Unknown dataspace 0` (sistema/ROM):
   ruido del dispositivo, no de Zone.

Ninguno impide R01. **No se modificó ningún código** (regla §10; los arreglos son
decisión de CTO).

## 7. WIRING SLICE — IDENTITY RUNTIME (R02–R05 revalidados en físico, 2026-09-25)

Tras la integración del Identity Bootstrap en `InitialLoadingScreen` (paso 0,
antes del gate de Supabase), la fundación se instancia en el runtime real:

| Resultado | Evidencia |
| --- | --- |
| **R02 PASS** | `[IdentityBootstrap] OK account_id=... device_id=... device_status=pending` en logcat del 1er arranque (CREATE) |
| **R03 PASS** | 2º arranque (LOAD): `account_id` idéntico (`account_created=false`) |
| **R04 PASS** | `device_id` idéntico + `device_status=pending` + `device_fingerprint` presente |
| **R05 PASS** | `fingerprint` 1er == fingerprint 2º (`PV-UF64642AMJ-2G5RXH` / `6JH2FDBTSUAGJCUGWB4G`) |
| **R01 PASS** | MainActivity en foco, PID 9871 estable +100 s, crash buffer vacío, sin FATAL |
| Persistencia | `app_flutter/zone_identity.isar` (1 MB) materializado; almacén seguro poblado |
| Migración | intacta: estado `legacy` (solo lectura, ningún evento ejecutado) |
| Secretos | ninguno en logs (solo account_id, device_id, fingerprints, estados) |

### Hallazgo de entorno (no es regresión de código)

`default.isar` (legacy) ya no está presente tras el update `adb install -r`:
el instalador **recrea el directorio de documentos `app_flutter/`** al actualizar
el APK debug in-place. Ningún código de Zone borra esa base (nada en el cambio
toca `default.isar`); se recreará cuando el flujo legacy corra con backend
configurado. Documentado para el CTO.

Evidencia: `docs/device_lab/evidence/WIRING_R02-R05_identity_physical.txt` y
`WIRING_identity_bootstrap_R01.png`. Detalle del slice: reporte en
`docs/phases/PHASE_2_2_RUNTIME_WIRING_SLICE.md`.

## 8. Notas de entorno pendientes (no auto-corregidas)

- Añadir `C:\platform-tools` al PATH de usuario (o usar ruta completa).
- `flutter doctor --android-licenses` pendiente (licencias SDK).
- `cmdline-tools` del SDK ausente (enf margen para sdkmanager).
- Wrapper Gradle 8.13 < mínimo Flutter 8.14: upgrade a 8.14+ cuando el CTO lo autorice,
  o seguir usando el flag de bypass (cero cambios).