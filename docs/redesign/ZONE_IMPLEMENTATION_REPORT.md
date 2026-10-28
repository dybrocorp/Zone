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
