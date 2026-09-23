# MESH_AUDIT — Auditoría de la Malla P2P (Nearby Connections) · ZONE (FASE 0)

> Implementación sobre `nearby_connections` (Google Nearby Connections API). Archivo principal: `lib/services/nearby_service.dart`.

## 1. Arquitectura actual

```
BLE advertise/scan (ble_proximity_service) + Nearby Connections (wifi/bt)
  → descubrimiento de endpoints (tokens BT pseudonym 'BT:...' / 'OFFLINE:...')
  → requestConnection/acceptConnection (sin auth — Z-004)
  → _shareProfileP2P (envía perfil + publicKey)  → deriva sesión (X25519) Z-101
  → _shareRoutingTable / _updateRoutingTable      (distancias, max hops)
  → sendMeshMessage / _handleMeshMessage           (routing + flood relay) Z-003/Z-005
```

## 2. Hallazgos

| ID | Severidad | Descripción |
|---|---|---|
| Z-003 | P0 | Payload mesh sin cifrar si no hay llave de sesión (`isEncrypted:false`, `text` en claro) y reenviado por flood a TODOS los vecinos. |
| Z-004 | P0 | `_onConnectionInitiated` → `acceptConnection` inmediato, sin verificar identidad/firma. Campo `source` declarado por el emisor (spoofable). |
| Z-005 | P0 | `msgId = DateTime.now().millisecondsSinceEpoch` (1015): colisiones en el mismo ms; dedup set se limpia a `_maxSeenMessageIds` → replay. |
| Z-204 | P2 | BLE lowLatency sin filtro de dispositivo/Servicio → escaneo de todo el entorno. |
| Z-112 | P1 | Timer global de descubrimiento 2 min + painter malla `shouldRepaint=true`. |

## 3. Rutas y flood (verificado)

- `_routingTable` persistida en Isar (`_isar.updateRoute`) con `distance` y `lastUpdate`.
- `_shareRoutingTable` envía rutas conocidas; `_handleRoutingTableUpdate` actualiza si distancia menor.
- Si no hay ruta hacia `target`, se hace **flood a todos los endpoints conectados** (1046-1054).
- Límite: `_maxMeshHops` saltos (default pequeña), sin TTL por mensaje (solo `hops`).
- **Problema adicional:** el flood de mensajes **no cifrados** a vecinos intermedios los expone en claro a todos los dispositivos de la malla (Z-003 amplificado).

## 4. Autenticación de peers (Z-004 detalle)

- `Nearby Connections` autentica el *canal* con el endpoint (confidencialidad del canal), **no la identidad**: cualquier app con la misma servicio ID puede conectarse y declarar `source='userA'`.
- La validación de entrega es `await _isar.getProfile(source) != null` (1081) — un perfil local cualquiera con ese zone_id habilita recibir; pero un atacante puede **inyectar** un perfil falso via `_onPayloadReceived` de un perfil P2P fraudelento (no hay firma del payload).
- **Mitigación:** handshake firmado con Ed25519 + challenge; vincular endpointId↔clave pública verificada; rechazar perfiles no firmados.

## 5. Rendimiento (Z-112)

- `_globalDiscoveryTimer` cada 2 min dispara pull global de hasta 1000 usuarios (`supabase_service.getActiveUsersForRadar`), aunque BLE/Nearby local baste.
- `MeshLinkPainter.shouldRepaint => true` repinta TODA la malla en cada frame de animación.
- Dedup set + caches en memoria sin LRU (a futuro, rebase).

## 6. Recomendaciones FASE 1

1. **Fail-closed:** prohibir envío sin llave de sesión; si no hay llave, pedirla vía handshake antes.
2. **Handshake firmado** + atadura endpoint↔identidad.
3. **msgId único** (UUIDv4/HMAC) + dedup LRU con TTL.
4. **Firma en cada paquete mesh** (autenticidad del `source`).
5. **Filtro BLE** por UUID/servicio propio; escaneo a baja latencia solo cuando la pantalla radar esté visible.
6. **Repintado condicional** del painter de la malla; pull global con caché + TTL.

---
*La malla es lo más arriesgado del proyecto: mezcla tráfico local no autenticado con E2EE roto. Documento FASE 0.*