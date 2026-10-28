# ZONE — SERVER CONFIGURATION (procedimiento operativo)

> Incidencia resuelta 2026-09-25: `Falta la configuración del servidor. Reinstala la app.`
> en pantalla real. Causa: el build se generaba **sin** inyectar la configuración.
> Este documento define el mecanismo correcto (sin revelar secretos).

## 1. Variables necesarias

| Variable | Dónde | PRESENT/MISSING |
| --- | --- | --- |
| `SUPABASE_URL` | `.env` raíz del repo | **PRESENT** (25/09/2026) |
| `SUPABASE_ANON_KEY` | `.env` raíz del repo | **PRESENT** (25/09/2026) |

- `.env` está en `.gitignore` (línea 41) y **no está commiteado** — nunca commitearlo.
- Verificar presencia SIN mostrar valores:

```powershell
# PowerShell — imprime solo PRESENT/MISSING, nunca valores
$l = Get-Content .env
foreach ($k in @('SUPABASE_URL','SUPABASE_ANON_KEY')) {
  $line = $l | Where-Object { $_ -match "^\s*$k\s*=" }
  $v = if ($line) { ($line -replace "^\s*$k\s*=\s*","").Trim() } else { '' }
  Write-Output ("$k = " + $(if ($v.Length -gt 0) {'PRESENT'} else {'MISSING'}))
}
```

## 2. Mecanismo de configuración (código real)

`lib/utils/env_config.dart` — orden de prioridad:

1. **Compile-time `--dart-define-from-file=.env`** (producción): los valores se
   embeben en el binario; `.env` NO se empaqueta como asset. Es el mecanismo correcto.
2. Dev fallback `flutter_dotenv` — solo funciona si `.env` fuese asset en
   `pubspec.yaml`. **No** está declarado (solo `assets/`); es por diseño: no
   empaquetar `.env`.

Si ninguna fuente está disponible, `EnvConfig.resolve()` devuelve nulos y la
pantalla de arranque muestra el mensaje de configuración ausente (`lib/screens/
initial_loading_screen.dart:71`) en lugar de crashear (fail-soft intencional).

## 3. Cómo ejecutar / construir

```powershell
# Análisis y tests (siempre)
flutter analyze
$env:ZONE_ISAR_CORE_PATH="$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\isar_flutter_libs-3.1.0+1\windows\isar.dll"
flutter test test

# Build con configuración REAL (corrección de la incidencia):
flutter build apk --debug --dart-define-from-file=.env --android-skip-build-dependency-validation

# (Alternativa run en dispositivo con configuración)
# flutter run -d <SERIAL> --debug --dart-define-from-file=.env
```

## 4. Instalación en dispositivo físico

```powershell
& C:\platform-tools\adb.exe devices -l                # confirmar HA26RCFN
& C:\platform-tools\adb.exe -s HA26RCFN install -r build\app\outputs\flutter-apk\app-debug.apk
& C:\platform-tools\adb.exe -s HA26RCFN shell am force-stop com.dybrocorp.zone
& C:\platform-tools\adb.exe -s HA26RCFN shell monkey -p com.dybrocorp.zone 1
```

## 5. Verificación (sin secretos)

```powershell
& C:\platform-tools\adb.exe -s HA26RCFN logcat -d | Select-String 'Startup|Supabase|IdentityBootstrap|configuration'
```

Esperado tras una instalación correcta:

- `[Startup] Supabase OK (...ms)` y `supabase_flutter: INFO: ***** Supabase init completed *****`
- **Ausente** `[Startup] Configuración de Supabase ausente` y el texto de reinstalación.
- Backend vivo: `[DEBUG] [ZoneIdService] Clave en Supabase preservada (...)` (id truncado; nunca volcar claves).

## 6. Evidencia de la incidencia resuelta (25/09/2026)

- `docs/device_lab/evidence/SERVER_CONFIG_auth_screen.png` — pantalla sin mensaje de error.
- `docs/device_lab/evidence/SERVER_CONFIG_final_state.png` — estado final estable.
- `docs/device_lab/evidence/SERVER_CONFIG_ui.xml` — jerarquía de UI (canvas Flutter activo).
- Logcat: `Supabase init completed` + `Supabase OK`, sin FATAL/errores de red/auth.