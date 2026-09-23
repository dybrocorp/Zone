# UX_AUDIT — Auditoría de Experiencia de Usuario · ZONE (FASE 0)

## 1. Bloqueos y errores expuestos

| Hallazgo | Bug | Impacto UX |
|---|---|---|
| Arranque atascado en "Error al iniciar. Reintenta." si `.env` no está (no puede avanzar) | Z-006 | Bloqueo total; el botón Reintentar no soluciona la causa |
| SnackBars con mensajes técnicos: `Exception: Sin conexión Mesh ni Internet`, `$e`, "No se pudo guardar en el servidor" | Z-202 | Confusión; sin acción clara |
| `Error de seguridad: Llaves no listas. Reinicia la app.` al abrir chat | (diseño) | Mensaje de seguridad sin explicación |
| retry del chat requiere estar en la misma sesión (memoria) | Z-007 | Los mensajes "failed" desaparecen si cambias de pantalla/app |

## 2. Estados de conexión

- El header del chat no muestra/degradada la indicación de "mesh offline vs online" más allá del `transport` del mensaje.
- El arranque exige red implícitamente (Supabase.initialize), aun cuando el mesh local podría ser suficiente — UX y usabilidad fuera de cobertura, pese a prometer offline-first (Z-007).
- Radar: cuando falla el pull global, el usuario ve un radar vacío sin distinción "sin datos vs sin conexión".

## 3. Flujo de identidad / login

- `loginWithExistingID` acepta cualquier `zone_id` alfanumérico sin formato validado (regex ausente): entorpece y facilita ataques (Z-001).
- La recuperación de cuenta depende únicamente del ZONE-ID (sin verificación de posesión). UX insecure y fácilmente víctima de phishing.

## 4. Premium / donaciones

- El botón de donación activa Premium **al instante y gratis** (donations_screen:44) — engañoso para usuarios que pagan (Z-008). Sin flujo de pago real; hay precio en pantalla (100000) sin procesador.

## 5. Privacidad percibida vs real

- UI declara visibilidad selectiva (IG/FB/TikTok, gallery) pero la protección es client-side (Z-002) y los avatares/galleries viven en bucket público (Z-111). La promesa de "tú decides quién ve qué" es falsa a nivel plataforma → riesgo de confianza del usuario.

## 6. Notificaciones

- Sin push; solo notificaciones locales mientras la app está abierta (Z-110). En iOS no hay Darwin settings para sonido/alertas.
- Los mensajes entrantes requieren el listener global activo (singleton) — puede haber duplicados entre canales (broadcast + postgres).

## 7. Recomendaciones FASE 1 (UX)

1. Errores amigables con acciones (Reintentar/Cerrar) y sin texturas internas (Z-202).
2. Chat 100% funcional offline con cola visible ("esperando conexión…") (Z-007).
3. Validación + edukación de ZONE-ID en login; agregar 2FA/posesión (Z-001).
4. Remover compra simulada; dejar placeholder "próximamente" hasta integrar pagos (Z-008).
5. Alinear privacidad percibida vs real (RLS/storage) antes de marketing (Z-002, Z-111).
6. Notificaciones push con permisos correctos iOS/Android (Z-110).

---
*Documento FASE 0.*