# FASE H — Validación en dos dispositivos (Device A + Device B)

**Fecha:** 2026-10-23
**Estado:** matriz preparada. **No hay hardware disponible.**
**Ejecución física:** **NO REALIZADA** (no se simula evidencia).
**Beta:** **NO-GO**.

---

## 1. Comprobación de entorno (evidencia)

### 1.1 `adb devices`

```text
List of devices attached

ADB_EXIT=0
```

**Resultado:** cero dispositivos Android conectados.

### 1.2 `flutter devices`

```text
Found 2 connected devices:
  Windows (desktop) • windows • windows-x64 • Microsoft Windows 10.0.26200.7628
  Edge (web)        • edge    • web-javascript • Microsoft Edge 155.0.4283.62
```

**Resultado:** solo destinos de escritorio/web. Ninguno soporta BLE/Nearby
Connections ni representa un dispositivo físico Android.

### 1.3 `flutter emulators`

```text
No emulators available.
```

**Resultado:** no hay emuladores creados. Un emulador tampoco validaría BLE,
Wi-Fi Direct ni el comportamiento de radio de Nearby Connections, así que no se
usa como sustituto.

### 1.4 Conclusión

La matriz **no se puede ejecutar** en este host. Cualquier afirmación de
"validado en dos dispositivos" sería falsa. Los casos físicos quedan
**NOT RUN**.

---

## 2. Hardware y configuración requeridos

### 2.1 Dispositivos

| Rol | Requisito | Cantidad |
|---|---|---|
| Device A | Android físico, `minSdk 24`+, BLE + Wi-Fi Direct, Google Play Services | 1 |
| Device B | Android físico, `minSdk 24`+, BLE + Wi-Fi Direct, Google Play Services | 1 |
| Device C (solo H-06) | Android físico, mismo build | 1 |

Recomendado: al menos un Android 12+ y un Android 13+ para cubrir los permisos
`BLUETOOTH_*` y `NEARBY_WIFI_DEVICES`.

### 2.2 Permisos a conceder

- Ubicación precisa (`ACCESS_FINE_LOCATION`).
- Bluetooth: escanear, anunciar, conectar.
- Dispositivos Wi-Fi cercanos (Android 13+).
- Notificaciones (para receipts/avisos).
- Cámara/solo si el caso lo requiere (no en esta matriz).

### 2.3 Preparación

- [ ] Misma build (`flutter build apk --debug` o release firmado de prueba).
- [ ] Dos cuentas de prueba distintas (nunca cuentas reales).
- [ ] Batería sin optimización para ZONE en ambos.
- [ ] Bluetooth y Wi-Fi activados; ubicación activada.
- [ ] Reloj de ambos dispositivos sincronizado (afecta TTL de handshake).
- [ ] Registro de: modelo, versión de Android, build, hora, `adb logcat`.
- [ ] Captura de pantalla o vídeo por caso.
- [ ] No usar datos de usuarios reales.
- [ ] No aplicar migraciones ni cambios remotos durante la prueba.

---

## 3. Matriz de 15 casos

Leyenda de estado:

- **NOT RUN** — no ejecutado por falta de hardware.
- **AUTOMATED** — existe cobertura local de la lógica, pero **no** sustituye la
  prueba E2E.
- **KNOWN FAIL** — se espera que falle hasta que se cierre el P0 indicado.

| ID | Caso | Estado | Dependencia |
|---|---|---|---|
| H-01 | Descubrimiento BLE/Nearby bidireccional | NOT RUN | hardware |
| H-02 | Intercambio de perfil y derivación de clave | NOT RUN | hardware; Z-004 |
| H-03 | Match request/accept | NOT RUN (lógica AUTOMATED) | hardware |
| H-04 | Chat online vía Supabase | NOT RUN | hardware |
| H-05 | Chat offline vía mesh directo | NOT RUN (lógica AUTOMATED) | hardware |
| H-06 | Mesh a 2+ saltos con Device C | NOT RUN | 3 dispositivos |
| H-07 | Receipts enviado → entregado → leído | NOT RUN | hardware |
| H-08 | Outbox pendiente + reinicio | NOT RUN (lógica AUTOMATED) | hardware |
| H-09 | Reinstalación / login de usuario existente | NOT RUN | decisión Fase F |
| H-10 | Suplantación de ZONE-ID | NOT RUN — **KNOWN FAIL** | Z-004 / Fase G |
| H-11 | Usuario bloqueado no puede interactuar | NOT RUN | hardware |
| H-12 | Modo sigilo (stealth) | NOT RUN | hardware |
| H-13 | Visibilidad Z-212 (avatar/social) | NOT RUN (lógica AUTOMATED) | hardware |
| H-14 | Payload malformado/no-JSON se descarta | NOT RUN (lógica AUTOMATED) | hardware |
| H-15 | No reemplazo de `sk_` y reconexión | NOT RUN (lógica AUTOMATED) | hardware |

**Resultado físico:** 0/15 ejecutados. **No se declara ningún caso como PASS.**

---

## 4. Detalle de cada caso

### H-01 — Descubrimiento BLE/Nearby bidireccional

**Precondiciones:** A y B con la app abierta, permisos concedidos, Bluetooth y
Wi-Fi activos, radio encendida.

**Pasos:**
1. Abrir el radar en A y en B.
2. Esperar 30 s.
3. Comprobar que A ve a B y B ve a A.
4. Alejar un dispositivo y comprobar que desaparece tras el TTL.
5. Acercarlo y comprobar que reaparece.

**Esperado:** descubrimiento mutuo, sin duplicados, con desaparición/reaparición
coherente.

**Evidencia:** captura de ambos radares, `logcat` con endpoints, hora.

---

### H-02 — Intercambio de perfil y derivación de clave

**Precondiciones:** H-01 OK; ambos con perfil.

**Pasos:**
1. Tocar la tarjeta del peer para iniciar conexión.
2. Verificar que el perfil remoto aparece (nombre, zona, avatar según
   visibilidad).
3. En `logcat`, confirmar que se deriva una sesión (`sk_<zoneId>`) sin errores.
4. Comprobar que el `endpointId` **no** se usa como Zone ID.

**Esperado:** perfil correcto, sesión derivada, sin exponer claves en logs.

**Riesgo conocido:** el `profile_exchange` actual **no está firmado** (Z-004). El
caso puede "pasar" funcionalmente y seguir siendo inseguro; se registra como
funcional, no como seguridad.

---

### H-03 — Match request/accept

**Precondiciones:** H-01/H-02 OK.

**Pasos:**
1. A envía solicitud de match a B.
2. B la recibe y acepta.
3. Ambos abren el chat.
4. Repetir la solicitud (idempotencia).

**Esperado:** un solo match, estado `accepted`, sin duplicados, chat disponible
en ambos.

**Cobertura local:** `test/match_outbox_test.dart` (idempotencia, convergencia,
accept/reject offline). No sustituye la prueba de radio.

---

### H-04 — Chat online vía Supabase

**Precondiciones:** match aceptado; ambos con Internet.

**Pasos:**
1. A envía "hola online".
2. B lo recibe y responde.
3. Verificar en Supabase que `encrypted_content` no contiene el texto claro.
4. Comprobar que ambos descifran correctamente.
5. Reabrir el chat y verificar el historial.

**Esperado:** mensajes cifrados en tránsito/DB, descifrado correcto, historial
consistente.

**Riesgo conocido:** la clave pública viene de Supabase sin verificación
(Fase G); el caso valida funcionalidad, no autenticidad.

---

### H-05 — Chat offline vía mesh directo

**Precondiciones:** match aceptado; **Wi-Fi/ datos apagados** en ambos; peers
alcanzables por Nearby.

**Pasos:**
1. A envía "hola mesh".
2. B lo recibe.
3. B responde.
4. Comprobar que no se envió texto claro.
5. Verificar que el mensaje se encola si no hay clave.

**Esperado:** entrega cifrada por mesh, sin texto claro, cola si falta clave.

**Cobertura local:** `test/mesh_policy_test.dart` (fail-closed, packet
validation, dedup). No sustituye la prueba de radio.

---

### H-06 — Mesh a 2+ saltos con Device C

**Precondiciones:** A, B y C; A y C fuera de alcance directo; B en medio.

**Pasos:**
1. A envía a C.
2. B relay-a el paquete.
3. C lo recibe y descifra.
4. Repetir con un paquete no cifrado (debe descartarse).
5. Medir latencia y pérdida.

**Esperado:** entrega a 2 saltos, relay solo de paquetes cifrados, sin bucles.

**Riesgo conocido:** el mesh confía en `source` (Z-004); un relay malicioso
puede intentar inyectar. Se registra.

---

### H-07 — Receipts enviado → entregado → leído

**Precondiciones:** H-04 OK.

**Pasos:**
1. A envía un mensaje.
2. B lo recibe (tick entregado).
3. B abre el chat (tick leído).
4. A verifica ambos ticks.
5. Repetir offline y al reconectar.

**Esperado:** transiciones correctas, sin retroceder, sin marcar leído antes de
ver.

**Cobertura local:** RPCs `mark_messages_delivered` / `mark_messages_read`
validadas en SQL; falta E2E.

---

### H-08 — Outbox pendiente + reinicio

**Precondiciones:** H-03 OK; sin red.

**Pasos:**
1. A envía un mensaje sin red.
2. Cerrar la app por completo.
3. Reabrir y reconectar.
4. Verificar que se envía una sola vez, con el mismo `messageId`.

**Esperado:** sin duplicados, sin pérdida, reintento con backoff.

**Cobertura local:** `test/match_outbox_test.dart` (idempotencia, respuesta
perdida, reintentos). No sustituye la prueba de proceso real.

---

### H-09 — Reinstalación / login de usuario existente

**Precondiciones:** A con cuenta; desinstalar y reinstalar; B conserva su cuenta.

**Pasos:**
1. Reinstalar A.
2. Intentar "Entrar A Mi Zone" con el ZONE-ID de A.
3. Registrar el mensaje mostrado.
4. Si Fase F elige A, probar recovery + `register_device`.
5. Si Fase F elige B, verificar que la UX comunica "cuenta nueva".

**Esperado hoy:** bloqueo explícito de migración (no takeover, no split-brain).

**Estado:** depende de la decisión de Fase F. No se puede marcar PASS.

---

### H-10 — Suplantación de ZONE-ID

**Precondiciones:** A víctima, B atacante; B conoce el ZONE-ID de A.

**Pasos:**
1. B intenta anunciarse como A en `profile_exchange`/`source`.
2. B intenta establecer sesión con la clave X25519 de B.
3. A intenta enviar/recibir un mensaje.
4. Verificar si A acepta la identidad falsa.

**Esperado (objetivo):** A rechaza al peer; no se establece sesión; no se
inyecta mensaje.

**Estado actual:** **KNOWN FAIL**. El código de `HEAD` no autentica el
`profile_exchange` ni el `source`; B puede suplantar. Este caso debe fallar hasta
que Fase G integre el handshake. **No se debe reportar como PASS.**

---

### H-11 — Usuario bloqueado no puede interactuar

**Precondiciones:** A y B con match; A bloquea a B.

**Pasos:**
1. B intenta enviar mensaje a A.
2. B intenta solicitar match.
3. A abre el radar/chat.
4. Verificar RLS y UI.

**Esperado:** B no puede enviar ni crear match; A no ve contenido de B; sin
errores 42501 anómalos.

---

### H-12 — Modo sigilo (stealth)

**Precondiciones:** A activa `stealth_mode`.

**Pasos:**
1. B abre el radar.
2. Verificar que A no aparece.
3. A intenta iniciar match con B (si el producto lo permite).
4. Desactivar sigilo y comprobar reaparición.

**Esperado:** A oculto en radar; comportamiento de match según producto; sin
fugas por mesh.

---

### H-13 — Visibilidad Z-212 (avatar/social)

**Precondiciones:** A con `avatar_is_public=false`, `ig_visible=false`,
`fb_visible=false`, `tiktok_visible=false`.

**Pasos:**
1. B recibe el `profile_exchange` de A.
2. Verificar que avatar/IG/FB/TikTok llegan como `null` o ausentes.
3. Cambiar los flags a `true` y repetir.
4. Verificar `verify_zone_id`/`v_profile`.

**Esperado:** los datos privados no se difunden por radio ni se devuelven por
RPC.

**Cobertura local:** validadores de visibilidad y SQL Z-212; falta E2E.

---

### H-14 — Payload malformado/no-JSON se descarta

**Precondiciones:** cliente de prueba o peer modificado.

**Pasos:**
1. Enviar un payload no-JSON.
2. Enviar JSON sin `type`.
3. Enviar `profile_exchange` con `zone_id` no canónico.
4. Enviar paquete mesh con `isEncrypted=false`.
5. Enviar `msgId` no UUID / `hops` fuera de rango.

**Esperado:** descarte silencioso y fail-closed; sin crash; sin texto claro.

**Cobertura local:** `test/discovery_readiness_test.dart`,
`test/mesh_policy_test.dart` (validadores). Falta el transporte real.

---

### H-15 — No reemplazo de `sk_` y reconexión

**Precondiciones:** sesión existente entre A y B.

**Pasos:**
1. Establecer sesión y enviar un mensaje.
2. Forzar reconexión de Nearby.
3. Verificar que `sk_<zoneId>` **no** se reemplaza por una clave nueva.
4. Comprobar que los mensajes siguen descifrando.
5. Simular un peer que envía otra `publicKey` (debe rechazarse/no reemplazar).

**Esperado:** la sesión existente se conserva; no hay downgrade silencioso.

**Cobertura local:** lógica de no reemplazo en `nearby_service.dart` y tests de
política; falta E2E.

---

## 5. Subconjunto automatizable ejecutado en este host

Aunque no sustituye la matriz física, se ejecutó la lógica que sí es verificable
sin radio:

```powershell
flutter test --no-pub `
  test/discovery_readiness_test.dart `
  test/mesh_policy_test.dart `
  test/encounter_idempotency_test.dart `
  test/match_outbox_test.dart `
  test/sql_security_regression_test.dart `
  test/android_release_signing_test.dart
```

**Resultado:** `+89: All tests passed!` (`TARGETED_EXIT=0`).

Cubre:

- H-03/H-08: idempotencia y outbox.
- H-05/H-14: mesh fail-closed, validación de paquetes y rutas.
- H-13: validadores de visibilidad.
- H-15: política de no reemplazo (lógica).
- SQL Z-212 y firma release como guardas estáticas.

**No cubre:** BLE, Nearby, Wi-Fi Direct, permisos reales, latencia, pérdida de
paquetes, recepción en segundo plano, ni comportamiento entre dos dispositivos.

---

## 6. Criterios de entrada y salida

### 6.1 Entrada

- [ ] Dos Android físicos disponibles.
- [ ] Build instalable (debug o release de prueba).
- [ ] Cuentas de prueba.
- [ ] Permisos y batería configurados.
- [ ] Relojes sincronizados.
- [ ] Procedimiento de captura de evidencia.

### 6.2 Salida

- [ ] H-01 a H-09, H-11 a H-15 ejecutados con evidencia.
- [ ] H-10 ejecutado y **fallando** hasta Fase G (documentado).
- [ ] Sin crashes ni fugas de claves en logs.
- [ ] Resultados adjuntos a este documento.
- [ ] Actualización de `BETA_READINESS_GATE.md`.

---

## 7. Limitaciones y honesty statement

- No hay dispositivos Android conectados.
- No hay emuladores.
- No se ha simulado ninguna captura, log ni resultado físico.
- Los 89 tests locales prueban lógica, no radio.
- H-10 se espera **FAIL** por Z-004; no se puede cerrar con la build actual.
- H-09 depende de la decisión de Fase F.

**Por tanto:** la validación en dos dispositivos sigue **NOT VERIFIED** y el gate
sigue **NO-GO**.

---

## 8. Referencias

- `docs/audit/BETA_READINESS_GATE.md` P0-6.
- `test/discovery_readiness_test.dart`.
- `test/mesh_policy_test.dart`.
- `test/encounter_idempotency_test.dart`.
- `test/match_outbox_test.dart`.
- `test/sql_security_regression_test.dart`.
- `test/android_release_signing_test.dart`.
- `lib/services/nearby_service.dart`.
- `lib/services/discovery_policy.dart`.
- `lib/services/mesh_policy.dart`.
