# DEVICE CERTIFICATE V2 — Especificación (`ZDC2`)

**Estado: IMPLEMENTADO + PROBADO LOCALMENTE** (`lib/identity/device_certificate_v2.dart`,
`test/identity/device_certificate_v2_test.dart` 13/13). Fundación de migración de
dispositivo (PHASE F/G, autorización PHASE_J DEC-F/DEC-F4). Sin backend remoto
(NO VALIDADO EN BACKEND — el exec de z213 no está autorizado).

## 1. Propósito

Certificado firmado que vincula un **dispositivo** (X25519 pk + fingerprint)
a una **cuenta** (Ed25519 de identidad), emitido por la propia cuenta. Caso de
uso: primer ancla `add_device` (pipeline A) verificado por OOB del
fingerprint — explícito, NO TOFU silencioso — y verificación de intercambios
durante la migración A/B/C.

## 2. Formato binario/canónico

```text
cert  = "ZDC2:" || base64( utf8( envelope_json ) )
envelope_json = {"p": <payload_canonical_json>, "s": <sig_b64_std_padded>}
payload (campos, orden fijo, sin espacios):
{
  "v": 2,
  "account_id":  <uuid canónico lowercase>,
  "device_id":   <uuid canónico lowercase>,
  "fp":          <64 hex lowercase — DEVICE_FINGERPRINT de la fundación>,
  "x25519":      <32B device encryption pk, base64 estándar con padding>,
  "acct_ed25519":<32B account identity pk, base64 estándar con padding>,
  "iat":         <ISO8601 UTC>,
  "exp":         <ISO8601 UTC, iat < exp; validez por defecto 365 d>
}
```

- La serialización de strings del payload usa la **ÚNICA** función canónica
  compartida `canonicalJsonString` (`lib/crypto/e2ee_message_crypto.dart`) —
  dos formateadores distintos romperían la reproducibilidad de bytes.
- Firma Ed25519 sobre los bytes EXACTOS del payload canónico
  (`CanonicalCodec.utf8Bytes`), 64 B (`kEd25519SignatureLength`).

## 3. Orden de verificación (fail-closed, `verify`)

1. **shape** — prefijo `ZDC2:` / base64 / JSON / campos tipados presentes y
   no vacíos; `issue` rechaza `exp <= iat` (`validity`) y un fingerprint
   declarado que no liga al material (`fingerprint`).
2. **canonical** — el payload DEBE reproducir EXACTAMENTE el JSON canónico
   conocido (FORMA + ORDEN; la manipulación de VALORES la atrapa la firma,
   que cubre los bytes exactos).
3. **expired** — `exp` pasado (tolerancia 0; `issue` construye UTC).
4. **signature** — Ed25519 sobre el payload canónico con
   `acct_ed25519` declarado. Esto cubre también la vía de manipulación
   de VALORES sin re-firmar: la firma vieja no matchea.
5. **fingerprint** — recomputa el binding del fingerprint
   (`FingerprintService.deviceFingerprint` con `account_id+device_id+x25519
   pk`); declarado ≠ recalculado ⇒ rechazo aunque el cert sea auto-consistente.

## 4. Límite de confianza explícito (caller-side anchor)

Un cert **auto-consistente** (firmado por SU propia clave declarada) pasa
`verify`: es por diseño — el formato no puede distinguir el "propio" sin
contexto externo. La autenticidad EXIGE que el llamador compare
`payload.accountIdentityEd25519Base64` contra su **ancla conocida** (del
login, del dispositivo activo previo o del OOB del fingerprint). El test
`caller-side anchor contract` documenta y demuestra la detección.

## 5. Qué NO hace

- No revoca (revocación = ledger server-side `device_revocations`, z213,
  NO AUTORIZADO aún).
- No sustituye el registro `register_device` firmado del backend (dependencia
  documentada en `PHASE_E` §7.8.2 para WI-7 rotación legítima).
- No cifra nada: es binding de identidad, no transporte.

## 6. Verificación local

`test/identity/device_certificate_v2_test.dart` (13/13): roundtrip fiel,
envelope malformado (prefix/base64/json), `expired`, `validity` al emitir,
`fingerprint` al emitir, cert auto-consistente con fingerprint fabricado ⇒
rechazo en verify (re-computación), payload re-ordenado ⇒ `canonical`,
manipulación de valor ⇒ `signature`, clasificador `isV2Certificate`,
contrato de ancla, sin fuga de material en el error tipado.
