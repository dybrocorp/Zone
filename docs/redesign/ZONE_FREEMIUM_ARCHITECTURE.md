# ZONE FREEMIUM — ARQUITECTURA DE REDISEÑO

**Proyecto:** ZONE (DYBROCORP)
**Propósito:** Discovery gratuito GPS+Red · Premium Bluetooth por suscripción verificada
**Etapa:** A (Diseño) — documento de arquitectura objetivo
**Baseline auditado:** `main` @ `1bf6e1b75f488e4b5d023fcf9183b8299e704639`
**Validación de arranque:** `flutter analyze --no-pub` → 0 issues · `flutter test --no-pub` → **421/421 PASS**
**Fecha:** 2026-10-28

---

## 1. Estado previo (inventario auditado, no asumido)

### 1.1 Toolchain y build
| Ítem | Valor |
|---|---|
| Flutter / Dart | 3.47.2 / 3.13.2 (stable) |
| Versión app | `1.0.4+5` (pubspec) |
| Package ID | `com.dybrocorp.zone`, `minSdk=24` (build.gradle.kts) |
| Signing release | fail-fast sin fallback debug (Fase C) — NO como debug |
| Config Supabase | `--dart-define-from-file=.env` (prod) o dotenv dev fallback (`EnvConfig`) |
| Estado Git inicial | 3 PNGs staged por el owner (`docs/device_lab/evidence/*`) — preservados, excluidos del commit |

### 1.2 Componentes existentes que SE REUTILIZAN
| Componente | Rol | Decisión |
|---|---|---|
| `ZoneIdentityBootstrapService` / `identity/*` | Identidad account/device fail-closed (Isar `zone_identity`) | **REUTILIZAR** — intacto |
| `NearbyService` + `discovery_policy.dart` | Radar P2P Nearby Connections (P2P_CLUSTER), tokens efímeros, handshake AKE `ZONE-P2P-AKE-1` | **REUTILIZAR** para modo Bluetooth (premium) — no retirar |
| `EncounterKey` (ZEN-1), `MatchPair`, `match_outbox*` | Encuentros/matches canónicos idempotentes | **REUTILIZAR** — el descubrimiento GPS no altera su modelo |
| `SupabaseService` (chat/matches/messages/realtime) | Backend cliente | **REUTILIZAR** + añadir métodos discovery |
| `ZoneIdService` (claim/login/storage) | Identidad ZONE-ID | **REUTILIZAR** |
| `ConnectivityService` | `isOnline`/`hasRealInternet` (DNS real) + stream | **REUTILIZAR** como señal de modo |
| `PermissionsService` + `DiscoveryPermissions` | Clasificación estructurada de permisos | **REUTILIZAR**; ampliar con ubicación |
| `Crypto/E2EE` (`e2ee_message_crypto`, `chat_e2ee_service`) | Mensajería cifrada | **REUTILIZAR** — sin cambios |
| `RadarConfig` | Constantes radar BT (RSSI, free 15 m / premium 100 m) | **REUTILIZAR** para BT; el radio geográfico obtiene config propia |
| Tono visual (dark #0F172A, acento #00D2FF) | Identidad | **PRESERVAR** |

### 1.3 Componentes que SE MODIFICAN
| Componente | Cambio |
|---|---|
| `PremiumService` | Hoy: flag `SharedPreferences` + `users.is_premium` leído del perfil → **no es prueba de pago**. Pasa a delegar en `EntitlementService` verificado en backend (API compat conservada) |
| `donations_screen.dart` | Contiene compra **simulada** (`_buyPremium` → `setPremium(true)`): se sustituye por `premium_screen` con flujo real de compras (sin precios inventados) |
| `radar_screen.dart` | Se añade selector de modo GPS/BT, radio, visibilidad, estados de ubicación |
| `AndroidManifest.xml` | + `com.android.vending.BILLING` (ubicación/BT ya declarados) |

### 1.4 Huecos detectados (por qué el rediseño es necesario)
1. **No existe geolocalización**: no hay proveedor de ubicación, ni columnas geo, ni RPC geoespacial. `get_active_users_for_radar` devuelve hasta 1000 usuarios activos 24 h **sin filtro de distancia** (radar "global").
2. **Premium no verificado**: `is_premium` es una columna editable por el dueño del perfil y un flag local; la compra es un diálogo simulado. Cualquier gate de bloqueo premium (hoy en `radar_screen` y `nearby_service`) es cosmético, no de seguridad.
3. `z002` ya aplica visibilidad server-side (`v_profile`, stealth, shadowban, bloqueos) — base correcta para extender.

### 1.5 Solicitudes del prompt mapeadas a referencias reales
| Referencia pedida | Estado real |
|---|---|
| `nearby_connections` / `flutter_reactive_ble` | Ambas en pubspec; producción usa Nearby Connections 4.3 (`discovery_policy`); BLE central es legacy/no usada (`requiresBle=false`) |
| `EncounterKey` / ZONE-ID | Implementados y testeados (Z-210, Z-213) |
| Tablas/RPC que revelan usuarios o ubicación | `get_active_users_for_radar`, `v_profile` (sin ubicación hoy) |

---

## 2. Arquitectura objetivo (módulos nuevos)

Nombres adaptados a las convenciones del repo (`lib/services/*`, config tipo singleton, lógica pura testable separada del wire).

```
RadarScreen (UI: modo GPS | BT)
    │
    ├──► DiscoveryCoordinator  (orquesta estado, permisos, conectividad, decisión de proveedor)
    │        ├── LocationEngine        → PositionSource (geolocator en prod; fake en tests)
    │        │     └── Resultado tipado: GeoFix{lat,lng,accuracy,source,age} | GeoFailure{...}
    │        ├── InternetDiscoveryProvider  → RPC ping + discover_nearby_users (Supabase)
    │        └── ConnectivityService / PermissionsService (inyectables, devuelven estado)
    │
    └──► EntitlementService (verificado en backend, caché TTL) 
             └── gate de BluetoothPremiumProvider (NearbyService.existente)
             └── PlayBillingService (in_app_purchase; NUNCA autogrant)
```

### 2.1 `LocationEngine` (nuevo)
- Interfaz `PositionSource` (pura, inyectable) + impl de producción con **`geolocator`** (decisión 3.1).
- Devuelve `GeoFix` (lat/lng, `accuracy_m`, `source: gps|network|hybrid`, `timestamp`) o `GeoFailure` tipado:
  `serviceDisabled · permissionDenied · permissionPermanentlyDenied · locationUnusable · timeout`.
- Exige una corrección con `accuracy ≤ maxAcceptableAccuracyM` y `age ≤ maxFixAge` (config `DiscoveryConfig`); valida el permiso when-in-use antes de pedir; usa precisión aproximada (`coarse`) cuando basta.
- Invariante: **nunca inventa coordenadas ni congela un fix antiguo**.

### 2.2 `InternetDiscoveryProvider` (nuevo)
- `publishPresence(GeoFix, radiusMeters)` → RPC `upsert_discovery_presence` (el servidor valida consentimiento/visibilidad/radio/TTL).
- `discover(radiusMeters)` → RPC `discover_nearby_users(lat,lng,radius,limit)` → filas de `v_profile`-equivalente (id, zone_id, display_name, avatar_url, public_key) + `distance_m` **aproximada por el servidor** (sin coordenadas remotas nunca).
- Autenticado por design (RPC deniega anon); usa la sesión Supabase existente. Sin sesión → `requiresAuth`.

### 2.3 `DiscoveryCoordinator` (nuevo)
- Máquina de estados: `idle · acquiringFix · live · hidden · offline · permissionBlocked · serverError · requiresAuth`.
- Decide proveedor por modo del usuario (GPS|BT), estado de conectividad y permisos; **nunca cae automáticamente BT→GPS ni GPS→BT**.
- Aplica la visibilidad del usuario antes de cualquier `publishPresence` y expone stream para la UI.
- Cancelación limpia al `dispose`/logout/ocultarse.

### 2.4 `EntitlementService` (nuevo, reemplaza la verificación de `PremiumService`)
- Única fuente de "¿puede usar el radar BT?": RPC `get_my_entitlements` (backend).
- Política:
  - `entitled == true` y `not_expired` → acceso.
  - Verificación en línea imposible → **grace window**: se respeta el entitlement verificado previamente hasta `verified_expires_at + GRACE` (24 h), NUNCA tiempo indefinido y nunca si nunca hubo verificación.
  - Estado `pending/unknown/error` → denegado con mensaje específico.
- Caché local (prefs) **solo acelera**: caduca y el gate revalida siempre en operaciones sensibles (arranque de BT).

### 2.5 `PlayBillingService` (nuevo)
- `in_app_purchase` oficial. Productos (placeholders documentados, no precios): `ZONE_PREMIUM_MONTHLY = zone_premium_monthly`, `ZONE_PREMIUM_ANNUAL = zone_premium_annual`.
- Estados expuestos: `querying · ready · unavailable · purchaseInProgress · pending · succeeded(unverified) · verificationPending · error`.
- Invariante: **el éxito de Play NO activa premium**; solo marca "compra registrada — verificación en curso". El entitlement se activa cuando el backend confirma (Edge Function, sección 4.3). Fail-closed.
- `restorePurchases()` usa `restorePurchases` API y posterior consulta de entitlement en backend.

### 2.6 UI (conserva identidad visual)
- `RadarScreen`: selector modo (segmented), chips de radio GPS (de `DiscoveryConfig.radiusOptions`), toggle de visibilidad, banner contextual por `GeoStatus`, lista de usuarios GPS con distancia aproximada, previo lock sheet premium para BT.
- `premium_screen.dart`: planes mensual/anual con datos **reales de Play** (`queryProductDetails`); sin Play configurado muestra estado honesto y botón "Administrar suscripciones" (Play Store). Sin precios quemados en el cliente.
- `settings_screen`: secciones "Descubrimiento" (visibilidad, consentimiento de ubicación, radio por defecto) y "Membresía".

---

## 3. Decisiones técnicas justificadas

| # | Decisión | Justificación |
|---|---|---|
| D1 | **`geolocator`** como LocationEngine de producción | Mantenido activamente, soporta ubicación fused Android (GPS + proveedores de red vía FusedLocationProvider), expone precisión/timestamp, minSdk≥21 (repo: 24). No había ninguna lib de ubicación previa (connectivity_plus es red, no geolocalización). La app consume las lecturas combinadas del SO y valida su calidad — no confunde conectividad Wi-Fi con geolocalización por Wi-Fi |
| D2 | **Sin PostGIS v1; lat/lng + bounding-box + haversine** | Evita depender de verificar la disponibilidad de una extensión en producción (regla §8: no añadir extensiones sin verificar). B-box indexado sobre lat/lng es suficiente para radios ≤ 2 km con límite 50 filas; PostgreSQL ≥ 9.4 compatible. PostGIS queda como mejora opcional documentada (DEC-OPEN-2) |
| D3 | **RPC SECURITY DEFINER con auth.uid() + `search_path` fijado** | Es el patrón del repo (`update_bt_activity`, `delete_own_account`). La tabla de presencia queda deny-all vía RLS sin policies de lectura; todas las lecturas pasan por funciones que aplican gating |
| D4 | **`in_app_purchase` oficial** | Es el plugin sugerido por Google/Flutter para Play Billing; evita wrappers de terceros. La integración del Play Developer API queda en el backend (verificación server-side obligatoria) |
| D5 | **Premium SOLO gatea Bluetooth; GPS discovery es gratis** | Requisito literal del prompt. La distancia geográfica no añade límite premium; el radio se selecciona dentro de un conjunto fijo con clamp server-side |
| D6 | **Nada se retira hasta equivalencia validada** | `NearbyService` queda operativo como proveedor BT premium; el modo GPS es un proveedor paralelo (§11 del prompt) |
| D7 | **Privacidad por expiración: presencia TTL 30 min** | "Ubicación temporal caduca si deja de actualizarse" — server-side, no depende de que el cliente sea honesto |
| D8 | **El backend no devuelve coordenadas ajenas** | `discover_nearby_users` devuelve distancia truncada (grid de 10 m) y campos de perfil autorizados; nunca lat/lng de otros |

---

## 4. Contratos de servicio y backend (resumen; SQL completo en `ZONE_DATA_MIGRATION.md`)

### 4.1 Tablas nuevas (aditivas)
- `discovery_preferences(user_id pk→users.id on delete cascade, discovery_enabled bool default false, location_sharing_enabled bool default false, radius_m int default 500, updated_at timestamptz default now())` — RLS owner-only.
- `discovery_presence(user_id pk→users.id on delete cascade, lat double precision, lng double precision, accuracy_m int, source text check in ('gps','network'), updated_at, expires_at > now() revisado en cada ping)` — **RLS ENABLED sin policies de SELECT (deny-all)**; solo funciones definer acceden.
- `user_entitlements(id uuid pk, user_id →users.id cascade, product text, platform text, purchase_token text, verified bool, starts_at, expires_at, renewal_state text check in ('active','grace','canceled','expired','refunded','unknown'), last_verified_at)` — RLS owner-SELECT de campos no sensibles; escrituras solo service_role/función verificación. Índices: presence(expires_at), presence(lat,lng), entitlements(user_id).

### 4.2 RPC nuevas (autenticadas, anon revocado)
| RPC | Firma | Semántica |
|---|---|---|
| `upsert_discovery_presence(p_lat,p_lng,p_accuracy_m,p_source,p_radius_m)` | void | Verifica auth, prefs (consent+visible), radio clamp server, min intervalo anti-abuso (≥15 s), TTL relative a now()+30 min |
| `discover_nearby_users(p_lat,p_lng,p_radius_m,p_limit)` | TABLE(id, zone_id, display_name, avatar_url, public_key, distance_m int) | Auth + clamp limite≤50 + radius≤2000; filtra: presencia válida, shadows/stealth/bloques, precision mínima; haversine + truncado 10 m |
| `get_my_entitlements()` | jsonb | Auth;/expiración/estado del entitlement del llamador (dueño) |
| `set_discovery_preference(p_enabled,p_location_consent,p_radius_m)` | void | Upsert de prefs (canal único seguro, no requiere escritura directa) |
| `expire_my_presence()` | void | Ocultarse inmediato (borra fila de presencia) |

`get_active_users_for_radar` **no se modifica** (sigue sirviendo a su propósito actual BT-global) y el modo Bluetooth continúa con su flujo vigente.

### 4.3 Verificación de compras (diseño; SU IMPLEMENTACIÓN REMOTA ES BLOQUEO EXTERNO)
- Edge Function `verify-play-purchase` (Supabase) llamada por el cliente tras `purchaseStream` éxito; llama Google Play Publisher API con service account (secretos en env de la función, jamás en el cliente); escribe `user_entitlements` con `verified=true, expires_at=expiry-from-play, renewal_state`.
- Mientras el owner no despliegue key/función, el flujo cliente queda en `verificationPending` — honesto, sin flag mágico.
- RTDN y demás referencias de Play quedan documentadas en `ZONE_PREMIUM_BILLING.md`.

---

## 5. Pruebas
- Fake `PositionSource`, fake adapter de Supabase, fake de conectividad: los tests no hacen red real (misma tradición que `match_outbox_test`).
- RPC SQL: guard estático (`sql_discovery_regression_test`) que verifica en los archivos: RLS ENABLED en las 3 tablas nuevas, REVOKE anon/PUBLIC en las RPC nuevas, no SELECT de coordenadas ajenas en el SQL visible, `search_path` fijo en definer, sin grant de escritura directo a `user_entitlements` a `authenticated`.
- Suite completa debe permanecer ≥ 421 PASS + nuevos.

## 6. Gates de aceptación → `ZONE_ACCEPTANCE_TESTS.md`.

## 7. Bloqueos externos identificados
1. Aplicar la migración (tablas/RPC) en el proyecto Supabase productivo: requiere autorización explícita del owner (regla §3.7).
2. Google Play Console: crear productos de suscripción, licencias de test y service account (para la verificación). Hacerlo sin Play Console real es inválido (regla §9).
3. Validación física de GPS/distancias: requiere dispositivo físico (no disponible ahora).
