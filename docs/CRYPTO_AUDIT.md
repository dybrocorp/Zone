# CRYPTO_AUDIT — Auditoría Criptográfica · ZONE (FASE 0)

> Cambiar el algoritmo/XOR no aplica aquí: la cripto está semi-bien implementada, pero el **protocolo** no logra lo que promete (FS, E2EE universal, identidad verificada).

## 1. Stack declarado vs verificado

| Primitiva | Uso | Verificado | Nota |
|---|---|---|---|
| Ed25519 | Firmas | Declarado (README) | **NO hallada en rutas clave** (mesh sin firma — Z-004). Verificar `p2p_security_service.dart`. |
| X25519 | ECDH | ✓ | `deriveSessionKey` estático-estático; sin claves efímeras — Z-101 |
| ChaCha20-Poly1305 | Cifrado de mensajes | ✓ | `chat_e2ee_service.dart::encryptMessage` produce encrypted_content+nonce+mac |
| PBKDF2 | Derivación local | Requiere validación | No confirmado en el código revisado |
| Secure storage | Claves | ✓ | flutter_secure_storage 9.2.4 (KEK en Keystore del SO) |

## 2. Problemas críticos

### Z-101 · ECDH estático-estático (sin Forward Secrecy)
- `_security.deriveSessionKey(remotePublicKey)` con pares X25519 fijos:
  - Misma llave de sesión durante toda la vida de las claves estáticas.
  - Compromiso de 1 clave privada → descifra TODO el historial de la sesión.
  - No hay ratchet, no hay rotación, no hay contadores por mensaje.
- **Impacto:** la afirmación "Forward Secrecy" de SECURITY.md/README es **FALSA**.
- **Mitigación:** protocolo con ratchet (doble/triple ratchet), claves efímeras por mensaje o al menos rotación de sesión; KDF con contador para nonces; reutilización de nonce prohibida (ver §4).

### Z-102 · Cambio de identidad sin aviso
- Pérdida de `private_key` en secure storage → `zone_id_service` regenera par y sube la nueva pública (426-432) silenciosamente.
- Los peers siguen usando la pública antigua → descifrado falla sin diagnóstico ("[Mensaje cifrado recibido pero no se tiene la llave de sesión]", nearby:1142).
- Falta: safety numbers/huella de identidad y prompt de confirmación.

### Z-003 · Opt-out de cifrado (fail-open) en mesh
- El cifrado mesh es **opcional**: si no hay `sessionKey`, el texto viaja en claro.
- Requisito de diseño: NO hay modo claro, jamás.

## 3. Derivación y guardado de llaves

- `_onPayloadReceived` deriva sesión al recibir perfil P2P y la guarda con `saveSessionKey(remoteZoneId, sessionKey)` (nearby:910-917). No hay verificación de quién es el peer (Z-004) → MTM/MITM trivial en Nearby (el man-in-the-middle "endpoint" se convierte en proxy y comparte una sesión falsa con cada lado).
- `p2p_security_service` y `chat_e2ee_service` son **singletons**; `initialize()` crea/lee clave par.

## 4. Recomendaciones estrictas de cifrado

1. **Nonces únicos garantizados** — si se reutiliza `nonce` con la misma clave en ChaCha20-Poly1305, se rompe autenticación y confidencialidad (criptoanálisis). Hoy el nonce depende de la generación interna de `encryptMessage`; añadir contador/persistencia.
2. **KDF con contexto** — `HKDF(sharedSecret, info=sessionID||contador)` para derivar llaves por mensaje.
3. **Firma Ed25519 por paquete mesh** — autenticidad de `source` (Z-004).
4. **Ratchet** o rotación de sesión programada (Z-101).
5. **Split de identidad** — par de firma (Ed25519) separado del par de intercambio (X25519), ambos con huella mostrada en UI.
6. **Revoque y aviso** de cambio de clave pública (Z-102).

## 5. Conclusión

- **Bien:** primitivas modernas, uso de secure storage, estructura mensaje cifrado (content+nonce+mac) persistida en DB.
- **Mal:** protocolo de capa alta (sin FS, identidad no verificada, fail-open) hace inviable garantizar E2EE y FS reales.
- **Estado: NO LISTO** para afirmaciones públicas de seguridad.

---
*Documento FASE 0.*