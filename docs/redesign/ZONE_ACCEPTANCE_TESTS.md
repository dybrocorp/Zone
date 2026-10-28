# ZONE — PLAN DE PRUEBAS DE ACEPTACIÓN (REDESIGN FREEMIUM)

**Etapa:** A (Diseño; el resultado de ejecución se registra en `ZONE_IMPLEMENTATION_REPORT.md`)

Etiquetas de resultado: `PASS` / `FAIL` / `BLOCKED` / `NOT RUN` / `NOT VERIFIED`.
Las suites existentes (421 tests) deben permanecer verdes; cualquier
regresión es un fallo de esta tarea.

---

## 1. Ubicación (LocationEngine)
| # | Escenario | Matriz/como | Resultado |
|---|---|---|---|
| L-01 | GPS disponible, precisión buena | fake fix ≤150 m | listado para test |
| L-02 | Solo fuente de red (sin GPS preciso) | fake fix 200–150 | aceptado si ≤ umbral |
| L-03 | Permiso denegado | fake status denied | estado `permissionBlocked` + reintento |
| L-04 | Permiso permanentemente denegado | fake status permanentlyDenied | guía a Ajustes |
| L-05 | Servicio de ubicación desactivado | fake serviceDisabled | instrucciones claras |
| L-06 | Precisión insuficiente (>150 m) | fake fix 800 m | "señal débil", sin resultados falsos |
| L-07 | Fix caducado (>2 min) | fake timestamp viejo | re-solicitud, no reutiliza |
| L-08 | Sin Internet | connectivity fake false | `offline`, sin llamada HTTP |
| L-09 | Cambio Wi-Fi ↔ datos móviles | transición de conectividad | se revalida y reenvía ping |

## 2. Descubrimiento geográfico
| # | Escenario | Cómo | Resultado |
|---|---|---|---|
| D-01 | Usuarios dentro y fuera del radio | RPC fake: filas filtradas por servidor | solo inside llegan al widget |
| D-02 | Radio mínimo/máximo | clamp client 250→max y server-side 2000 | valores inválidos rechazados |
| D-03 | Usuario visible/oculto | preferences fake | oculto no se muestra |
| D-04 | Usuario bloqueado | bloqueo bidireccional lógico | excluido (server + cliente) |
| D-05 | Presencia caducada | expires_at pasados | excluido |
| D-06 | Solicitud no autenticada | sesión nula | estado `requiresAuth`, sin RPC |
| D-07 | Consulta abusiva | pings < 15 s aparte | server rechaza (SQL), client throttle |
| D-08 | Intento de coords ajenas | resultado RPC no lista lat/lng | invariante SQL guard |
| D-09 | Visibilidad off con presencia viva | ping precede | `expire_my_presence` es llamado |

## 3. Premium (entitlement/billing)
| # | Escenario | Cómo | Resultado |
|---|---|---|---|
| P-01 | Usuario Free consulta gate | entitlement fake vacío | BT bloqueado con sheet |
| P-02 | Suscripción activa | entitlement verified+future | BT permitido |
| P-03 | Suscripción pendiente de backend | `purchased` sin verify | `verificationPending`, BT bloqueado |
| P-04 | Suscripción expirada | expires_at pasada | BT bloqueado |
| P-05 | Cancelada renovación (aún activa) | renewal_state canceled | BT permitido con aviso |
| P-06 | Refund/revocado | renewal_state refunded | BT bloqueado |
| P-07 | Fallo verificación (red) | RPC lanza | fail-closed (sin acceso eterno) |
| P-08 | Grace dentro de ventana | verified before + desconexión | permitido ≤24 h |
| P-09 | Grace expirado | >24 h sin conexión | bloqueado |
| P-10 | Restaurar | restorePurchases fake | re-query backend |
| P-11 | Manipular cliente: flag local premium | prefs premium=true sin entitlement | BT sigue bloqueado (falla invariante test) |
| P-12 | Llamada directa al servicio BLE sin entitlement | NearbyService.startRadar con entitlement false | guard RECHAZA (no solo UI) |

## 4. Regresión (suite completa existente + flujos clave)
Se ejecuta `flutter test --no-pub` completo y deben permanecer ≥ 421 PASS:
identidad (126), E2EE KAT (30), migración dispositivo (14), P2P AKE (simulado),
mesh, outbox, matches canónicos, login fail-closed, SQL guards Z-212/Z-213,
widget base.
Además se verifica manualmente (o por widget test) que:
- Radar BT sigue funcionando con el flujo existente cuando hay entitlement.
- login/ZONE-ID/matches/chat no cambian (solo añaden el proveedor GPS en paralelo).

## 5. SQL (guards estáticos de migración)
| # | Aserción en `sql_discovery_regression_test.dart` |
|---|---|
| S-01 | `discovery_preferences`, `discovery_presence`, `user_entitlements` nacen `ENABLE ROW LEVEL SECURITY` |
| S-02 | presence sin policies de SELECT (deny-all) |
| S-03 | Cada RPC nueva tiene REVOKE a anon/PUBLIC + GRANT authenticated |
| S-04 | definer con `search_path` fijado |
| S-05 | sin `GRANT INSERT/UPDATE/DELETE ON user_entitlements TO authenticated` |
| S-06 | el SELECT visible de `discover_nearby_users` no devuelve lat/lng |
| S-07 | TTL server: `expires_at = now() + INTERVAL` en ping |
| S-08 | FK CASCADE hacia users en las 3 tablas |

## 6. Empaquetado
| # | Chequeo | Criterio |
|---|---|---|
| V-01 | `flutter analyze --no-pub` | 0 issues |
| V-02 | `flutter test --no-pub` | todo pass |
| V-03 | `git diff --check` | sin conflictos de whitespace |
| V-04 | `flutter build apk --debug --dart-define-from-file=.env` | APK existe, tamaño>0, SHA-256 registrado |
| V-05 | instalación física | SOLO si hay dispositivo adb disponible; si no: NOT VERIFIED documentado |

> Los tests de compra real y GPS físico requieren Play Console / dispositivo
> externo → niveles §1/§3 "cómo" ya son fakes; las pruebas con vendor real
> quedan BLOCKED/NOT RUN y se listan en el informe final.
