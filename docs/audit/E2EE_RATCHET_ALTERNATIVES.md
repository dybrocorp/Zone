# E2EE · Comparación de alternativas para el ratchet (Decisión de componente)

**Fecha:** 2026-10-27
**Estado:** propuesta técnica revisable. **No se cambia ningún formato
criptográfico ni se migra nada.** El gate de beta sigue **NO-GO** y Z-101
sigue **ABIERTO**.
**Insumo:** `docs/audit/PHASE_G_E2EE_KEY_ESTABLISHMENT.md` (riesgo §9:
"Implementar Double Ratchet desde cero vs librería revisada — requiere
decisión").
**Decisión requerida:** CTO (aprobación de ruta + presupuesto de revisión).

---

## 1. Qué debe resolver la decisión

La Fase G exige forward secrecy y PCS para afirmar "E2EE con forward
secrecy". El diseño v3/v4 (`PHASE_G` §4-§5) usa las primitivas ya aprobadas
(Ed25519, X25519, HKDF-SHA256, ChaCha20-Poly1305, SHA-256; decisiones D1/D2)
y ya está implementado el AKE de dos mensajes (`ZONE-P2P-AKE-1`). Falta el
**ratchet** y la pregunta es: ¿terceros o propio?

Mandatos que acotan la búsqueda:

- **No criptografía propietaria improvisada**: la capa de composición debe
  seguir especificaciones publicadas y ser verificable; las primitivas
  siguen siendo de una librería mantenida.
- **Compatibilidad**: historial v1 existe y se conserva; no se re-cifra ni
  se re-escribe nada (`I-025`, Fase G §6.2).
- **Plataforma**: Android/iOS por Flutter, validación en Windows; BLE mesh
  con mensajes pequeños (payload acotado).
- **Licencia**: app propietaria de DYBROCORP. Copyleft fuerte (GPL-3.0 /
  AGPL-3.0) en un componente enlazado obligaría a discutir liberación de
  código de la app: es un bloqueo jurídico, no técnico.

---

## 2. Candidatas investigadas (evidencia del 2026-10-27)

Búsqueda en pub.dev + repositorios; se registra fecha/estado de cada fuente.
No asumimos que "existe el paquete" por su nombre: cada fila se verificó en
su fuente.

| # | Candidata | Qué es | Licencia | Mantenimiento/evidencia | Encaje con Zone |
|---|---|---|---|---|---|
| 1 | `libsignal_protocol_dart` 0.8.2 | Pure Dart Signal Protocol (X3DH + Double Ratchet + SenderKey) | **GPL-3.0** | pub.dev, publisher verificado `mixin.dev`, publicado **2026-06-20**, 16.4k descargas, 67 likes, 150 puntos, CI activa | Funcionalmente encaja; licencia copyleft **incompatible** para una app propietaria salvo decisión legal; identidades Ed25519 de Signal ≠ modelo D1/D2 de Zone; no auditado públicamente |
| 2 | `libsignal` 9.0.0 | Wrapper Dart del libsignal **Rust** oficial (flutter_rust_bridge) | **AGPL-3.0** | pub.dev, publicado **2026-10-26**, 1.58k descargas, 4 likes | Protocolo de referencia (más fuerte), pero AGPL peor todavía; exige toolchain Rust por plataforma y binarios nativos por build; no auditado por Dybrocorp; complejidad de build/CI alta |
| 3 | `omemo_dart` | X3DH + Double Ratchet con semántica OMEMO 0.8.3 (XMPP) | MIT | Repositorio `PapaTutuWawa/omemo_dart` (18 estrellas, 1 watcher); **no está en pub.dev** (se instala desde un host propio del autor: `git.polynom.me/.../pub`) | El propio README advierte: "**not been audited**", "not tested with other implementations — works with **itself**"; mantenida por una persona; modelo orientado a JID/OMEMO (devices XMPP), encaje parcial |
| 4 | `double_ratchet` 0.2.1 | X3DH + Double Ratchet en Dart puro, MIT | MIT | pub.dev: **creado hace 2 días** (0 descargas, 0 likes, sin adopción verificable) | Inmadura: sin historial de seguridad ni adopción; riesgo de composición sin revisión |
| 5 | `cyphermask` 0.0.1 / `chat_secure_guard` 0.0.2 / `azproto` 1.0.0 / `pq_aura_flutter` 0.1.0 | Mini-librerías / toolkits con "ratchet simple" o FFI nativo | varias | Descargas de orden decenas/cientos; sin auditoría ni adopción relevante | No candidatas serias; documentación insuficiente; FFI añade superficie nativa |
| 6 | libsignal oficial (Signal) | Implementación de referencia (Rust/Java/Swift/JS) | AGPL-3.0 / otros | Muy mantenida (Signal) | **Sin binding Dart oficial**; consumirla vía (2) vuelve a la fila 2 |
| 7 | Propia, según spec publicada (`PHASE_G` §5) | Double Ratchet (Signal spec) + AKE ya implementado como módulo de primera parte sobre `cryptography` | n/a (código propio) | Primitivas de `cryptography` (ya en pubspec, con KATs propias posibles); especificación de protocolo pública; tests de FS/PCS mandatorios | Licencia libre de conflicto; encaje total con D1/D2 y AKE existente; **riesgo de error de implementación alto — obliga revisión externa antes de afirmar FS** |

### 2.1 Primitivas (no en duda)

`cryptography` 2.9.0 (ya dependencia directa) provee HKDF-SHA256, X25519,
Ed25519 y ChaCha20-Poly1305 probadas por el proyecto con 126 tests de
identidad y KATs de fingerprint. La decisión aquí **no toca las primitivas**:
decide la capa de composición (ratchet + key schedule + state machine).

---

## 3. Veredicto y recomendación

**No existe hoy un paquete Dart mantenido, con garantías documentadas,
licencia compatible con la app propietaria y encaje con el modelo de
identidad aprobado.** Con la lista de la §2, la denominación "usar una
librería del Signal Protocol en Dart" termina siempre en (1) copyleft
incompatible o (2) bindings Rust/AGPL, y las MIT (3/4) son no-auditadas sin
adopción.

**Recomendación (obligatoria de revisar por el CTO):**

1. **Ruta principal (propuesta):** implementar el ratchet como **módulo de
   primera parte**, siguiendo las specs publicadas de Signal (Double Ratchet
   + establecimiento vía `ZONE-P2P-AKE-1` cuya analogía X3DH ya está
   especificada en Fase G §4), sobre las primitivas del paquete
   `cryptography`, con la cadena de obligaciones siguiente:
   - tests KAT de primitivas (RFC 5869/8439/7748/8032) **ante cada versión**
     que se toque;
   - la matriz de seguridad de `PHASE_G` §7 (FS/PCS/out-of-order/replay/AAD/
     persistencia/recovery) en verde antes de integrar;
   - estado del ratchet solo en SecureStorage, nunca en Isar plano/Supabase;
   - **revisión externa de seguridad del módulo** (no declarable por
     auto-read) antes de publicar a usuarios reales; sin ella, el gate
     prohibe la afirmación "forward secrecy" (igual regla de la §5 del gate).
2. **Ruta alternativa (solo con decisión legal de producto):** adoptar
   `libsignal_protocol_dart` si DYBROCORP libera la app bajo GPL-3.0 o
   compra/isola licencia; incorpora riesgo de mantener un fork alineado al
   modelo D1/D2. El wrapper Rust (2) se descarta de facto por AGPL + coste
   de infraestructura y compatibilidad de flujos offline mesh.
3. **Excluirse de facto:** 3/4/5 no cumplen el mínimo de madurez; si el
   ecosistema cambia (p. ej. omemo_dart publicado/auditado), se re-evalúa con
   este mismo documento como base.

**Registro honesto:** la ruta principal contiene código criptográfico propio
a nivel de **protocolo** (no de primitiva), y por tanto debe tratarse como
riesgo alto hasta revisión externa. No afirmar FS en ninguna pieza de
usuario/documentación de marketing sin esa revisión + tests verdes + AKE
cableado.

---

## 4. Parámetros justificados para el diseño (insumo de Fase G §5.4/§6)

Propuestas explícitas — se justifican antes de fijarlos; **los valores de
TTL/límites NO se fijan automáticamente** ("no selecciones valores de TTL sin
justificar el impacto"):

| Parámetro | Propuesta | Justificación (seguridad/offline) | Costo de revisar |
|---|---|---|---|
| Ventana de skipped keys | **2000 claves/sesión** | Zona es offline-first con BLE: un peer fuera de radio varios días debe poder recibir y descifrar al volver sin re-negociar. 2000 ≈ margen holgado para mensajería 1:1. Costo acotado: ≈ 2000 × (32 B de clave + índices) ≈ 96 KiB por conversación; daño de ventana abierta: un atacante con estado de sesión viejo solo descifra dentro de la ventana | Bajarla puede convertir reconexiones tarde en mensajes "ilegibles" en beta; subirla amplía la superficie de claves almacenadas |
| TTL de skipped keys | **7 días** | Alineado con la cadencia offline esperada del producto (fin de semana/camping/sin datos >24h); reduce la ventana arqueológica si el dispositivo se pierde sin recovery emitido; coincide con el ciclo realista de "leer el backlog" | TTL corto (24h) rompe el caso real "reconecto el domingo"; TTL largo (30d) aumenta la exposición del material de reserva |
| TTL de claves de sesión pendientes (handshake iniciado sin respuesta) | **10 min** (= TTL del `hello`) | Un handshake pendiente debe caducar a la vez que el `hello` firmado; evita `session_id` sin uso que retrospección alguna capture | — |
| Rechazo de reuso | message key de un solo uso; replay por contador estricto por dirección | cuerpo de la spec Signal; sin excepciones de compatibilidad | — |
| Re-negociación | session_id nuevo con AKE reiniciado cuando la conversación excede la ventana con mensajería real en tránsito | UX documentada ("reenvía"), no fallback silencioso | — |

Estos valores los **firma el CTO** antes de implementar (aunque la
implementación los use "por defecto", no son automáticos).

---

## 5. Plan de migración (refuerzo de PHASE_G §6) — sin ejecutar

Además de los pasos ordenados en `PHASE_G` §6.6 (corrección del comentario
falso → v2 HKDF+AAD → v3 AKE+transcript → v4 ratchet → unificación cloud/mesh
→ multi-device), el plan migratorio añade estas condiciones de control (sin
cambiar el orden, sin ejecutar nada hoy):

1. **Nada de formato cambia antes de que todas las condiciones de
   recuperación/compatibilidad estén documentadas** esa es la regla
   anti-migración precipitada: `crypto_version` explicitado por mensaje
   (`PHASE_G` §6.3/§6.4), `messages` alterado solo con migración autorizada
   (mismo proceso que Z-212) y con `nullable` para filas v1 sin reescritura.
2. **Compatibilidad v1 incondicional mientras exista historial** descifrado
   local; no existe conversión retroactiva de la clave v1 a ninguna versión
   nueva.
3. **Mensaje v1 ilegible tras un cutover nunca queda "silencioso":** la UI ya
   usa placeholder 🔒 (`chat_e2ee_service.dart:105-109`), que se reutiliza
   como estado tipado, no como excepción silente.
4. **Downgrade prohibitivo:** la versión se firma en el transcript del AKE y
   viaja en el AAD (`PHASE_G` §6.3): un peer v3 que acepte v1 solo mediante
   re-negociación explícita y aprobada; jamás fallback automático.
5. **Rollback documentado:** revertir feature flags **no** baja el formato de
   los mensajes una vez escritos en v2+; un rollback solo desactiva la
   creación de mensajes nuevos en v2+, dejando los existentes descifrables.

---

## 6. Decisión solicitada (para el registro CTO)

1. ¿Se aprueba la **ruta 1 (módulo propio según specs publicadas)** con las
   obligaciones de §3.1 (KATs, matriz de seguridad, revisión externa)?
2. ¿Se aceptan los parámetros §4 (2000 / 7 días / 10 min) como firma del
   diseño oficial, o se ajustan con argumento documentado?
3. ¿Se autoriza la fase de implementación v2 (HKDF+AAD sobre la infraestructura
   de Fase E, sin tocar historial v1), sujeta a staging y dos dispositivos?
4. ¿Se registra explícitamente el bloqueo de licencia de la ruta 2 (GPL-3.0)
   como no aplicable mientras la app siga siendo propietaria?

**Sin esa firma: sin implementación alguna. Afirmaciones prohibidas
(actualizadas)**: "ZONE tiene E2EE con forward secrecy" / "Forward Secrecy
implementado" hasta: ratchet implementado + matriz de seguridad `PHASE_G` §7
en verde + (para el copy público) revisión externa + AKE cableado a Nearby.

## 7. Referencias (verificadas 2026-10-27)

- `libsignal_protocol_dart` en pub.dev (página consultada; GPL-3.0; 0.8.2 /
  2026-06-20): https://pub.dev/packages/libsignal_protocol_dart
- `libsignal` (wrapper Rust) en pub.dev (9.0.0 / AGPL-3.0 / 2026-10-26):
  https://pub.dev/packages/libsignal
- `omemo_dart` (repositorio; MIT; advertencia de no-auditado en el README;
  GitHub como espejo, fuente canónica en Codeberg):
  https://github.com/PapaTutuWawa/omemo_dart
- `double_ratchet` en pub.dev (0.2.1 / 2026-10-27): https://pub.dev/packages/double_ratchet
- Specs de referencia: Double Ratchet y X3DH
  (https://signal.org/docs/specifications/doubleratchet/ ,
  https://signal.org/docs/specifications/x3dh/)
- Internas: `docs/audit/PHASE_G_E2EE_KEY_ESTABLISHMENT.md`,
  `docs/PHASE_2_CRYPTO_DECISIONS.md` (D1/D2),
  `docs/audit/PHASE_E_P2P_AUTH_DESIGN.md`.
