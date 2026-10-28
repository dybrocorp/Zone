# Informe de Implementación — Rediseño Freemium Zone

**Fecha:** 28 de octubre de 2026
**Base:** `main` @ `1bf6e1b75f488e4b5d023fcf9183b8299e704639` (origin/main)
**Alcance:** Fase A (auditoría + diseño) y Fase B (implementación GPS+Red gratis, radar Bluetooth Premium).

> **Revalidación 28/10 14:15:** tras re-emitir el mandato se re-ejecutaron todas las
> compuertas y se cerró el único hueco detectado frente al prompt: recuperación GPS
> al volver la app a primer plano (§4.B) — `didChangeAppLifecycleState` ahora invoca
> `manualRefresh()` inmediato cuando el modo GPS está activo y visible (antes la
> recuperación ocurría solo en el siguiente tick, ≤ 10 s).

---

## A. Baseline y Protección del Repositorio

| Punto | Estado | Evidencia |
|---|---|---|
| Baseline `main` fijada antes de cambios | **PASS** | `1bf6e1b75f488e4b5d023fcf9183b8299e704639`, sincronizada con origin |
| 3 PNG de evidencia del owner intactos | **PASS** | `docs/device_lab/evidence/SERVER_CONFIG_auth_screen.png`, `SERVER_CONFIG_final_state.png`, `WIRING_identity_bootstrap_R01.png` siguen en staging, sin modificar, y **excluidos del commit** (commits con pathspec explícito) |
| Sin operaciones git destructivas | **PASS** | Sin reset/checkout/force push; solo ediciones localizadas y archivos nuevos |
| Sin secretos en commits/salidas | **PASS** | `.env`, keystores y credenciales nunca leídos a output ni incluidos; `git diff --check` limpio (exit 0) |
| Sin APK dentro del repo | **PASS** | El APK vive solo en `build/` (ignorado por git) |

## B. Fase A — Documentos de Diseño

| Documento | Estado |
|---|---|
| `docs/redesign/ZONE_FREEMIUM_ARCHITECTURE.md` | **PASS** |
| `docs/redesign/ZONE_DISCOVERY_PRIVACY.md` | **PASS** |
| `docs/redesign/ZONE_PREMIUM_BILLING.md` | **PASS** |
| `docs/redesign/ZONE_DATA_MIGRATION.md` | **PASS** (incluye política de retención y rollback §5) |
| `docs/redesign/ZONE_ACCEPTANCE_TESTS.md` | **PASS** (matriz L/D/P que guía los tests nuevos) |
| `docs/redesign/ZONE_IMPLEMENTATION_REPORT.md` | **PASS** (este archivo) |

Todos en rutas nuevas `docs/redesign/` — ningún archivo preexistente fue sobrescrito.

## C. Backend (SQL local — NO aplicado en remoto)

| Punto | Estado | Notas |
|---|---|---|
| `supabase_migrations/z214_discovery_geo.sql` | **PASS** (local) | `discovery_preferences` + `discovery_presence` (RLS deny-all), RPCs `set_discovery_preference`, `upsert_discovery_presence` (anti-abuso 15 s, anti-teleport 350 m/s), `discover_nearby_users` (sin coordenadas; distancia redondeada a 10 m), `expire_my_presence`, `auto_cleanup_discovery_presence`; REVOKE explícito a anon/PUBLIC; idempotente (`IF NOT EXISTS` / `DROP POLICY IF EXISTS`) |
| `supabase_migrations/z215_user_entitlements.sql` | **PASS** (local) | `user_entitlements` (RLS sin políticas DML), RPCs `get_my_entitlements` (jamás expone `purchase_token`), `has_bluetooth_premium`; idempotente |
| Guards SQL estáticos | **PASS** | `test/sql_discovery_regression_test.dart` 13/13 |
| **Aplicación en Supabase remoto** | **BLOCKED** | Requiere autorización y ejecución del owner. Mientras tanto, `EntitlementService` usa el puente transicional `users.is_premium` (server-side, no flag local) |

## D. Implementación Cliente — Descubrimiento GPS+Red (Gratis)

| Punto | Estado | Evidencia |
|---|---|---|
| `lib/config/discovery_config.dart` | **PASS** | Radios {250, 500, 1000, 2000} m, default 500; validez de fix (precisión ≤ 150 m, antigüedad ≤ 2 min) |
| `lib/services/location_engine.dart` | **PASS** | `PositionSource`/`PermissionChecker` inyectables (geolocator 14.0.2, FusedLocationProvider = GPS+Red híbrido); errores tipados; mensajes sin coordenadas |
| `lib/services/internet_discovery_provider.dart` | **PASS** | Reescritura limpia; RPCs de descubrimiento/preferencias; sesión inyectable; clamp local de radio |
| `lib/services/discovery_coordinator.dart` | **PASS** | Máquina de estados `idle/acquiringFix/live/hidden/offline/permissionBlocked/serverError/requiresAuth`; sin fallback automático GPS↔BT; tick testeable; reintentos y cancelación en dispose |
| Recuperación al volver a la app | **PASS** | `radar_screen.didChangeAppLifecycleState` → `manualRefresh()` inmediato en `resumed` con GPS activo y visible (revalidación 28/10) |
| UI radar (selector GPS/BT, chips de radio, banner de estado) | **PASS** | `lib/screens/radar_screen.dart` |
| UI ajustes (visibilidad, consentimiento, radio) | **PASS** | `lib/screens/settings_screen.dart` |
| Tests L-01…L-07 + máquina de estados del coordinador | **PASS** | `test/discovery_engine_test.dart` (10), `test/discovery_coordinator_test.dart` (10) |
| **Validación GPS en dispositivo físico** | **NOT VERIFIED** | Sin dispositivos conectados (`adb devices` vacío) |

## E. Implementación Cliente — Premium (Radar Bluetooth)

| Punto | Estado | Evidencia |
|---|---|---|
| `lib/services/entitlement_service.dart` | **PASS** | Fuente de verdad = backend (z215); estados free/verifying/active/grace/canceledRenewal/expired/refundedRevoked/unknown; grace ≤ 24 h fail-closed; caché TTL 5 min + coalescencia; fallback transicional al flag legacy del server |
| `lib/services/play_billing_service.dart` | **PASS** | `in_app_purchase` 3.3.1; fail-closed: ack (`completePurchase`) **solo tras** verificación backend; sin precios inventados (productos desde `ProductDetails` de Play); deep link de gestión de suscripción |
| Gate BT en `NearbyService.startRadar()` | **PASS** | Revalida `loadForce()` → falla con `premiumRequired` antes de tocar la radio; test estático P-12 |
| `lib/screens/premium_screen.dart` | **PASS** | Billing Play real, estados honestos, restore + gestionar suscripción; no hace dispose del singleton de billing |
| `donations_screen.dart` sin compra simulada | **PASS** | `_buyPremium`/`setPremium(true)` eliminados |
| Flag local no concede acceso (P-11) | **PASS** | `setPremium` es marcador inerte; el gate lee el backend |
| Tests P-01…P-12 | **PASS** | `test/entitlement_billing_test.dart` (18) |
| **Compra real en Play (productos, edge function `verify-play-purchase`, RTDN)** | **BLOCKED** | Productos y service account deben crearlos/desplegarlos el owner en Play Console + Supabase |

## F. Compuertas de Verificación (revalidadas 28/10 14:15)

| Compuerta | Estado | Resultado |
|---|---|---|
| `flutter analyze --no-pub` | **PASS** | 0 problemas |
| `flutter test --no-pub` | **PASS** | **472/472** (434 baseline+SQL, +38 nuevos: engine 10, coordinator 10, entitlement/billing 18) |
| `git diff --check` | **PASS** | exit 0 (solo avisos CRLF normales de Windows) |
| `flutter build apk --debug --dart-define-from-file=.env` | **PASS** | exit 0 (94,9 s) |
| Artefacto APK | **PASS** | `build/app/outputs/flutter-apk/app-debug.apk` — 208.958.949 bytes (≈ 199,3 MiB); SHA-256 `7EBA93DC079FB3817B4907B4D89F5791874B7D03F32DB84B16C41D327F5E932C`; paquete `com.dybrocorp.zone`, versión `1.0.4+5` (build **debug**, no release de Play) |
| Instalación en dispositivo físico | **NOT RUN** | `adb devices` sin dispositivos |

## G. Acciones Pendientes del Owner (fuera del alcance del agente)

1. **Aplicar migraciones** `z214_discovery_geo.sql` + `z215_user_entitlements.sql` en Supabase remoto (con autorización del owner; rollback documentado en `ZONE_DATA_MIGRATION.md §5`). Después, el fallback legacy `users.is_premium` se abandona automáticamente.
2. **Play Console:** crear suscripciones `zone_premium_monthly` y `zone_premium_annual`, configurar service account para verificación de compras.
3. **Desplegar edge function** `verify-play-purchase` en Supabase (contrato: body `{productId, purchaseToken, packageName?}` → `{verified: true|false}`).
4. **Activar RTDN** (real-time developer notifications) para renovación/cancelación/reembolso.
5. **Validación en dispositivo físico:** fix GPS real, flujo de compra Play (test track), radar BT con dos dispositivos.

---

# Fase Pre-Beta — Validación Física y Backend (28/10, sesión 2)

## H. Estado Git

| Punto | Estado | Evidencia |
|---|---|---|
| HEAD inicial = reportado | **PASS** | `3c42b13e44e6d75d6b2d94a03bb6b0f4587d1304` en `main`, sincronizado con origin |
| 3 PNG del owner intactos y excluidos | **PASS** | Siguen en staging (`git diff --cached --stat` solo los 3 binarios); ningún commit nuevo los incluye |
| Sin comandos destructivos / force push | **PASS** | Solo lecturas, build y sondeos no mutantes |

## I. Identidad del APK — **PASS**

| Campo | Valor |
|---|---|
| Ruta | `build/app/outputs/flutter-apk/app-debug.apk` |
| Tamaño | 208.958.949 bytes |
| SHA-256 | `7EBA93DC079FB3817B4907B4D89F5791874B7D03F32DB84B16C41D327F5E932C` — **idéntico al informe anterior** (mismo artefacto, sin cambios) |
| Paquete / versión | `com.dybrocorp.zone` v`1.0.4` (versionCode 5), minSdk 24, targetSdk 36 |
| Naturaleza | **Debug**, no release de Play |

**Análisis de tamaño (199,3 MiB) — no es un problema real:**

| Componente | Tamaño | Naturaleza |
|---|---|---|
| `assets/flutter_assets/kernel_blob.bin` | 80,5 MB | Kernel Dart JIT — **solo existe en debug** (release usa AOT `libapp.so`) |
| `assets/flutter_assets/isolate_snapshot_data` | 11,1 MB | Snapshot debug |
| `lib/` × 3 ABIs (arm64 52,7 + x86_64 39,5 + armeabi 32,4) | 124,6 MB | `libflutter.so` debug sin strip, APK gordo con 3 ABIs |
| Raíz (classes.dex debug) + res | ~26 MB | — |

Un build release (AOT + strip + splits por ABI) sería drásticamente menor. No se eliminó ninguna arquitectura ni dependencia.

## J. Dispositivo físico (1 de 2 requeridos) — **PARCIAL / BLOCKED para A↔B**

Dispositivo disponible: tablet Android 15 (API 35), arm64, autorizada (`adb devices` → `device`).

| Prueba | Estado | Evidencia |
|---|---|---|
| Identidad de la instalación | **PASS** | `base.apk` instalado = byte a byte el artefacto validado (SHA-256 idéntico tras `pm path` + pull); `versionCode=5`; instalación original 25/09 preservada, sin borrado de datos |
| Arranque sin crash | **PASS** | Proceso vivo (pid estable), sin `FATAL EXCEPTION` en logcat |
| Render del radar (captura de pantalla) | **PASS** | Selector **GPS activo / Bluetooth 🔒**, banner honesto "Ya no estás visible…", chips de radio {250/500/1000/2000} con 250 m seleccionado, botón Zone Premium en sección separada — sin paywall sobre el radar gratuito y sin peers ficticios |
| Permisos de ubicación | **PASS** | `ACCESS_FINE_LOCATION` y `ACCESS_COARSE_LOCATION` `granted=true` (USER_SET) |
| Modo de ubicación del SO | **PASS** | `location_mode=3` (precisión alta = GPS + proveedores de red, el modo híbrido del diseño) |
| **Descubrimiento A↔B con BT apagado** | **BLOCKED** | Requiere 2 dispositivos y migraciones z214/z215 aplicadas en remoto (ver K). Bluetooth del dispositivo está ON — condición a cambiar en la prueba futura |
| Ocultar/mostrar entre dos usuarios, radio excluyente, pérdida de red | **NOT RUN** | Dependientes del caso A↔B |

## K. Estado real de Supabase remoto — **VERIFICADO con sondeo de solo lectura**

Sondeo REST no mutante (POST a `/rest/v1/rpc/<fn>` con clave anon, sin DDL ni datos):

| RPC | Resultado |
|---|---|
| `get_my_entitlements` (z215) | **HTTP 404 → NO existe en remoto** |
| `get_discovery_preferences` (z214) | **HTTP 404 → NO existe en remoto** |

Conclusión: las migraciones **no están aplicadas** (confirmado por evidencia, no por suposición). El puente transicional `users.is_premium` (server-side) es la ruta activa de Premium, según diseño. **No se aplicó nada en remoto en esta fase.**

## L. Hallazgos de la revisión SQL (z214/z215)

**Fortalezas verificadas:** idempotencia (`IF NOT EXISTS`/`OR REPLACE` + `DROP POLICY IF EXISTS`), `SET search_path TO 'public'` en todas las definer, RLS deny-all en presencia/entitlements, `auth.uid()` con ERRCODE 42501 en cada RPC, REVOKE+GRANT explícitos, clamps server-side (radio 250–2000, limit ≤ 50), anti-abuso 15 s silencioso, anti-teleport 350 m/s, TTL 30 min con CHECK + filtro, respuesta solo con campos autorizados y distancia en grid de 10 m (jamás lat/lng), bloqueos mutuos + shadowban + `discovery_enabled`, anti-enumeración (exige presencia propia vigente), borrado de presencia al revocar consentimiento (en `set_discovery_preference` y en el guard del ping), bloques VERIFY finales, índices bbox+expires, unique token en z215 (idempotencia de escritura), sin políticas DML en z215 (escritura solo service_role).

**Hallazgos menores (documentados, no bloqueantes):**
1. `upsert_discovery_presence` acepta `p_radius_m` pero no lo usa (el radio vive en preferencias). Parámetro inerte por compatibilidad de contrato — inofensivo.
2. `zone_geo_distance_m` es `SECURITY DEFINER` innecesariamente (función pura); el REVOKE lo hace inaccesible a clientes — inofensivo.
3. `discover_nearby_users` no tiene rate-limit propio (el ping sí). Mitigan: exige presencia propia vigente, límite 50 filas, throttle client-side 20 s y TTL 30 min. Riesgo residual de enumeración acotado; opcional añadir límite por ventana en el edge/infra del owner.
4. Referencias de esquema verificadas contra el canon: `users.is_shadowbanned`, `users.avatar_is_public`, `users.public_key`, `blocked_users` existen en migraciones desplegadas (`fix_radar_bilateral.sql`, `z002_profile_visibility.sql`) con el mismo patrón de gating.

**Compatibilidad app ↔ migraciones:** firmas y nombres de parámetros coinciden exactamente con las llamadas de `internet_discovery_provider.dart` (`p_enabled/p_location_consent/p_radius_m`, `p_lat/p_lng/p_accuracy_m/p_source/p_radius_m`, `p_lat/p_lng/p_radius_m/p_limit`) y `entitlement_service.dart` (`get_my_entitlements` → `{entitlements:[...]}`).

## M. Estado real de Google Play Billing — **PASS código / BLOCKED infra**

| Componente | Estado |
|---|---|
| `play_billing_service.dart` | **PASS** — flujo completo: querying/ready/unavailable/purchaseInProgress/pending/succeededUnverified/verificationPending/error; ack solo tras verificación; token desde `serverVerificationData` con fallback JSON local; restore pasa por la misma verificación |
| `entitlement_service.dart` | **PASS** — fuente de verdad backend, grace ≤ 24 h fail-closed, caché TTL 5 min, puente legacy verificado con el sondeo 404 |
| `premium_service.dart` | **PASS** — delega en EntitlementService; `setPremium` marcador inerte (P-11) |
| `premium_screen.dart` | **PASS** — precios solo desde `ProductDetails` reales; sin dispose del singleton |
| Edge function `verify-play-purchase` | **BLOCKED — NO EXISTE** en el repo ni (por ende) desplegada; solo contrato documentado. El cliente fail-closed si ausente |
| Productos en Play Console | **BLOCKED — sin acceso autorizado**; no se inventa estado |
| RTDN | **BLOCKED — sin implementar** (sin tabla ni handler) |
| Compra real | **NOT RUN** — prohibida en esta fase |

## N. Compuertas re-ejecutadas (28/10 14:39)

| Compuerta | Código de salida | Resultado |
|---|---|---|
| `flutter pub get` | 0 | OK (120 paquetes con versiones newer fuera de constraints — informativo) |
| `flutter analyze --no-pub` | 0 | 0 problemas |
| `flutter test --no-pub` | 0 | **472/472 PASS** |
| `git diff --check` | 0 | Limpio |

## O. Criterio de salida de beta

**NO se declara la beta lista.** Pendientes validaciones en sus entornos reales: (1) descubrimiento A↔B con Bluetooth apagado en 2 dispositivos, (2) migraciones z214/z215 aplicadas y verificadas en remoto, (3) autorización Premium verificada end-to-end (productos Play + edge function + RTDN). Todo lo demás (código, tests, APK, privacidad por diseño, gates estáticos) está en estado PASS.
