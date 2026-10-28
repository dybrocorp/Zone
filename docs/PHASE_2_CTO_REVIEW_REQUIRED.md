# PHASE 2.0 — Revisión CTO Requerida (Checklist de Aprobación)

> **Tipo:** PUERTA — Nada de este lote se implementa sin las firmas de abajo.
> **Fecha:** 2026-09-24 · **Estado:** PENDIENTE DE REVISIÓN
> **Bloquea:** inicio de M0 (y todo lo posterior de FASE 2.0 en el código).

---

## 1. Decisiones a confirmar (marcar ✔ / ✘)

| Ref | Decisión | Estado | Nota CTO |
|---|---|---|---|
| D1 | Ed25519 = identidad de cuenta (firma) | ⬜ | — |
| D2 | X25519 = identidad de cifrado de dispositivo (sin firmas) | ⬜ | — |
| D3 | Primer dispositivo: bootstrap con código 1-uso + señuelos + evento anti-apropiación | ⬜ | — |
| D4 | Segundo dispositivo: autorización firmada por device activo + QR/challenge + fingerprint | ⬜ | — |
| D5 | Recovery: códigos alta entropía + wrapped key client-side (hash + blob; jamás privada en claro) | ⬜ | — |
| D6 | Revocación: `revoke_device` con firma + auditoría + propagación mesh | ⬜ | — |
| D7 | Rotación X25519 versionada (`device_keys`), conservando la retirada para historial | ⬜ | — |
| D8 | Modo legacy completo hasta retiro planificado | ⬜ | — |
| D9 | Pérdida de dispositivo = pérdida de claves/historial (sin puerta trasera) | ⬜ | — |
| D10 | Pérdida de recovery = pérdida de acceso (fail-closed) | ⬜ | — |
| D11 | `claim_zone_id` eliminado como apropiación; sustituido por bootstrap/register/recover | ⬜ | — |
| D12 | Primer contacto mesh autenticado vía handshake + fingerprint (MR3) | ⬜ | — |
| D13 | Double Ratchet base (Signal) con interfaces definidas, solo en M4 | ⬜ | — |
| D14 | Migración M0-M5 compatible/reversible, parada por fase | ⬜ | — |

## 2. Decisiones de diseño de menor nivel (DR)

| Ref | Pregunta | Recomendación | Estado |
|---|---|---|---|
| DR-1 | ¿Dónde se genera `device_id`? | Cliente (UUIDv4) con validación | ⬜ |
| DR-2 | ¿Sesión E2EE por par de devices o por account? | Por par de devices (fallback account legacy) | ⬜ |
| DR-3 | TTL de challenges | 10 min | ⬜ |
| DR-4 | Periodicidad de rotación X25519 | No periódica inicial; por compromiso | ⬜ |
| DR-5 | ¿Quién firma el alta de device_2? | Device activo, validado por account | ⬜ |
| DR-6 | ¿Persistencia de SessionState del ratchet? | SecureStorage (o Isar cifrado local) | ⬜ |

## 3. Riesgos que el CTO debe aceptar explícitamente

1. **Historial v1** (claves estáticas) no obtiene FS retroactiva: si una privada X25519
   cae, el historial cifrado con ella es descifrable. Mitigación en M4 solo para
   mensajes nuevos. (THREAT_MODEL T13)
2. **Compromiso total del servidor** permite MITM de entrega sin detección hasta M3
   (fingerprints fuera de banda). (THREAT_MODEL T12)
3. **Pérdida de claves v1 en migración**: los usuarios que no hagan upgrade no
   tendrán Ed25519 ni devices; queda soportado como legacy indefinido (coste de
   mantenimiento).
4. **Bootstrapping M1** es la fase más riesgosa (apropiación): requiere la UI de
   señuelos + evento anti-apropiación como requisito de entrada.

## 4. Pruebas que se ejecutarán como criterio de salida (cada fase)

| Fase | Pruebas obligatorias mínimas |
|---|---|
| M0 | `flutter analyze` 0 · tests v1 intactos |
| M1 | T1-T4, T7-T11, T14-T15 (THREAT_MODEL) · sin cambio de cifrado |
| M2 | pruebas v1↔v3 (footer de versión) · KDF vector (RFC 5869) |
| M3 | T6, T12, T16 (handshake, MITM, transcript) · fingerprint |
| M4 | T5, T9, T17 ratchet · FS/PCS vectors · out-of-order |
| M5 | retiro legacy con pruebas de historial |

## 5. Firma

| Rol | Fecha | Firma |
|---|---|---|
| CTO (decisión criptográfica) | | |
| CTO (decisión de producto/UX) | | |
| Owner (supabase/cloud) | | |

> ⚠️ **Hasta la fecha de firma, FASE 2.0 queda en estado DISEÑO. No se abre ningún
> sprint de implementación.** El handoff completo está en `PHASE_2_CTO_HANDOFF.md`.