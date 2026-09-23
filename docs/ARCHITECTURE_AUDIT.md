# ARCHITECTURE_AUDIT — Auditoría de Arquitectura · ZONE (FASE 0)

## 1. Visión general

- **Stack:** Flutter (Dart ≥3.10.8), Supabase (PostgREST + Realtime + Storage), Nearby Connections + BLE (mesh P2P), Isar (local), flutter_secure_storage (claves).
- **Patrón:** servicios singleton (`SupabaseService`, `IsarService`, `NearbyService`, `P2PSecurityService`, `ChatE2EEService`, `SyncService`, `ConnectivityService`, `NotificationService`, `ZoneIdService`, `PremiumService`, `PermissionsService`, `LoggerService`, `RetryHelper`, `BLEProximityService`, `BleService`, `ConnectionService`…) — **15+ singletons** sin DI contenedor ni estado gestionado centralmente (excepto `provider` en algunos puntos).
- **Capas:** no existe capa estricta "domain/data/presentation": los servicios llaman a pantallas y viceversa (chat llama a `SupabaseService`, `NearbyService`, `IsarService`, `ZoneIdService` directo).

## 2. Problemas estructurales

| Hallazgo | Bug | Descripción |
|---|---|---|
| Arranque monolítico y frágil | Z-006 | `InitialLoadingScreen` hace todo en serie y muere si `.env` falta; sin arquitectura de "bootstrap por módulos degradables" |
| Offline-first no implementado | Z-007 | La capa local (Isar `LocalMessage`/`LocalPendingMessage`) existe pero **no se usa**; el chat depende del servidor |
| Contratos SQL fragmentados | Z-105, Z-106, Z-109, Z-205 | Schema base ≠ código; parches sueltos; migración sin trackear |
| Identidad acoplada a RPC inseguros | Z-001, Z-103, Z-207 | El handover de ID (claim) es el centro de la autenticación y es inseguro |
| Sync "bidireccional" inexistente | Z-107 | Comentarios mienten; solo push de cola/encuentros y pull de perfiles |
| Registro multi-dispositivo roto | Z-107, Z-205 | Sin mensajes remotos → dos dispositivos NO comparten chat |
| Notificaciones sin orquestación | Z-110 | Listener global singleton sin ciclo de vida; sin push |
| Malla insegura por diseño | Z-003, Z-004, Z-005 | El mesh asume confianza del canal Nearby que no es identidad |
| Rendimiento reactivo no gestionado | Z-112 | Timers y painters sin throttling/memoización |
| Errores silenciosos | Z-109, Z-308 | Catch-and-log oculta fallos de funciones/RPC inexistentes |

## 3. Deuda técnica adicional

- **Sin tests** (Z-301) y dependencias viejas (Z-302) limitan cualquier refactor seguro.
- `widget_test.dart` bomba de humo; `load_test_simulator` con credenciales de terceros (Z-203).
- Código muerto: `verify_zone_id` (sin uso), ramas `CACHE:`/`GLOBAL:` del radar (Z-208), `getRadarStats` "no llamado", `sendMessagesBatch` (¿usado en algún punto?).
- Comentarios/documentación técnica engañosa (Z-307): "sync bidireccional", "Forward Secrecy", "seguro (Security Definer)".

## 4. Fortalezas

- Separación por servicios razonable para el tamaño del proyecto.
- Uso de primitivas criptográficas modernas y secure storage (CRYPTO_AUDIT §5).
- RLS habilitado en todas las tablas (aunque con policies incorrectas) — base aprovechable.
- Modelo Isar ya definido con entidades offline (falta conectar).
- Manejo de reintentos (RetryHelper) y conectividad centralizados.

## 5. Arquitectura objetivo (FASE 1/2 — propuesta)

1. **Capas:** presentación → caso de uso → repositorios (remote: Supabase; local: Isar) → servicios de plataforma.
2. **Repositorio de mensajes:** `MessageRepository` que siempre escribe a Isar y sincroniza (offline-first real) (Z-007).
3. **Contratos SQL únicos:** migraciones versionadas en `supabase/migrations` (Supabase CLI) + `supabase_deploy.sql` consolidado (Z-105/106/109/205).
4. **Identidad:** módulo de posesión criptográfica (challenge/response con Ed25519) reemplazando `claim_zone_id` (Z-001).
5. **Observabilidad:** logger con niveles + reporte; errores de negocio tipados; nunca `catch-and-ignore` en rutas críticas (Z-308).
6. **DI:** mover a `provider`/riverpod para gestionar ciclo de vida de los timers/listeners (Z-110, Z-112).

## 6. Verificación

- `flutter analyze`: 15 issues info (2 async context, 13 prints) — Z-303.
- `flutter test`: 1 test pasa pero con `[Startup] ERROR CRÍTICO: FileNotFoundError` en logs → cobertura ≈ 0 (Z-301, Z-006).
- `flutter pub outdated`: 69 upgrades, 17 fuera de rango, 4 discontinuadas (Z-302).
- Líneas Dart: ~10k (excl. `isar_models.g.dart` ~8.7k generadas).

---
*Documento FASE 0.*