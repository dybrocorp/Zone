# CHAT_AUDIT — Auditoría del Chat · ZONE (FASE 0)

## 1. Estado del pipeline de mensaje

Flujo real (`lib/screens/chat_screen.dart`):

```
UI (tempId) → 1) ¿mesh reachable? sendMeshMessage (Z-003 plaintext si no hay llave)
              → 2) ¿online? supabaseService.sendMessage (E2EE server-side)
              → si ninguno: throw Exception → status 'failed' → SOLO en memoria → se pierde
```

## 2. Hallazgos

| ID | Severidad | Problema |
|----|-----------|----------|
| Z-007 | P0 | Sin persistencia offline: `_sendMessage` marca 'failed' sin escribir en `LocalPendingMessage`; mensaje perdido al cerrar app. |
| Z-003 | P0 | Si no hay llave de sesión, el texto mesh se envía en claro. |
| Z-101 | P1 | Llave de sesión derivada de ECDH estático-estático; sin FS ni ratchet. |
| Z-102 | P1 | Cambio silencioso de `public_key` al perder la clave local → mensajes nuevos ilegibles; sin "nuevas llaves" aviso. |
| Z-105 | P1 | Receipts entregado/leído rotos: columnas y RPC ausentes (migración sin trackear) y métodos nunca llamados. |
| Z-106 | P1 | `deleteMatch` sin policy DELETE → no se pueden eliminar conversaciones. |
| Z-107 | P1 | Sync push-only; `_flushPendingMessages` genera `id` nuevo → duplicados. |

## 3. Detalles verificados (con líneas)

- `chat_screen.dart:443-525` — `_sendMessage`: optimista en memoria; `throw` en 496/500; catch marca failed (517-523). **Sin Isar.**
- `chat_screen.dart:527-582` — `_retryMessage`: reutiliza `_decryptedByMessageId` (memoria). Si la app se cerró, no hay texto que reintentar.
- `chat_screen.dart:133-167` — `_setupChat`: historial 100% desde Supabase (`getMessages`) — sin caché local (Isar solo guarda el perfil del otro usuario, no mensajes).
- `chat_screen.dart:112-120` — mensajes mesh entrantes con `id: 'mesh-${epoch}'` (colisión posible, igual que Z-005).
- `supabase_service.dart:341-374` — métodos de receipt definidos pero **ninguna pantalla los invoca** (grep confirmó 0 llamadas).
- `sync_service.dart:116-143` — `_flushPendingMessages` crea `id: _uuid.v4()` en el momento del flush → sin idempotencia.

## 4. Gaps de seguridad de conversación

1. **Autenticidad del mensaje mesh:** el receptor valida solo que exista perfil local para `source` (Z-004): cualquier vecino puede declarar ser otro usuario.
2. **Sin "safety numbers":** no hay huella de identidad comparada entre pares (Z-102).
3. **No hay reporte de clave cambiada:** cambio de `public_key` rompe con-versaciones sin diagnóstico.
4. **Realtime:** los mensajes viajan por broadcast `new_msg` sin verificación del emisor más allá de RLS de insert (el canal realtime usa filtro por match? ver BACKEND_AUDIT).

## 5. Leído vs Entregado vs Enviado

- `status` es local a la UI (`sending/sent/failed`).
- `delivered_at`/`read_at` son campos muertos: columnas no desplegadas + sin policy UPDATE + sin llamadas.
- El cliente nunca marca "visto" al leer (`markAllMessagesRead` no se invoca).

## 6. Pruebas

- `test/widget_test.dart` solo verifica que `ZoneApp` no crashea al pump — **no valida chat ni E2EE** (Z-301).
- `test/load_test_simulator.dart` NO testea el chat: inserta 50 `encounters` fake contra un proyecto Supabase con credenciales hardcodeadas (Z-203).

---
*Chat NO es offline-first ni E2EE verificado. Recomendación: detener afirmaciones de "E2EE grado industrial" hasta remediar.*