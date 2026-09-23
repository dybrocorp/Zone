# PERFORMANCE_AUDIT — Auditoría de Rendimiento · ZONE (FASE 0)

## 1. Consumo de batería / CPU

| Área | Hallazgo | Severidad | Bug |
|---|---|---|---|
| Radar global | `_globalDiscoveryTimer` cada 2 min invoca `getActiveUsersForRadar` (hasta **1000 perfiles**) y pulsa `update_bt_activity` | 🔴 | Z-112 |
| Painter de malla | `MeshLinkPainter.shouldRepaint => true` (radar_screen:668) repinta en cada frame con animación; `RadarPainter` repinta cuando cambia `animationValue` | 🟠 | Z-112 |
| BLE | escaneo `lowLatency` permanente sin filtro de dispositivo/Servicio | 🟠 | Z-204 |
| Local notifications | listener global de mensajes/matches (`onPostgresChanges`) activo como singleton sin stop | 🟡 | Z-110 |
| Mesh | flood de mensajes a todos los endpoints cuando no hay ruta (spam radio/TX) | 🟠 | Z-003 |
| Sync | `SyncService` schedule cada 15 min (+backoff) sincroniza cola + encuentros + perfiles, sin pull de mensajes (coste no aprovechado) | 🟡 | Z-107 |

## 2. Rendimiento de red / datos

- GET de hasta 1000 usuarios completos cada 2 min: exceso de payload (solo se muestran pocos en pantalla), incluso con RPC `get_active_users_for_radar` (si estuviera desplegado) → de todas formas 1000 filas.
- `getMessages`/`getMessagesPaginated` sin streaming: carga 50 mensajes + `_prefetchDecrypted` (descifra por lotes). Paginación solo hacia atrás (scroll up); sin paginación hacia adelante para el stream realtime.
- `load_test_simulator` (reachable en test) arma 50 inserts simultáneos — relevante solo si se ejecuta contra DB real (Z-203).
- Falta **agrupación/indices** para `messages` por match: existe `idx_messages_match` ✓. `encounters` con índice único horario ✓. `users.updated_at` sin índice en schema base (solo en parche) — filtro `.gte('updated_at')` haría seq scan sin él (Z-205).

## 3. Inicio / arranque

- `InitialLoadingScreen` ejecuta cargas en serie: `dotenv.load` → `ConnectivityService.initialize` → Isar+P2P en paralelo → `Supabase.initialize` → `SyncService` — ~aceptable, salvo `dotenv` roto (Z-006) que lo bloquea del todo.
- `dotenv.env['SUPABASE_URL']!` con `!` → crash si falta la variable.

## 4. Uso de memoria

- `_seenMessageIds` Set: crece hasta `_maxSeenMessageIds`, luego `clear()` entero (memory leak acotado pero con impacto funcional — Z-005).
- `_messages` en chat: lista sin límite en memoria; paginación incremental razonable.
- `_decryptedByMessageId` mapa en memoria (textos en claro) — necesario para retry, pero se mantiene al cerrar sesión de chat salvo el widget (GC maneja).
- Isar: perfiles/rutas guardados; mensajes NO persistidos (Z-007).

## 5. Recomendaciones FASE 1

1. **Radar:** bajar a pull manual/pull-to-refresh + TTL de caché (p. ej. 5 min); limitar a usuarios a <distancia>/con actividad; `update_bt_activity` con throttling (≤1/min).
2. **Painter:** memoizar geometría; `shouldRepaint` solo con datos cambiados; `RepaintBoundary`.
3. **BLE:** filtrar por UUID propio; parar scan cuando radar no visible.
4. **Mesh:** dedup LRU; limitar flood a 1 salto con TTL por mensaje.
5. **Sync:** pull de mensajes por cursor + push idempotente; evitar doble trabajo.
6. **Red:** compresión/selects mínimos; índices `updated_at`, `messages(match_id, created_at) DESC` ya existente.
7. **Arranque:** hacer el paso Supabase no bloqueante si offline (UI de reintento ya existe, pero debe no depender de `.env`).

---
*Sin perfiles de CPU/consumo medidos: verificación QUIALITATIVA del código. Documento FASE 0.*