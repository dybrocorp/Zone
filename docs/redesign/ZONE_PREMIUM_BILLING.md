# ZONE PREMIUM — FACTURACIÓN (GOOGLE PLAY) Y VERIFICACIÓN

**Etapa:** A (Diseño) · **Fecha:** 2026-10-28

## 1. Alcance premium

**El radar y descubrimiento Bluetooth (Nearby Connections) es la función
Premium.** El descubrimiento GPS+Red permanece gratis. La portada premium se
verifica en el backend (no es creíble ninguna bandera local).

## 2. Estado actual de partida (auditoría)

- `donations_screen.dart` contiene una compra **simulada**:
  `_buyPremium(plan, price)` → diálogo → `PremiumService.setPremium(true)`.
  Es un flag en `SharedPreferences` + una columna `users.is_premium` editable
  por el propietario del perfil. **Esto no puede blindar nada.**
- No existe `in_app_purchase`, ni productos de Play, ni backend de receipts.
- El gate actual es cosmético (UI only) — defecto honesto reconocido.

## 3. Requisitos funcionales (implementados en cliente; verificación externa bloqueada)

| # | Requisito | Cómo se cumple en el código |
|---|---|---|
| R1 | Mostrar planes mensual/anual | `premium_screen` lee `ProductDetails` reales de Play (`queryProductDetails`) — nunca precios quemados en el cliente |
| R2 | Iniciar compra | `buyNonConsumable` (suscripciones → `PurchaseParam`; package v3.x) |
| R3 | Estados pendiente/completado/cancelado/fallo | `PurchaseStatus` mapeado: `pending → purchaseInProgress → purchased → verificationPending`, `error/canceled` con mensajes exactos |
| R4 | Restaurar compras | botón `restorePurchases()` + reconsulta de entitlement en backend |
| R5 | Expiración/renovación/refund/revocación | tabla `user_entitlements` (`renewal_state`) actualizada por backend (notificación RTDN / Developer API) |
| R6 | Explicar denegaciones | cada estado del `EntitlementService` tiene mensaje concreto (sin acceso / verificando / error temporal / expirado) |
| R7 | Gestionar suscripción | deep link Play Store (`url_launcher` en `https://play.google.com/store/account/subscriptions`) |

## 4. Arquitectura de compra (secure)

```
[cliente] in_app_purchase → compra OK (PurchaseStatus.purchased)
     └─ llama Edge Function `verify-play-purchase` con package/purchaseToken
[backend] Edge Function (service account en secrets de Supabase)
     └─ Google Play Developer API: purchases.subscriptionsv2.get
        (deberá ser creado por el owner; requisito Play Console)
     └─ escribe user_entitlements (verified, expires_at, renewal_state)
[cliente] EntitlementService → get_my_entitlements() → gate BT
```

Reglas no negociables:
1. **El cliente nunca declara compra verificada** (`PurchaseStatus.purchased`
   ≠ entitlement). Solo es "pendiente de verificación".
2. Sin backend verificador operativo → flujo queda `verificationPending` (UI
   honesta), el radar BT sigue bloqueado.
3. Fallos de red en la verificación **no conceden acceso permanente**: tras un
   entitlement verificado previamente se aplica grace ≤ 24 h, alineado con
   `expires_at` (nunca tiempo ilimitado, nunca si no hubo verificación previa).
   Menos de 24 h a expirar → sin grace (fail-closed).

## 5. Matriz de estados (UI + gate)

| Estado | Significado | Acción visible | BT gate |
|---|---|---|---|
| `free` | Sin entitlement | botón "Hacerme Premium" | BLOQUEADO |
| `verifying` | compra registrada, backend no confirmó | "Verificando tu compra…" | BLOQUEADO |
| `active` | entitlement verificado, `expires_at` futura | "Eres Premium (hasta X)" | PERMITIDO |
| `grace` | verificación imposible temporalmente, dentro de grace | aviso discreto | PERMITIDO |
| `canceledRenewal` | canceló renovación, sigue activo hasta expirar | aviso con fecha | PERMITIDO |
| `expired` | pasado expiró, sin renovación | "Caducó hace Y" | BLOQUEADO |
| `refundedRevoked` | Play revocó | tal cual | BLOQUEADO |
| `unknown` | RPC errorz ocasional | mensaje error con reintento | BLOQUEADO (fail-closed) |

## 6. Robustez y tolerancia a errores

- `EntitlementService` cachea {entitled, expiresAt, verifiedAt} con TTL de 5
  min en sesión; `loadForce()` revalida en cada intento de entrar al radar BT.
- Offline: si existen entitlements verificados previos y no expirados, se
  aplica la ventana de gracia (≤24 h); al volver la conectividad se revalida
  automáticamente (stream de conectividad). Llamadas concurrentes coalesced.
- Anti-abuso: la RPC es la única fuente de verdad; el flag local de
  `SharedPreferences` nunca habilita el radar.

## 7. Integración backend (diseño; despliegue REMOTO = BLOQUEO EXTERNO)

- Edge Function `verify-play-purchase`:
  - input: `{userId (JWT sub), packageName, productId, purchaseToken}`
  - llama `purchases.subscriptionsv2.get` con Service Account+JWT
  - estados de `SubscriptionPurchaseV2`: `SUBSCRIPTION_STATE_ACTIVE`,
    `_IN_GRACE_PERIOD`, `_PENDING`, `_CANCELED`, `_EXPIRED`,
    `_ON_HOLD`, `_REVOKED` → mapeados a `renewal_state`
  - upsert con `service_role`
- Tabla + RPC definidas en `ZONE_DATA_MIGRATION.md` (z215).
- Notificaciones RTDN (Pub/Sub webhook opcional): recomendación
  documentada ya que requiere infra externa (pubsub sender subscription).

## 8. Pruebas necesarias y por qué no se "valida billing" hoy

| Prueba | Requisito oficial | Estado |
|---|---|---|
| Compra real en sandbox | productos en Play Console + licencias de test + firmado release subido a un track | **BLOCKED (owner)** |
| RTDN/Developer API | service account + permisos | BLOCKED |
| Restauración | misma cuenta con compra activa | BLOCKED |

> No se afirmará que el flujo de facturación es validado sin estos artefactos
> oficiales. El código cliente queda listo y fail-closed; su ejecución real
> requiere la configuración de Play Console (fases: internal testing track,
> productos `zone_premium_monthly` / `zone_premium_annual`, tester license).

## 9. Productos

- Product IDs (placeholders sin precio, creados tal cual en Play Console por
  el owner):
  - `zone_premium_monthly`
  - `zone_premium_annual`
- No se inventan precios: la UI muestra el precio desde `ProductDetails`; hasta
  que Play devuelva datos, la pantalla muestra "Cargando…" y desactiva la compra.
