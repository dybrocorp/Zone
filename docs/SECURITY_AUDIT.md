# SECURITY_AUDIT — Auditoría de Seguridad · ZONE (FASE 0)

> Clasificación: P0..P3. Referencias a IDs del `BUG_REGISTER.md`.
> Ninguno corregido todavía. Verificaciones marcadas como REQUIERE VALIDACIÓN cuando no se pudo confirmar contra la DB remota.

---

## 1. Resumen

| Área | Estado | Hallazgos críticos |
|---|---|---|
| Identidad / Login | 🔴 | Z-001, Z-103, Z-207 |
| RLS / Filtrado servidor | 🔴 | Z-002, Z-206 |
| Mesh P2P | 🔴 | Z-003, Z-004, Z-005 |
| Cripto | 🟠 | Z-101, Z-102 |
| Storage | 🟠 | Z-111, Z-204 |
| Premium/Pagos | 🔴 | Z-008 |
| Plataforma | 🟠 | Z-006 (bloqueo), Z-110 (push) |

---

## 2. Vectores de ataque principales

### 2.1 Robo de cuenta por reclamación de `zone_id` (Z-001) — CRÍTICO
- La credencial de login es un código de 8 caracteres `A-Z0-9` (~41 bits de entropía).
- `claim_zone_id(p_zone_id)` es `SECURITY DEFINER`, GRANT a `authenticated` **y `anon`**, y mueve `users.id` al `auth.uid()` de quien lo invoca sin prueba de posesión.
- **Demostración:** `select * from public.rpc('claim_zone_id', '{"p_zone_id":"<ID_OBJETIVO>"}')` desde la API con un JWT anónimo.
- **Agravante:** `loginWithExistingID` acepta cualquier ID; `verify_zone_id` (Z-103) permite confirmar existencia y obtener el `uid` para encadenar el ataque.
- **Mitigación requerida (FASE 1):** challenge-response firmado con la clave privada local + comparación contra `users.public_key`; prohibir GRANT a anon; rate-limit.

### 2.2 Exfiltración masiva de datos personales vía RLS (Z-002) — CRÍTICO
- `SELECT` any authenticated → todas las columnas de todos los `users` no shadowbanned.
- Datos expuestos: `instagram_handle`, `facebook_handle`, `tiktok_handle`, `gallery_photos`, `public_key`, `avatar_url`, `reports_count`, `stealth_mode`.
- Los flags `*_visible` se aplican SOLO en el cliente (`supabase_service.dart:73-78` filtra client-side).
- **Mitigación:** Vistas/RPC que devuelvan NULL server-side según flags y bloqueos; revocar `SELECT` amplio.

### 2.3 RPC `SECURITY DEFINER` mal graneados (Z-103, Z-104)
- Tres funciones `SECURITY DEFINER` (verify_zone_id, resolve_bt_token, claim_zone_id) con `GRANT EXECUTE ... TO anon`.
- `resolve_bt_token` no consume el token (`used` nunca se marca) → reuso; idéntico texto en schema y deploy.
- **Mitigación:** GRANT solo a authenticated; consumo único; expiración corta.

### 2.4 Mesh en claro y spoofing (Z-003, Z-004, Z-005)
- Sin llave de sesión → `text` viaja en claro con `isEncrypted: false`, reenviado a todos los vecinos (flood).
- `_onConnectionInitiated` acepta toda conexión (Z-004) y `source` es un string no verificado.
- `msgId` = milisegundos epoch → colisiones y replay tras limpiar `_seenMessageIds`.
- **Mitigación:** fail-closed + handshake firmado Ed25519 + IDs únicos + dedup LRU.

---

## 3. Gestión de secretos

- **Git history:** escaneo `-S`/`-G` de `service_role`, `sb_secret`, JWTs (`eyJ...`), `.env`, `.key`, `secret`, `password`, `private_key`, `api_key`, `token` → **sin hallazgos de claves privadas**.
- **✓ Correcto:** `.env` está en `.gitignore` (línea 35).
- **✗ Hallazgo:** `test/load_test_simulator.dart:7-8` (trackeado) contiene URL y anon key **publishable de OTRO proyecto Supabase** (`leejpxwctnubihacudik.supabase.co`) — Z-203.
- **⚠ Práctica débil:** `.env` empaquetado en el APK/AAB cuando se incluye en assets (Z-305). Contiene solo claves publishable del proyecto actual (no crítica, pero evitable).

---

## 4. Verificaciones con estado "REQUIERE VALIDACIÓN"

| Ítem | Estado | Nota |
|---|---|---|
| `.env` elimina asset → `FileNotFoundError` en arranque | **CONFIRMADO** (test: `[Startup] ERROR CRÍTICO: FileNotFoundError`) | Z-006 |
| ¿Parches DB aplicados en el proyecto remoto (`updated_at`, `get_active_users_for_radar`, `mark_messages_read`…)? | **NO VERIFICABLE desde el repo** | Z-105, Z-109 |
| ¿Existe la columna `updatedAt` camelCase en la DB real? | **NO VERIFICABLE** | Z-108 |
| `claim_zone_id` → ¿la DB real rechaza `p_public_key`? | **Esperado** (firma de un solo parámetro en ambos SQL del repo) | Z-001 |

---

## 5. Prioridades de remediación de seguridad (orden sugerido)

1. **Z-006** — Bloqueo de arranque (para que cualquiera de las demás tenga efecto observable).
2. **Z-001 / Z-103 / Z-207** — Identidad: reclamación segura, revocar anon.
3. **Z-002 / Z-206** — RLS y policies (fuga de datos + UPDATE de mensajes).
4. **Z-003 / Z-004 / Z-005** — Mesh: fail-closed + handshake + IDs.
5. **Z-104 / Z-111** — Tokens BT consumibles y storage privado.
6. **Z-008** — Premium server-verified.
7. **Z-101 / Z-102** — Cripto: ratchet/FS y gestión de identidad.
8. Los demás P1/P2/P3 en orden del `REMEDIATION_PLAN.md`.

---
*Documento generado en auditoría FASE 0. No modifica código.*