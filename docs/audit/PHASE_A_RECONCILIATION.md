# FASE A — Reconciliación del estado real (ZONE)

**Fecha:** 2026-10-23
**Repositorio:** `D:\Proyectos\Zone`
**Rama:** `main`
**HEAD:** `7f59b776c62cc131fd05dc999e99cbb7804385e8`
**Alcance:** inspección local, pruebas estáticas y SQL en PostgreSQL aislado. **No** se accedió a staging/producción, **no** se aplicaron migraciones remotas y **no** se hizo commit/push.

---

## 1. Método

1. Se verificó ruta, rama, HEAD, `git status --short` y `git diff --stat` antes de editar.
2. Se leyeron los informes de auditoría, `BUG_REGISTER.md`, el esquema canónico, el deploy, Z-212 y todas las migraciones históricas.
3. Se buscaron rutas alternativas: `UPDATE/INSERT/DELETE` sobre tablas sensibles, funciones `SECURITY DEFINER`, grants a `anon`/`PUBLIC`, políticas amplias y funciones que escriben columnas protegidas.
4. Se añadió un guard estático (`test/sql_security_regression_test.dart`) que lee los SQL reales y falla si reaparece el claim inseguro o una política Z-212.
5. Se extendió el harness SQL (`supabase_migrations/tests/z212_behavioral_test.sql`) para re-aplicar las migraciones históricas después de Z-212 y comprobar que no regresan.
6. Se ejecutó el harness en un clúster PostgreSQL 18.4 desechable.

---

## 2. Tabla de reconciliación

| # | Afirmación | Evidencia actual | Resultado | Discrepancia | Acción necesaria |
|---|------------|------------------|-----------|--------------|------------------|
| 1 | Z-001: `claim_zone_id` permitía account takeover | Antes de esta fase, `secure_claim_zone_id.sql`, `z002_profile_visibility.sql`, `supabase_schema.sql` y `supabase_deploy.sql` ejecutaban `UPDATE public.users SET id = auth.uid()` sin prueba de posesión. | **P0 confirmado.** El código contradecía el estado `REMOTE_APPLIED + VERIFIED` del registro. | `BUG_REGISTER.md` sobreafirmaba la verificación: cubría ACL/rate-limit, no posesión. | Estado corregido en el registro. Claim en cuarentena local. Validar en staging (Fase B). |
| 2 | El claim está deshabilitado fail-closed | `supabase_schema.sql:743-756`, `supabase_deploy.sql:187-205`, `z212_security_hardening.sql:26-45`, `secure_claim_zone_id.sql:87-91`, `z002_profile_visibility.sql:158-163` lanzan `Reclamo de ZONE-ID deshabilitado temporalmente por seguridad (Z-212).` | **PASS local.** | Ninguna. | Aplicar Z-212 en staging con autorización; probar con JWT real. |
| 3 | No queda ninguna ruta ejecutable que reescriba `users.id` | `test/sql_security_regression_test.dart` recorre esquema, deploy y todas las migraciones, ignora comentarios y falla ante `UPDATE ... users ... SET ... id =`. Resultado: 4/4 PASS. | **PASS local.** | Ninguna. | Mantener el guard en CI. |
| 4 | Las migraciones históricas no reintroducen el claim | `secure_claim_zone_id.sql` y `z002_profile_visibility.sql` fueron endurecidas: si se re-aplican instalan la cuarentena, no el `UPDATE`. El guard estático lo verifica. | **PASS local.** | Los archivos históricos describían el comportamiento antiguo; se anotaron como `SUPERSEDED`. | No re-aplicar sin Z-212; el staging debe usar el inventario de Fase B. |
| 5 | `bt_tokens` ya no expone el mapping token→usuario | `supabase_schema.sql:443-456` y `supabase_deploy.sql:523-533` eliminan la política amplia `"Resolver token BT"`; solo queda `"Ver propio token"` (`auth.uid() = user_id`). `resolve_bt_token` exige `auth.uid()` y filtra avatar/handles (`supabase_schema.sql:811-850`). | **PASS local.** | `fix_radar_bilateral.sql` recreaba la política amplia y una RPC sin gate; era una ruta de regresión real. | Archivo histórico endurecido: ahora elimina la política y reinstala la RPC segura. Validar RLS/JWT en staging. |
| 6 | `messages` no admite UPDATE directo de contenido | `supabase_schema.sql:519-572` no crea política UPDATE; el trigger `enforce_message_immutable_columns` bloquea `id`, `match_id`, `sender_id`, `encrypted_content`, `nonce`, `mac`, `created_at`; los receipts van por RPC Z-007. | **PASS local.** | `z106_z206_policies.sql` recreaba la política UPDATE; era una ruta de regresión. | Archivo histórico endurecido: elimina la política y verifica su ausencia. Probar receipts RPC en staging. |
| 7 | `matches` no permite reescribir el par ni degradar un accepted | `supabase_schema.sql:482-517`: `WITH CHECK (auth.uid() = receiver_id)` + trigger que bloquea `id`/`requester_id`/`receiver_id`/`created_at` y accepted→otro estado. | **PASS local.** | Ninguna. | Probar con dos JWT reales en staging (receiver vs tercero). |
| 8 | Las columnas protegidas de `users` están protegidas | `supabase_schema.sql:241-269`: trigger `enforce_user_protected_columns` bloquea `id`, `zone_id`, `reports_count`, `is_shadowbanned`, `created_at` para `authenticated`; `service_role` y el flag transaccional de moderación conservan la escritura administrativa. | **PASS local, con residual.** | `is_premium` no está en la lista protegida; si la columna existe, un usuario podría auto-asignársela vía UPDATE de su fila (Z-008). | Decidir en Fase F/Producto si se protege `is_premium` y se aplica enforcement server-side de Premium. No cambiar a ciegas: la columna no está en el esquema canónico. |
| 9 | El flag de moderación tiene autorización adecuada | Solo `handle_new_report()` ejecuta `set_config('zone.allow_protected_user_write','1', true)`; la función es `SECURITY DEFINER`, está revocada de `PUBLIC/anon/authenticated` y solo se invoca como trigger de `reports`. El flag es transaction-local. | **Aceptable local.** | Un rol con SQL directo podría fijar el GUC; queda fuera de la superficie PostgREST y requiere credenciales de base de datos. | Verificar en staging que `authenticated` no puede ejecutar `handle_new_report` ni `set_config` vía API. |
| 10 | `verify_zone_id` no es un oráculo | `supabase_schema.sql:765-806`: exige sesión, valida formato, comparte rate-limit, no devuelve `id`/`zone_id` y oculta avatar privado. | **PASS local.** | El registro lo declaraba `VERIFIED` en remoto sin instancia/pruebas reproducibles en esta sesión. | Estado corregido a “reportado, no re-verificado”; validar en staging. |
| 11 | Los contratos cliente-servidor coinciden | El cliente usa exclusivamente `resolve_bt_token` (sin SELECT directo a `bt_tokens`), `mark_messages_read`/`mark_message_delivered` y `claim_zone_id`; `SameAccountClaimPolicy` bloquea el claim por defecto. | **PASS parcial.** | `_loginWithExistingIDInternal` escribe `_zoneId`/`_uid` y storage **antes** de llamar al claim. Si el kill-switch se levantara y el claim fallara, el dispositivo quedaría con identidad local nueva y sin fila reclamada. | Fase F: mover el commit local después de un claim exitoso y limpiar la sesión anónima si falla. No habilitar el switch hasta entonces. |
| 12 | `BUG_REGISTER.md` refleja la evidencia | Se corrigieron Z-001, Z-002, Z-103, Z-206 y Z-207; se separó “historial” de “estado actual”; se retiró la afirmación de verificación remota no reproducible. | **Corregido.** | El registro afirmaba `REMOTE_APPLIED + VERIFIED` para Z-001 mientras el código seguía vulnerable. | Mantener el registro enlazado a evidencia verificable; no declarar VERIFIED sin instancia y pruebas. |
| 13 | `get_radar_stats` no filtra datos sensibles | `supabase_schema.sql:333-356`: `SECURITY DEFINER`, exige `auth.uid()`, devuelve solo conteos agregados (`total_users`, `active_users_24h`, `active_tokens`, `total_encounters`). | **Residual P2/P3.** | Cualquier usuario autenticado obtiene métricas agregadas de toda la base. | Aceptar como diagnóstico o restringir a un rol interno; documentado en el gate. |
| 14 | Las migraciones Z-210/Z-211 son compatibles | `z210` añade `encounter_key` + índice único; `z211` añade par canónico y reconcilia duplicados con `UPDATE`/`DELETE` deterministas. No alteran políticas. | **Compatible con revisión.** | `z211` modifica/elimina filas históricas de `matches`; no es reversible con SQL. | Fase B: backup, conteo de duplicados y dry-run antes de aplicar; rollback documentado como restauración, no como reverse SQL. |
| 15 | El estado remoto está verificado | No hay acceso a una instancia remota identificada en esta sesión; no se ejecutaron pruebas JWT/RLS remotas. | **BLOCKED.** | Cualquier afirmación de “verificado en remoto” carece de evidencia actual. | Fase B: solicitar autorización explícita para staging y ejecutar el runbook. |

---

## 3. Hallazgos nuevos de esta fase

### 3.1 `fix_radar_bilateral.sql` era una ruta de regresión P1

El archivo histórico:

- Recreaba la política `"Resolver token BT"` con `USING (auth.role() = 'authenticated' AND expires_at > now())`, exponiendo el mapping token→`user_id` a cualquier autenticado.
- Reemplazaba `resolve_bt_token` por una versión sin `auth.uid()` y sin filtrar avatar/handles privados.
- Reseteaba `used = FALSE` en todos los tokens.

**Corrección local:** el archivo ahora elimina la política amplia, reinstala la RPC con gate de sesión y visibilidad, y no muta `used`. El harness lo re-aplica después de Z-212 y verifica que no reaparece la política ni se expone el avatar privado.

### 3.2 `z106_z206_policies.sql` recreaba el UPDATE directo de `messages`

El archivo histórico recreaba la política `"Actualizar mensaje con match aceptado"`. Aunque el trigger Z-212 seguiría bloqueando contenido/identidad, la política permitía saltarse el diseño “receipts solo por RPC”.

**Corrección local:** el archivo ahora elimina la política UPDATE, conserva la DELETE de participantes y su bloque de verificación falla si la política UPDATE reaparece. El harness lo re-aplica y comprueba el catálogo `pg_policies`.

### 3.3 `z104_bt_token_hardening.sql` tenía comentarios obsoletos

Afirmaba que la política `"Resolver token BT"` seguía gobernando el acceso directo. Se actualizó el comentario: Z-212 la eliminó y el acceso directo es self-scoped.

### 3.4 El login tiene un efecto lateral si el claim falla

`loginWithExistingID` llama primero a `SameAccountClaimPolicy.ensureAllowed` (fail-closed), por lo que hoy el flujo no se ejecuta. Pero si el switch se levantara sin corregir el orden, `_loginWithExistingIDInternal` escribiría `_zoneId`, `_uid` y storage antes de que el claim falle. Esto dejaría al dispositivo con una identidad local nueva y sin fila reclamada. Se documenta para Fase F; no se cambió el comportamiento en Fase A para no tomar una decisión de producto sin aprobación.

---

## 4. Evidencia ejecutada

| Prueba | Comando | Resultado |
|--------|---------|-----------|
| Guard estático SQL | `flutter test --no-pub test/sql_security_regression_test.dart` | **4/4 PASS** |
| Analyze del guard | `flutter analyze --no-pub test/sql_security_regression_test.dart` | **No issues found** |
| Harness SQL Z-212 + migraciones históricas | `psql -v ON_ERROR_STOP=1 -f supabase_migrations/tests/z212_behavioral_test.sql` en PostgreSQL 18.4 desechable | **ALL Z-212 SQL TESTS PASSED**, `PSQL_EXIT=0` |
| Segunda aplicación de Z-212 | Ejecución separada de `z212_security_hardening.sql` sobre el mismo esquema | **`RUN2_EXIT=0`** (evidencia de la sesión previa; Z-212 no cambió en esta fase) |
| Búsqueda de `UPDATE public.users SET id` | `Select-String` sobre esquema, deploy y migraciones | **Sin coincidencias ejecutables**; solo texto histórico en comentarios |
| Búsqueda de políticas amplias / grants anon | `Select-String` sobre `USING (true)`, `auth.role()`, `GRANT ... TO anon/PUBLIC` | **Sin coincidencias** en esquema/deploy/migraciones |

**Nota de entorno:** durante los reintentos de validación SQL, Windows registró `exception 0xC0000142` en procesos hijos de PostgreSQL (fallo de inicialización de DLL). El primer harness completo pasó; los reintentos posteriores no son evidencia de una regresión SQL. La validación debe repetirse en CI/Linux o en un host estable antes de staging.

---

## 5. Conclusión de Fase A

- El estado real **no** coincidía con el registro: Z-001 seguía presente en el código y dos migraciones históricas podían reintroducir controles vulnerables.
- El claim, la política de tokens, el UPDATE de messages y el UPDATE de matches están ahora en el estado Z-212 **local**.
- Las rutas de regresión históricas conocidas están cerradas y cubiertas por un guard estático.
- **No** se declara ningún control verificado en remoto.
- El gate de beta sigue **NO-GO** hasta completar Fase B (staging), Fase F (login) y Fase G (E2EE/P2P), y hasta resolver los P0/P1 restantes.

**Siguiente paso:** preparar el runbook de staging (Fase B) y solicitar autorización explícita antes de cualquier conexión remota.
