# ZONE — DESCUBRIMIENTO GEOGRÁFICO (GPS + RED) Y PRIVACIDAD

**Etapa:** A (Diseño) · **Fecha:** 2026-10-28 · Baseline `main@1bf6e1b`

Este documento define el flujo del descubrimiento gratuito por Internet (GPS o
proveedores de red), el control de visibilidad individual y el modelo de
privacidad de ubicación propuestos para el rediseño.

---

## 1. Flujo obligatorio (mapeado 1:1 al requisito)

1. El usuario habilita el descubrimiento (toggle visible en radar/ajustes).
2. **Consentimiento explícito**: primer uso dispara un diálogo de consentimiento
   ("Zone solicitará tu ubicación para mostrarte gente cerca; puedes ocultarte
   o revocarlo cuando quieras"). El consentimiento se persiste server-side
   (`discovery_preferences.location_sharing_enabled`) — no solo en cliente.
3. `LocationEngine` obtiene un fix y valida precisión/antigüedad
   (`maxAccuracy = 150 m`, `maxAge = 2 min`; ampliables en `DiscoveryConfig`).
4. Petición **autenticada** al backend (sesión Supabase; RPC deniega anon).
5. El servidor verifica identidad (`auth.uid()`), preferencias
   (consentimiento + visibilidad), radio permitido (clamp server), intervalo
   mínimo entre pings (anti-abuso ≥ 15 s) y reglas de privacidad
   (shadowban/stealth equivalente: `discovery_enabled`).
6. Consulta geoespacial server-side sobre presencia válida
   (`expires_at > now()`): lat/lng + bounding-box + haversine; límite 50 filas.
7. El cliente recibe perfiles autorizados (mismos campos que `v_profile`:
   id, zone_id, display_name, avatar_url, public_key — NO coordenadas) y una
   **distancia aproximada** truncada a un grid de 10 m calculada en servidor.
8. Presencia caduca tras 30 min sin pings (`expires_at` server-side).
9. Ocultarse = `expire_my_presence()` + preferencia off: sin nuevas
   publicaciones, excluido de nuevas búsquedas, fila de presencia eliminada.

## 2. Radio configurable

| Valor | 250 m | 500 m (default) | 1 km | 2 km (máx server) |
|---|---|---|---|---|

- Selector de chips en `RadarScreen` (modo GPS). Persistido por usuario en
  `discovery_preferences.radius_m` (server) + caché local para arranque rápido.
- **El servidor clampea** `radius_m` al conjunto `DiscoveryConfig.allowedRadii`
  (repetido en SQL: `{250,500,1000,2000}`); un cliente manipulado no puede
  exceder el máximo.
- Cambiar radio **no** altera identidad, matches ni conversaciones (solo
  preferencia + siguiente consulta).
- No se proponen radios premium en v1 (decisión D5: premium = Bluetooth);
  extender a 5–10 km queda como decisión abierta del producto (DEC-OPEN-1).

## 3. Ubicación híbrida GPS + red (aclaración de concepto)

- El sistema operativo combina fuentes (GPS, Wi-Fi/Red móvil, BLE vía
  FusedLocationProvider). `geolocator` devuelve la lectura disponible con
  `accuracy/timestamp` — la app **consume lecturas y valida calidad**, no
  intenta "elegir Wi-Fi vs GPS" (la conectividad Wi-Fi del dispositivo no
  equivale a geolocalización por Wi-Fi).
- Precisión predeterminada: **aproximada basta** para radio ≥ 250 m; no se
  exige `ACCESS_FINE_LOCATION` como requisito duro. Si el único fix disponible
  es demasiado impreciso (>150 m, p. ej. solo red), se muestra el estado
  "señal débil" y se permite reintentar o ampliar el radio —
  sin inventar distancias.
- Fuentes de error cubiertas: GPS ausente → fix de red; permiso denegado →
  tab de "otras funciones" + botón de reintento de permiso; servicio de
  ubicación desactivo → instrucciones habilitar ajustes; fix antiguo → no
  visible hasta nuevo fix; sin Internet → "discovery geográfico no disponible"
  (el proveedor BT no se activa automáticamente como fallback).

## 4. Visibilidad individual y privacidad

### 4.1 Controles de usuario
- `Aparecer en el descubrimiento` (`discovery_enabled`).
- `Compartir mi ubicación` (consentimiento, `location_sharing_enabled`).
- `Ocultarme ahora` (acción inmediata: borra presencia en servidor + estado UI).
- Ambos se guardan server-side y se aplican **aunque el cliente esté modificado**.

### 4.2 Interacción de conceptos
| `discovery_enabled` | `location_sharing_enabled` | Resultado |
|---|---|---|
| true | true | ping permitido; aparece para otros dentro del radio |
| true | false | NO se publica presencia; puede buscar (ver sin ser visto) |
| false | true | pings con publIcación previa viva: se cancela y se borra presencia (`expire`) |
| false | false | totalmente fuera del descubrimiento |

La UI nunca muestra "invisibles" mientras el servidor aún mantenga presencia
viva: tras `Ocultarme`, la confirmación UI solo llega si el RPC devuelve éxito
(estado reflejado **confirmado por servidor**).

### 4.3 Protecciones de privacidad del backend
| Riesgo | Control (residente en SQL de migración) |
|---|---|
| Exposición de coordenadas de otros | `discover_nearby_users` devuelve SOLO campos permitidos + `distance_m` truncada; `discovery_presence` sin policies SELECT → nadie lee lat/lng ajenos por REST |
| Enumeración de usuarios | `p_limit ≤ 50`, resultados solo dentro del radio, requiere ping del llamador con presencia válida propia |
| Consultas abusivas | Intervalo mínimo 15 s por usuario en ping (comparado con `updated_at`), límite por RPC, índices dedicados |
| Acceso anónimo | `REVOKE EXECUTE ... FROM anon, PUBLIC` + `auth.uid() IS NULL → EXCEPCIÓN` en RPC |
| Shadowban / bloqueos | Filtros server: `is_shadowbanned = false`, bloqueos bidireccionales excluidos, `discovery_enabled = true` del candidato |
| Ubicaciones falsas/teleport | Delta de distancia vs tiempo entre pings coherente (anti-teleport: se conserva la posición previa si el salto es físicamente imposible) + precisión máxima admitida (`p_accuracy_m` dentro del umbral) |
| Presencia eterna | `expires_at = now() + INTERVAL '30 minutes'` recalculado por el servidor; GC vía `DELETE WHERE expires_at < now() - INTERVAL '1 day'` (cron/edge) |
| Revocación de consentimiento | Toggle off → siguiente ping rechazado; `expire_my_presence` borra fila |
| Limpieza de registros | Borrado por cascada al eliminar cuenta (`ON DELETE CASCADE`) + GC de expirados |
| Anonimato absoluto | **NO se promete**: el servidor procesa coordenadas (temporal). Se documenta con claridad |

### 4.4 Nota honesta sobre datos
- `lat/lng` en el servidor: necesaria para responder "¿quién está cerca?"
  Sin ella, el cálculo tendría que hacerse en cada cliente (fuga total de
  coords + coste). Se minimiza: un punto por usuario, TTL 30 min, borrado en
  opt-out, jamás expuesto por API. Distancia mostrada a terceros: redondeada.
- Esta sección debe reflejarse (factual, sin garantías legales nuevas) si se
  revisa PRIVACY_POLICY.md — decisión del owner documentada en el informe.

## 5. Efectos sobre el legado BLE

- `bt_tokens`, encuentros y matches NO cambian.
- Un usuario visible solo por GPS **no** aparece en radar BT de otro usuario
  salvo que ambos tengan BLE activo (protocolos independientes).
- Si un usuario está en modo GPS y oculto y además es premium: su BLE igual
  exige entitlement — el gate es del proveedor BT, no del modo visible.
