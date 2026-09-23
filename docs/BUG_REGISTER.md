# BUG_REGISTER — Registro de Hallazgos FASE 0 · ZONE

**Total:** 37 hallazgos — **8 P0 · 12 P1 · 9 P2 · 8 P3**
**Convención:** ID `Z-NNN`; Severidad P0=crítico/seguridad, P1=grave, P2=importante, P3=mejora.
Toda "Solución" es propuesta de FASE 1, **pendiente de autorización**.

---

## P0 — CRÍTICO (seguridad / bloqueo funcional)

### Z-001 · Robo de identidad vía `claim_zone_id` (el ZONE-ID es la única credencial)
- **Severidad:** P0
- **Archivo:** `supabase_schema.sql:340-357` · `supabase_deploy.sql:140-153` · `lib/services/zone_id_service.dart:154-157, 314-316` · `lib/screens/login_screen.dart`
- **Problema:** `claim_zone_id(text)` es `SECURITY DEFINER` con `GRANT EXECUTE` a `authenticated` **y a `anon`**. Ejecuta `UPDATE users SET id = auth.uid() WHERE zone_id = p_zone_id` sin probar posesión de clave ni contra-muestra. El cliente (zone_id_service) lo invoca pasando `p_zone_id` + `p_public_key`, pero la función solo declara `p_zone_id` → **PostgREST devuelve error de firma** (la llamada legítima falla, la ilegítima también funciona si se llama con el parámetro correcto vía API).
- **Impacto:** Cualquier usuario autenticado que conozca (o adivine) un `zone_id` de 8 caracteres A-Z0-9 (~41 bits, sin verificación) puede **robar la cuenta y el perfil completo** de la víctima. El login acepta únicamente este código como credencial.
- **Causa raíz:** Diseño de "handover de ID" sin prueba de posesión criptográfica; firma cliente/servidor divergente no validada; GRANT innecesario a `anon`.
- **Riesgo:** Crítico (compromiso total de cuenta, robo de identidad, spam/abuso).
- **Solución (FASE 1.2 aplicada — Opción 3 Fase A, decisión CTO):** (a) `REVOKE` de `anon`/`PUBLIC` en `claim_zone_id` y `verify_zone_id`; solo `authenticated`. (b) `claim_zone_id` endurecido: formato estricto `^ZONE-[A-Z0-9]{8}$`, rate-limit (máx 5 fallos/15 min por zone_id, tabla `zone_claim_attempts`), **ya NO escribe `public_key`**, idempotente y auditado. (c) Cliente: las llamadas al RPC ya no envían `p_public_key`; se detiene la rotación silenciosa de clave en `ensureAuth` (276-302) y `checkAndFixRegistration` (388-391); `updateProfile` preserva la clave archivada (436-455); validación fail-fast `isValidZoneIdFormat`. (d) Fase B (siguiente iteración, pendiente de CTO): identidad de firma **Ed25519** (las claves actuales son X25519/ECDH y no firman) + códigos de recuperación + `update_public_key` firmado + transfer firmado.
- **Dependencias:** Z-103 (verify_zone_id, mismo lote), Z-207 (ensureAuth).
- **Prueba:** ✅ `flutter test` 5/5 (incluye `test/zone_id_format_test.dart`); ✅ `flutter analyze` sin findings nuevos; SQL con 7 pruebas de verificación documentadas en `supabase_migrations/secure_claim_zone_id.sql` (anon→403, formato, rate-limit, claim no altera public_key, idempotencia, sin oráculo).
- **Estado:** FIXED_LOCAL — **REQUIRES_REMOTE_VERIFICATION** (migración `supabase_migrations/secure_claim_zone_id.sql` + baselines `schema`/`deploy` actualizados; aplicar en remoto vía supabase CLI y ejecutar las 7 pruebas SQL).

### Z-002 · RLS SELECT de `users` filtra TODAS las columnas a cualquier autenticado
- **Severidad:** P0
- **Archivo:** `supabase_schema.sql:191-193` · `supabase_deploy.sql:233-235`
- **Problema:** La policy `"Ver perfiles públicos"` es `FOR SELECT TO authenticated USING (is_shadowbanned = FALSE)`: cualquier autenticado lee **todas** las columnas de todos los perfiles no shadowbanned (handles privados IG/FB/TikTok, `gallery_photos`, `public_key`, `avatar_url`, `reports_count`, `stealth_mode`). Los filtros de visibilidad (`ig_visible` etc.) se aplican **solo en el cliente**.
- **Impacto:** Fuga de datos personales (handles privados, galería "privada", clave pública). Un atacante con `select()` directo vía API obtiene los datos "privados" de toda la base.
- **Causa raíz:** RLS de columna inexistente (PostgreSQL no soporta column-level security) + no se reemplazó por una vista/RPC que filtre por flags y por `blocked_users`.
- **Riesgo:** Alto (incumplimiento GDPR/ley 1581, doxxing).
- **Solución:** Exponer perfiles solo vía RPC/vista que devuelva NULL en handles con `*_visible=false`, oculte `gallery_photos`, `public_key` según política; aplicar filtro server-side de `blocked_users` en la query; mínimo privilegio en SELECT.
- **Dependencias:** Z-104 (resolve_bt_token), Z-111 (bucket público).
- **Prueba:** SQL test: consumo directo via PostgREST con 2 usuarios autenticados → columna `instagram_handle` debe ser null si `ig_visible=false`.
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-003 · Mesh envía mensajes EN CLARO si no hay llave de sesión
- **Severidad:** P0
- **Archivo:** `lib/services/nearby_service.dart:1008-1039` (packet `isEncrypted: false` en 1018) y `1057-1156`
- **Problema:** `sendMeshMessage` construye el payload con `'isEncrypted': false` y `'text': message` **antes** de intentar cifrado; si no hay `sessionKey` o falla el cifrado, el paquete se reenvía tal cual (flood a todos los vecinos) en claro. El receptor trata el texto como cuerda directa.
- **Impacto:** Todo mensaje mesh "E2EE" sin llave de sesión derivada viaja en texto plano y se reenvía por múltiples saltos (visibilidad ante cualquier dispositivo intermediario). Contradice la promesa de E2EE.
- **Causa raíz:** Falla silenciosa a menos-privilegio (opt-out del cifrado) en lugar de fail-closed; derivación de llave solo ocurre al recibir perfil P2P (`_onPayloadReceived` 905-917), no garantizada antes de enviar.
- **Riesgo:** Crítico (intercepción de conversaciones).
- **Solución:** Fail-closed: si no hay llave, NO enviar (o enviar solo tras solicitar/derivar llave); añadir autenticación de paquete (firma Ed25519 ya disponible en el stack); incluir flag `isEncrypted` siempre true o estructura firmada.
- **Dependencias:** Z-004, Z-005, CRYPTO (ratchet).
- **Prueba:** Test unitario de `sendMeshMessage` sin sessionKey → se niega a enviar; test de integración con 2 peers.
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-004 · Conexiones P2P aceptadas sin autenticación (spoofing de `source`)
- **Severidad:** P0
- **Archivo:** `lib/services/nearby_service.dart:760-763` (`_onConnectionInitiated` → `acceptConnection` inmediato), `810-814`, y `1062-1088`
- **Problema:** Toda conexión entrante es aceptada sin verificar identidad del peer (firma/desafío). El campo `packet['source']` es un string libre que el emisor declara (`'source': _myZoneId` en 1013); cualquier dispositivo puede hacerse pasar por otra zona. El bloqueo de mensajes depende solo de que exista un perfil local para `source`.
- **Impacto:** Suplantación de identidad, inyección de mensajes falsos en nombre de otros usuarios, abuso del "match previo" gating, spam en malla.
- **Causa raíz:** Modelo de confianza implícita de Nearby Connections; no hay handshake criptográfico.
- **Riesgo:** Alto.
- **Solución:** Handshake firmado (Ed25519) con challenge/nonce entre pares antes de aceptar; vincular `endpointId` ↔ `zone_id` verificada; revocar automáticamente si la firma falla.
- **Dependencias:** Z-003, Z-005.
- **Prueba:** El `endpoint` falsifica `source` → debe rechazarse.
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-005 · `msgId` = epoch milis + dedup con reinicio a 500 → colisiones y replay
- **Severidad:** P0
- **Archivo:** `lib/services/nearby_service.dart:1015` (`'msgId': DateTime.now().millisecondsSinceEpoch.toString()`), `1067-1076` (set `_seenMessageIds`, `_maxSeenMessageIds`)
- **Problema:** El ID de mensaje es la marca de tiempo en ms → dos mensajes emitidos en el mismo ms colisionan; al superar `_maxSeenMessageIds` el set se **limpia entero**, permitiendo re-despachar un mensaje antiguo (replay). Además un atacante conoce el rango de IDs.
- **Impacto:** Deduplicación en falso (pérdida de mensajes) y cansancio/duplicados en la malla; replay de mensajes tras limpiar la caché.
- **Causa raíz:** ID no criptográfico ni único; estructura FIFO en lugar de LRU/time-based.
- **Riesgo:** Alto (consistencia y replay).
- **Solución:** `msgId` = UUIDv4 o HMAC(zona+contador+epoch); dedup con LRU y TTL (no clear global), o ventana deslizante horaria.
- **Dependencias:** Z-004.
- **Prueba:** Unit: 2 mensajes en mismo ms → IDs distintos; dedup LRU no pierde entradas nuevas.
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-006 · La app NO arranca con el pubspec del working tree (`.env` fuera de assets)
- **Severidad:** P0 (funcional)
- **Archivo:** `pubspec.yaml` (diff local: elimina `- .env` de `assets:`) · `lib/screens/initial_loading_screen.dart:33` (`dotenv.load(fileName: '.env')`)
- **Problema:** `flutter_dotenv` 5.x carga desde el bundle de assets; `.env` ya no está declarado → `rootBundle.load('.env')` lanza `FileNotFoundError`. El test lo reproduce: `[Startup] ERROR CRÍTICO: Instance of 'FileNotFoundError'`. El usuario queda atascado en "Error al iniciar. Reintenta por favor." sin salida.
- **Impacto:** Bloqueo total de la app en build debug y release. La versión commitada (con `.env` en assets) sí arrancaba; el cambio local lo rompe.
- **Causa raíz:** Eliminación del asset `.env` en el working tree (probable intención de no empaquetar config) sin migrar a otra estrategia de configuración.
- **Riesgo:** Crítico funcional.
- **Solución aplicada (FASE 1.1):** Estrategia (b) — configuración compile-time en `lib/utils/env_config.dart` (`String.fromEnvironment('SUPABASE_URL' | 'SUPABASE_ANON_KEY')`) con fallback dev tolerante a `flutter_dotenv` (sin crash si falta el asset). `initial_loading_screen.dart` ya no usa `!` ni `dotenv.load` obligatorio: si no hay configuración, muestra "Falta la configuración del servidor. Reinstala la app." sin bucle de reintento. Builds locales/release con `flutter run/build --dart-define-from-file=.env`. El `.env` NO se reintroduce en assets y permanece gitignored. README.md y CONTRIBUTING.md documentan el flujo.
- **Dependencias:** Z-305.
- **Prueba:** `flutter test` pasa con log `[Startup] Configuración de Supabase ausente` (antes: `ERROR CRÍTICO: FileNotFoundError`); sonda con `--dart-define-from-file=.env` confirma URL y anon key inyectadas; `flutter analyze` sin findings nuevos.
- **Estado:** VERIFICADO_LOCAL — FASE 1.1 completada. (Falta verificación en dispositivo/build release real: `REQUIRES_REMOTE_VERIFICATION` para release APK.)

### Z-007 · Offline-first roto: el chat pierde mensajes y no persiste nada en Isar
- **Severidad:** P0 (funcional)
- **Archivo:** `lib/screens/chat_screen.dart:443-525` (`_sendMessage`), `527-582` (`_retryMessage`), `133-167` (`_setupChat` solo server), `lib/models/isar_models.dart` (`LocalPendingMessage` sin uso)
- **Problema:** Sin mesh ni internet, `throw Exception('Sin conexión Mesh ni Internet')` (línea 500) marca 'failed' pero **nunca escribe** en `LocalPendingMessage`/Isar; el texto vive solo en `_decryptedByMessageId` en memoria → se pierde si se cierra la app. `_setupChat` carga historial únicamente desde Supabase (166) → sin internet no se abre el chat aunque esté cacheado. El arranque global exige internet (Z-006 hace bloqueante aunque sea red).
- **Impacto:** Pérdida irreversible de mensajes que prometía offline-first; UX rota en zonas sin cobertura.
- **Causa raíz:** El modelo local (isar_models `LocalPendingMessage`) fue creado pero el chat no lo usa; la máquina de estados es de UI (temp/failed/sent) sin capa offline.
- **Riesgo:** Alto (datos de usuario).
- **Solución:** Escribir siempre en `LocalPendingMessage` en `_sendMessage` (idempotente); cola que sincroniza al recuperar red (`sync_service._flushPendingMessages` ya existe, adaptarlo); al abrir chat, merge Isar caché + servidor; enmascarar estado del mesh en el header.
- **Dependencias:** Z-107 (sync), Z-205.
- **Prueba:** Test de widget/service: enviar sin red → mensaje en Isar; reabrir → presente; recuperar red → sincroniza a Supabase sin duplicar.
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-008 · Premium 100% simulado: cualquiera obtiene Premium gratis
- **Severidad:** P0 (fraude/ingresos)
- **Archivo:** `lib/services/premium_service.dart:34-39` · `lib/screens/donations_screen.dart:44` (botón "donar" llama `setPremium(true)`)
- **Problema:** No hay IAP (sin `in_app_purchase` en pubspec); `setPremium` escribe solo `SharedPreferences`. `loadPremiumStatus` lee `is_premium` del server, pero `is_premium` solo existe en `supabase_migrations/add_is_premium.sql` (no aplicado necesariamente) y **nada en el server lo valida ni lo activa**.
- **Impacto:** Todos los usuarios pueden activar Premium sin pagar; sin enforcement server-side de las features premium.
- **Causa raíz:** Feature flag local sin flujo de compra verificado.
- **Riesgo:** Alto (fraude, promesa legal).
- **Solución:** Flujo IAP real (StoreKit/Play Billing) o flujo server-verified (edge function + webhook); exponer features premium tras validación server-side; nunca auto-otorgar desde el cliente.
- **Dependencias:** Frontend de pagos, Edge Function.
- **Prueba:** E2E de compra sandbox; verificación en server que revierte si no hay recibo válido.
- **Estado:** ABIERTO — FASE 1 pendiente.

---

## P1 — GRAVE

### Z-101 · Sin Forward Secrecy ni rotación (ECDH estático-estático)
- **Severidad:** P1
- **Archivo:** `lib/services/p2p_security_service.dart` (`deriveSessionKey`) · `lib/services/chat_e2ee_service.dart` (X25519 + ChaCha20-Poly1305)
- **Problema:** La llave de sesión se deriva de pares clave estáticos (X25519 estático-estático): misma llave de sesión mientras no cambien las claves; no hay ratchet (double/triple), ni rotación de llaves de mensaje, ni Data/Metadata de seguridad.
- **Impacto:** Sin secreto perfecto hacia adelante: si una clave privada se compromete, todo el historial de esa sesión se descifra; el comentario/doc "Forward Secrecy" es falso.
- **Causa raíz:** Elección de esquema ECDH simple para simplificar; documentación incorrecta.
- **Riesgo:** Alto post-compromiso.
- **Solución:** Implementar ratchet (ej. Signal ratchet con keys efímeras intermedias) o al menos rotación DH efímera por mensaje; corregir docs; añadir KDF con estado (contador) para nonces.
- **Dependencias:** Z-003, Z-102.
- **Prueba:** Vectors criptográficos: dos ratchets convergen; claves comprometidas no descifran mensajes pasados (FS).
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-102 · Pérdida local de clave → se empuja clave nueva al servidor rompiendo mensajes pasados
- **Severidad:** P1
- **Archivo:** `lib/services/zone_id_service.dart:426-432` (re-genera `public_key` si falta) y `179-181` (`ensureAuth`) · `lib/services/p2p_security_service.dart`
- **Problema:** Si `flutter_secure_storage` pierde la clave (reinstalación, borrado de datos, fallo de Keystore), se genera un nuevo par y se sobrescribe `public_key` en `users` silenciosamente.
- **Impacto:** El contacto cifra con la nueva pública pero su peer todavía tiene la anterior → los mensajes nuevos no descifran; no hay aviso ni clue de "identidad reiniciada" (safety numbers).
- **Causa raíz:** No hay respaldo ni notificación de cambio de identidad; single public_key column.
- **Riesgo:** Alto (pérdida de comunicación persistente, incomprensión).
- **Solución:** Guardar pairId/huella de identidad; advertir en UI el cambio de seguridad (como WhatsApp "nuevas llaves"); opción de migrar llaves (backup cifrado) o re-encriptar con los peers.
- **Dependencias:** Z-101.
- **Prueba:** Test: reinstall simulado → el chat nuevo falla descifrado pero muestra aviso; peers re-establecen.
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-103 · `verify_zone_id` = oráculo de enumeración IDOR expuesto a anon
- **Severidad:** P1
- **Archivo:** `supabase_schema.sql:361-382` · `supabase_deploy.sql:155-177` (SECURITY DEFINER + `GRANT ... TO anon`)
- **Problema:** RPC devuelve `{id, zone_id, display_name}` de cualquier zone_id (o NULL). Aunque no está llamado desde el app, es invocable por anon: permite enumerar la existencia/cuenta de cualquier ID, revelando `id` (uso en otros ataques).
- **Impacto:** Confirmación de existencia y fuga de uid de cuentas; base para robo (Z-001) y para targeting.
- **Causa raíz:** GRANT anon + SECURITY DEFINER innecesario; función muerta.
- **Riesgo:** Medio-alto.
- **Solución (FASE 1.2 aplicada — mismo lote que Z-001):** `verify_zone_id` endurecido: `REVOKE` de `anon`/`PUBLIC` (solo `authenticated`), formato estricto, rate-limit compartido (`zone_claim_attempts`) y **ya no expone `id` ni `zone_id`** (devuelve `{exists, display_name, avatar_url}`). La función queda disponible solo para el flujo login autenticado.
- **Dependencias:** Z-001.
- **Prueba:** ✅ `flutter analyze` sin findings nuevos; SQL: prueba 1 y 7 del bloque de verificación de `supabase_migrations/secure_claim_zone_id.sql`.
- **Estado:** FIXED_LOCAL — **REQUIRES_REMOTE_VERIFICATION** (aplicar migración en remoto vía supabase CLI y verificar 403 para anon).

### Z-104 · `resolve_bt_token` expuesto a anon; `used` nunca se marca
- **Severidad:** P1
- **Archivo:** `supabase_schema.sql:385-425` · `supabase_deploy.sql:179-219` (SECURITY DEFINER, `GRANT ... TO anon`) · `bt_tokens.used` (schema:43)
- **Problema:** Con solo un token BT válido (5-10 min) un anon obtiene perfil completo del dueño (zone_id, uid, public_key, handles si visibles). `used` nunca se set ea TRUE: el mismo token puede resolverse repetidamente y por múltiples atacantes. `fix_radar_bilateral.sql:53` incluso fuerza `used=FALSE` (limpió el flag).
- **Impacto:** Exposición de perfiles con token robado/interceptado; reuso infinito.
- **Causa raíz:** El flag `used` quedó obsoleto pero el diseño de consumo único no se sustituyó por expiración corta + rate limit; GRANT anon innecesario.
- **Riesgo:** Alto (espionaje de radar).
- **Solución:** GRANT solo a authenticated; marcar token como usado/borrar tras resolución (idempotencia con la misma llamada); expiración en minutos; rate limit por IP.
- **Dependencias:** Z-002.
- **Prueba:** Test SQL: segunda resolución del mismo token → NULL.
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-105 · Receipts de entrega/lectura rotos end-to-end
- **Severidad:** P1
- **Archivo:** `lib/services/supabase_service.dart:341-374` · `supabase_migrations/add_message_delivery_status.sql` (untracked) · schema/deploy (sin columnas ni RPC)
- **Problema:** `markMessageDelivered`/`markMessageRead` escriben `delivered_at`/`read_at` en `messages`: columnas que **no existen** en schema/deploy (solo en la migración **sin trackear**), y **no hay policy UPDATE en messages** → la escritura falla por RLS. `markAllMessagesRead` llama al RPC `mark_messages_read` que **no existe en ningún SQL del repo**. Además ningún screen llama a estos métodos.
- **Impacto:** Entregados/leídos nunca funcionan, ni siquiera cuando estén desplegados.
- **Causa raíz:** Feature "S5+S6" a medio desplegar; migración sin commitear y sin incluir en deploy.
- **Riesgo:** Medio (feature rota).
- **Solución:** Aplicar migración (trackearla e incluirla en `supabase_deploy.sql`), añadir policy UPDATE para los dos participantes, llamar a los métodos desde el chat (visible/visto), y RPC con `SECURITY DEFINER` restringido al lector.
- **Dependencias:** Z-206.
- **Prueba:** Integración: B abre chat → A ve "leído ✓✓".
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-106 · `deleteMatch` sin policy DELETE en `matches`
- **Severidad:** P1
- **Archivo:** `lib/services/supabase_service.dart:180` · `lib/screens/chats_list_screen.dart:239` · ningún SQL define `FOR DELETE` en `matches`
- **Problema:** El app intenta borrar el match; RLS no otorga DELETE (solo SELECT/INSERT/UPDATE). El borrado falla silenciosamente. `supabase_delete_fix.sql` es el parche pendiente.
- **Impacto:** El usuario no puede eliminar conversaciones; datos "borrados" persisten.
- **Causa raíz:** Policy DELETE omitida en schema/deploy; el fix existe como script suelto.
- **Riesgo:** Medio (cumplimiento de "derecho al borrado").
- **Solución:** Aplicar `supabase_delete_fix.sql` (policy DELETE para participantes) e integrarlo en deploy; verificar también cascadas y storage.
- **Dependencias:** Z-002 (RLS mirrors).
- **Prueba:** UI: eliminar match → desaparece de chats_list y de la DB.
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-107 · Sincronización push-only + regenera `id` → duplicados
- **Severidad:** P1
- **Archivo:** `lib/services/sync_service.dart:116-143` (`_flushPendingMessages` genera `id: _uuid.v4()` en 122-123), `161-182` (`_syncMessages` solo push)
- **Problema:** La cola local inventa un `id` nuevo al subir → si el insert se reintenta tras éxito parcial (retry), crea **duplicados**; no hay idempotencia por `client_id`. No existe pull de mensajes remotos→locales (el chat abre solo server-side).
- **Impacto:** Mensajes duplicados en servidor; un dispositivo no ve mensajes enviados desde otro dispositivo; la promesa multi-dispositivo no se cumple.
- **Causa raíz:** Modelo de id local no estable; sync unidireccional.
- **Riesgo:** Alto (integridad de datos).
- **Solución:** IDs locales estables (`client_id` UUID guardado en el modelo local desde la creación); upsert idempotente (`ON CONFLICT (client_id)`); implementar pull de mensajes con cursor por match y merge LWW.
- **Dependencias:** Z-007, Z-205.
- **Prueba:** Test de integración: envío offline→online sin duplicados; dispositivo B recibe pull.
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-108 · `updateProfile` escribe columna `updatedAt` (camelCase) inexistente
- **Severidad:** P1
- **Archivo:** `lib/services/zone_id_service.dart:436-453` (`'updatedAt'` en 450) · `lib/screens/profile_edit_screen.dart:219`, `profile_setup_screen.dart:50`
- **Problema:** El upsert incluye `updatedAt` camelCase; el esquema solo define `updated_at` (y solo tras `supabase_multi_device_fix.sql`). PostgREST rechaza columnas desconocidas → el guardado de perfil **falla** (o el upsert entero se aborta), con perfil quedando en estado inconsistente en Isar (si el server falla, `_isar.saveProfile` no ocurre por el throw).
- **Impacto:** No se guardan cambios de perfil en servidor; datos locales vs remotos divergen.
- **Causa raíz:** Nombre de columna inconsistente cliente/servidor; sin validación de schema.
- **Riesgo:** Alto (pérdida silenciosa de ediciones).
- **Solución:** Usar `updated_at` (tras aplicar multi_device_fix) o eliminar el campo si el trigger lo gestiona; test de contrato.
- **Dependencias:** Z-109.
- **Prueba:** Editar perfil → refrescar → persiste en DB.
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-109 · RPCs de radar/actividad y `updated_at` solo en parche, no en schema/deploy
- **Severidad:** P1
- **Archivo:** `lib/services/supabase_service.dart:575, 590-592, 603, 624-626, 638` · `supabase_multi_device_fix.sql` (parche suelto)
- **Problema:** El app invoca `get_active_users_for_radar`, `update_bt_activity`, `get_radar_stats` y usa `updated_at` en queries; **ninguno** está definido en `supabase_schema.sql`/`supabase_deploy.sql` (solo en `supabase_multi_device_fix.sql`). Sin el parche aplicado: fallback lento, queries con `.gte('updated_at')` fallan (columna inexistente) y `update_bt_activity`/`get_radar_stats` silenciosamente no-op.
- **Impacto:** Radar global degradado o inoperante; actividad BT no registrada; UX inconsistente.
- **Causa raíz:** Scripts fuera del flujo de migración principal; estado del proyecto remoto desconocido.
- **Riesgo:** Medio-alto (funcionalidad núcleo + errores silenciosos).
- **Solución:** Consolidar todos los parches en `supabase_deploy.sql` (idempotente) y ejecutar; lanzar error visible (no catch-and-ignore) en dev; documentar como migración única.
- **Dependencias:** Z-108.
- **Prueba:** SQL editor: funciones existen tras deploy; API `getActiveUsersForRadar` devuelve datos.
- **Estado:** ABIERTO — FASE 1 pendiente (requiere aplicar parches en Supabase remoto).

### Z-110 · Sin notificaciones push; listener global nunca se detiene
- **Severidad:** P1
- **Archivo:** `lib/services/supabase_service.dart:648-689` (`startGlobalNotificationListener/stopGlobal...`) · `lib/services/notification_service.dart`
- **Problema:** Solo hay notificaciones locales mientras la app vive (flutter_local_notifications); sin push (FCM/APNs) ni registro de token. En iOS no se configuran DarwinNotificationSettings. Además `startGlobalNotificationListener` no se llama desde un ciclo de vida controlado (singleton) y su par `stopGlobalNotificationListener` solo existe como método sin invocación demostrable.
- **Impacto:** Sin notificaciones cuando la app está cerrada; listener potencialmente duplicado/memoria.
- **Causa raíz:** Falta de integración push; orquestación de ciclo de vida.
- **Riesgo:** Medio (feature prometida en roadmap).
- **Solución:** Integrar FCM/APNs + edge function para enviar; configurar Darwin settings; gestionar listener en app lifecycle y singleton global.
- **Dependencias:** Backend push.
- **Prueba:** App cerrada + mensaje → notificación push.
- **Estado:** ABIERTO — FASE 1 pendiente (requiere backend).

### Z-111 · Bucket `profiles` público: fotos "privadas" y galería accesible sin auth
- **Severidad:** P1
- **Archivo:** `supabase_schema.sql:313-315` (`INSERT INTO storage.buckets ... public=true`) · `lib/screens/profile_edit_screen.dart`
- **Problema:** `avatar_url` publica en un bucket público. Aunque `avatar_is_public=false` o `gallery_photos` con flags, la URL del archivo es accesible sin autenticación.
- **Impacto:** Fotos declaradas privadas son públicas (link-sharing); incumplimiento de promesa de privacidad.
- **Causa raíz:** Bucket público global + control de visibilidad solo cliente.
- **Riesgo:** Alto (privacidad de imágenes).
- **Solución:** Bucket privado con firmas de acceso (postgrest/edge function para URLs firmadas) y políticas por flag; actualizar avatar para usuarios con privacidad.
- **Dependencias:** Z-002.
- **Prueba:** URL firmada caduca; acceso directo sin firma → 403.
- **Estado:** ABIERTO — FASE 1 pendiente.

### Z-112 · Radar global: hasta 1000 perfiles/todo-descargado cada 2 min + painter `shouldRepaint=true`
- **Severidad:** P1 (rendimiento/privacidad)
- **Archivo:** `lib/services/nearby_service.dart:396` (timer 2 min) · `lib/services/supabase_service.dart:575, 592` (limit 1000) · `lib/screens/radar_screen.dart:357-358` (espera `CACHE:`/`GLOBAL:` que nadie emite), `622` y `668` (`shouldRepaint => true`)
- **Problema:** El radar descarga el pull global de hasta 1000 perfiles cada 2 minutos; el painter de la malla repinta siempre (`true`), forzando trabajo de CPU al animar; además las listas globales esperadas por la UI nunca las produce NearbyService.
- **Impacto:** Batería/CPU alto; exceso de tráfico; UI con features inalcanzables (código muerto).
- **Causa raíz:** Sin caché/expiración por distancia; pintura no memoizada; UI y servicio desconectados.
- **Riesgo:** Medio (accede a datos sin degradación).
- **Solución:** Cache con TTL y filtro geográfico/por actividad; painter con repintado condicional (solo cambios en datos); unificar endpoints de radar (emitir `CACHE:`/`GLOBAL:` o quitar el código muerto).
- **Dependencias:** Z-109.
- **Prueba:** Profile con DevTools: menos repaints; red reducida.
- **Estado:** ABIERTO — FASE 1 pendiente.

---

## P2 — IMPORTANTE

### Z-201 · `use_build_context_synchronously` (2 ocurrencias — crash potencial)
- **Severidad:** P2
- **Archivo:** `lib/screens/chats_list_screen.dart:228` · `lib/screens/donations_screen.dart:46`
- **Problema:** Uso del `BuildContext` tras await sin guard de `mounted` (el chequeo existente es de otro State).
- **Impacto:** Crash "setState after dispose"/Uso de context difunto.
- **Causa raíz:** Falta de guard de mounted en handlers async.
- **Riesgo:** Medio.
- **Solución:** Guardar `if (!mounted) return;` antes de usar context.
- **Dependencias:** —.
- **Prueba:** `flutter analyze` limpio para esas líneas + widget test de doble navegación.
- **Estado:** ABIERTO.

### Z-202 · Errores técnicos crudos expuestos al usuario
- **Severidad:** P2
- **Archivo:** múltiples `SnackBar`/`Text` con `$e`/`Exception(...)` (chat_screen, donations, auth, profile…)
- **Problema:** Se muestran `Exception: No se pudo guardar en el servidor`, textos internos y UTC stack en la UI.
- **Impacto:** Confusión del usuario; filtra internals de implementación.
- **Causa raíz:** Falta de capa de mensajes de error amigables.
- **Riesgo:** Bajo-medio.
- **Solución:** Mapear errores a textos por código/estado; logger con nivel para dev.
- **Dependencias:** —.
- **Prueba:** Revisión UX + test de golden.
- **Estado:** ABIERTO.

### Z-203 · Credenciales hardcodeadas de OTRO proyecto Supabase en test
- **Severidad:** P2
- **Archivo:** `test/load_test_simulator.dart:7-8` (URL `leejpxwctnubihacudik.supabase.co` + anon `sb_publishable_vl-...`) — trackeado en git
- **Problema:** URL+anon key de un proyecto ajeno/apagado en el repo; si se ejecuta, inserta datos fake en `encounters` de ese proyecto.
- **Impacto:** Derivada de secretos (publishable), basura de datos, confusión de entorno.
- **Causa raíz:** Script de prueba manual commitado con credenciales.
- **Riesgo:** Bajo-medio.
- **Solución:** Eliminar o mover a fixture con variables de entorno; no trackear credenciales.
- **Dependencias:** —.
- **Prueba:** `git grep supabaseUrl` sin hits en test.
- **Estado:** ABIERTO.

### Z-204 · BLE lowLatency escanea todos los dispositivos cercanos sin filtro
- **Severidad:** P2
- **Archivo:** `lib/services/ble_proximity_service.dart` (escaner `lowLatency` sin `mac_addr`/service filter)
- **Problema:** Se reciben beacon de CUALQUIER dispositivo BLE del entorno (no solo de la app) y se procesan.
- **Impacto:** Batería, ruido, posible fuga de información de presencia a terceros del mismo entorno.
- **Causa raíz:** Escaneo amplio sin filtro de manufacturer/service UUID propio.
- **Riesgo:** Medio.
- **Solución:** Filtrar por ServiceData/UUID de la app; estados paused en background.
- **Dependencias:** —.
- **Prueba:** Scan solo reacciona ante UUID propio.
- **Estado:** ABIERTO.

### Z-205 · Base de datos sin `updated_at` en schema → sincronización LWW y radar dependen de parche
- **Severidad:** P2
- **Archivo:** `supabase_schema.sql:13-32` (sin `updated_at`) · `sync_service.dart:184-207` (LWW con `updated_at`)
- **Problema:** La columna base no existe (solo tras `multi_device_fix.sql`); el sync LWW y las queries del radar dependen de ella.
- **Impacto:** Fallos silenciosos de sync si el parche no está aplicado.
- **Causa raíz:** Schema base divergente del código.
- **Riesgo:** Medio.
- **Solución:** Añadir `updated_at` + trigger en schema y deploy (consolidar parche).
- **Dependencias:** Z-109.
- **Prueba:** Sync aplica LWW; trigger actualiza timestamp.
- **Estado:** ABIERTO.

### Z-206 · Sin policy UPDATE en `messages` (bloquea receipts y ediciones futuras)
- **Severidad:** P2
- **Archivo:** `supabase_schema.sql:250-272` · `supabase_deploy.sql:278-299` (solo INSERT/SELECT)
- **Problema:** No hay `FOR UPDATE` en messages → actualizar `delivered_at`/`read_at` (aun con columnas desplegadas) falla por RLS (no-permitido). `deleteMessage` (supabase_service:377) tampoco tiene policy DELETE.
- **Impacto:** Receipts y borrado de mensajes inoperantes.
- **Causa raíz:** Policies incompletas.
- **Riesgo:** Medio.
- **Solución:** Policy UPDATE/DELETE limitada a participantes del match aceptado.
- **Dependencias:** Z-105.
- **Prueba:** SQL: UPDATE desde participante → OK; tercero → denegado.
- **Estado:** ABIERTO.

### Z-207 · `ensureAuth` reclama zone_id en cada arranque con payload roto
- **Severidad:** P2
- **Archivo:** `lib/services/zone_id_service.dart:309-326`
- **Problema:** Cada inicio llama a `claim_zone_id` con `p_zone_id`+`p_public_key` (firma inexistente) → falla cada vez (catch log). Peor: si la firma se "arreglara" solo a `p_zone_id`, cualquier reinicio del dispositivo re-autentica sin más prueba que el ID local, que un atacante pudo ver en claro en la malla (nearby P2P comparte zone_id a vecinos).
- **Impacto:** Ventana de reclamo automático; falsa sensación de seguridad.
- **Causa raíz:** Invocación redundante y no segura.
- **Riesgo:** Medio.
- **Solución:** Reclamar solo tras login explícito (login_screen), con prueba criptográfica; quitar el auto-claim del arranque.
- **Dependencias:** Z-001.
- **Prueba:** Sin login, un dispositivo nuevo no puede adueñarse del ID; logs limpios.
- **Estado:** ABIERTO.

### Z-208 · Radar: endpoints `CACHE:`/`GLOBAL:` esperados por la UI nunca se emiten
- **Severidad:** P2
- **Archivo:** `lib/screens/radar_screen.dart:357-358` · `lib/services/nearby_service.dart` (no emite)
- **Problema:** La UI filtra usuario por prefijos `CACHE:`/`GLOBAL:` en `endpointId`, pero NearbyService solo crea endpoints de Nearby/MOCK; la feature radar-global queda inaccesible o invisible en esa rama del código.
- **Impacto:** Código muerto e inconsistencia; posibles entradas invisibles.
- **Causa raíz:** Evolución de diseño UI vs servicio no sincronizada.
- **Riesgo:** Bajo-medio.
- **Solución:** Implementar emisión de esos marcadores o eliminar la rama.
- **Dependencias:** Z-112.
- **Prueba:** Radar muestra usuarios globales con el marcador previsto.
- **Estado:** ABIERTO.

### Z-209 · Artefactos de build/crash en la raíz (sin limpiar, algunos trackeados antes)
- **Severidad:** P2
- **Archivo:** raíz: `hs_err_pid*.log`, `replay_pid*.log` (crashes JVM/Gradle), `Zone.apk`, `tmp_check_crypto.dart` (ignorado por `tmp_*.dart` pero presente)
- **Problema:** Artefactos de compilación y volcados de crash en la raíz sin gitignore para `hs_err_pid*`/`replay_pid*` (solo `*.log`, y estos nombres no aplican a esos archivos… `hs_err_pid` no termina en `.log`; quedan sin ignore).
- **Impacto:** Ruido, riesgo de subir datos de diagnóstico, disco.
- **Causa raíz:** Configuración de gradle/JVM + ausencia de cleanup.
- **Riesgo:** Bajo.
- **Solución:** Añadir a `.gitignore` y eliminar; mover artefactos a `build/`.
- **Dependencias:** —.
- **Prueba:** `git status` limpio de esos archivos.
- **Estado:** ABIERTO.

---

## P3 — MEJORA / DEUDA TÉCNICA

### Z-301 · Sin tests reales (cobertura ≈ 0)
- **Severidad:** P3
- **Archivo:** `test/widget_test.dart` (9 líneas, solo pump) · `test/load_test_simulator.dart` (43 líneas, sin asserts)
- **Problema:** El único test es una bomba de humo que pasa aunque el arranque falle (no valida estado); no hay tests de servicios, RLS, cripto, mesh ni sincronización.
- **Impacto:** Regresiones no detectables; impedimento para FASE 1 con confianza.
- **Solución:** Suite por servicio (crypto vectors, cola offline, sync, RLS contract) + widget tests de flujos críticos. `flutter test --coverage` objetivo >60%.
- **Dependencias:** FASE 1 (implementaciones).
- **Prueba:** CI ejecuta `flutter analyze && flutter test`.
- **Estado:** ABIERTO.

### Z-302 · Dependencias muy desactualizadas (69 upgradable, 17 fuera de rango, 4 discontinuadas)
- **Severidad:** P3
- **Archivo:** `pubspec.yaml`
- **Problema:** `flutter pub outdated`: 69 upgradables; 17 constreñidas a versiones fuera de rango (supabase_flutter 2.12→2.17, flutter_secure_storage 9→11, realtime_client, etc.); `flutter_secure_storage_macos`, `js`, `build_resolvers`, `build_runner_core` discontinuados; analyzer 5.x muy viejo.
- **Impacto:** Parches de seguridad ausentes; incompatibilidades futuras; IDE lints desactualizados.
- **Solución:** Plan de upgrade por paquetes (con tests), priorizando supabase, secure_storage y notificaciones.
- **Dependencias:** Z-301 (tests para validar).
- **Prueba:** `flutter pub outdated` limpio; suite verde tras upgrade.
- **Estado:** ABIERTO.

### Z-303 · `flutter analyze`: 15 issues (2 context async, 13 prints en scripts)
- **Severidad:** P3
- **Archivo:** `lib/screens/chats_list_screen.dart:228`, `lib/screens/donations_screen.dart:46`; `scripts/recolor.dart`, `tools/*.dart`
- **Problema:** Lints info de `use_build_context_synchronously` y `avoid_print`.
- **Impacto:** Riesgo menor; CI no puede exigir `--fatal-infos`.
- **Solución:** Guardar mounted; reemplazar prints por `debugPrint`/logger.
- **Dependencias:** Z-201.
- **Prueba:** `flutter analyze` sin findings (0 issues).
- **Estado:** ABIERTO (2 de ellos son Z-201 — informativos).

### Z-304 · Docs legales/README/SECURITY declaran capacidades no implementadas
- **Severidad:** P3 (riesgo legal)
- **Archivo:** `README.md`, `SECURITY.md`, `PRIVACY_POLICY.md`, `TERMS.md`, `CONTRIBUTING.md`
- **Problema:** Se afirman E2EE universal, Forward Secrecy, "grado industrial", datos cifrados en reposo, mitigaciones OWASP/Zero Trust. El código NO lo satisface en el estado actual (ver Z-003, Z-101, Z-002, Z-111).
- **Impacto:** Responsabilidad legal y reputacional (GDPR/ley 1581, "no vende datos", etc.).
- **Solución:** Reformular con lenguaje veraz ("en desarrollo"), condicionar a FASE 1+, añadir fechas y versiones; auditoría legal.
- **Dependencias:** FASE 1.
- **Prueba:** Revisión de docs contra el registro.
- **Estado:** ABIERTO — requiere decisión del dueño.

### Z-305 · Configuración por `.env` empaquetado (práctica débil)
- **Severidad:** P3
- **Archivo:** `initial_loading_screen.dart:33` · `pubspec.yaml` assets
- **Problema:** Incluso funcionando, re-empaquetar `.env` (con claves aunque publishable) en AAB/APK y manejar con `!` (bang) es frágil: cualquier fallo de load rompe el arranque sin fallback.
- **Solución:** Migrar a `--dart-define`/`String.fromEnvironment` con `const String.fromEnvironment` y defaults; `dotenv` solo para dev.
- **Dependencias:** Z-006.
- **Prueba:** Build release sin archivo `.env` en assets.
- **Estado:** ABIERTO.

### Z-306 · Permisos Android/iOS excesivos o sin justificar
- **Severidad:** P3
- **Archivo:** `android/app/src/main/AndroidManifest.xml` (CAMERA 23, READ_EXTERNAL_STORAGE 22 sin uso claro) · `ios/Runner/Info.plist`
- **Problema:** Se declaran permisos (cámara, almacenamiento) que el flujo actual no usa directamente (image_picker para avatar comparte picker no cámara); iOS sin strings de uso para social/photo.
- **Impacto:** Revisión de tiendas, percepciones de privacidad, superficie de ataque.
- **Solución:** Mínimo necesario; declarar solo lo usado; justificar en metadata.
- **Prueba:** `adb shell pm` / App Store review.
- **Estado:** ABIERTO.

### Z-307 · Código muerto y comentarios engañosos (sync bidireccional, RPCs sin uso)
- **Severidad:** P3
- **Archivo:** `sync_service.dart:28` (comentario "sync bidireccional"), `supabase_service.dart:636` (`getRadarStats` marcado "no llamado"), `verify_zone_id` sin uso (Z-103)
- **Problema:** Documentación interna contradice la implementación; funcionalidades retirables.
- **Solución:** Alinear comentarios/código; eliminar o completar.
- **Dependencias:** —.
- **Prueba:** Lint de dead_code y revisión.
- **Estado:** ABIERTO.

### Z-308 · Catches vacíos y `debugPrint` de depuración en producción
- **Severidad:** P3
- **Archivo:** `lib/**` (patrón `catch (e) { _logger.debug(...) }` y `catch (_) {}`)
- **Problema:** Muchos errores se capturan y solo se loguean a debug, ocultando fallos (Z-109, Z-105 son ejemplos de fallos silenciosos); prints de depuración en flujos críticos.
- **Solución:** Niveles de log con reporte/telemetría en release; decisiones de negocio ante fallo (retry, degradación visible).
- **Dependencias:** —.
- **Prueba:** Revisión de flujos con fallos silenciosos.
- **Estado:** ABIERTO.

---

## Estadísticas

| Severidad | Cantidad | IDs |
|-----------|----------|-----|
| P0 | 8 | Z-001 … Z-008 |
| P1 | 12 | Z-101 … Z-112 |
| P2 | 9 | Z-201 … Z-209 |
| P3 | 8 | Z-301 … Z-308 |
| **Total** | **37** | |

*Registro completo — auditoría FASE 0, sin correcciones aplicadas.*