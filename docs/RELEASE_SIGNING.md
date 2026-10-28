# Android release signing (ZONE)

**Estado:** implementado en `android/app/build.gradle.kts` (Fase C, 2026-10-23).
**Regla:** un build `release` **nunca** se firma con la clave de debug. Si falta la
configuración, el build falla con un mensaje claro antes de producir el artefacto.

**Estado del release de producción (2026-10-27): BLOCKED.** No existe el
keystore de release; los builds release siguen fallando cerrados sin
configuración. Verificación de esta fecha: no hay `android/key.properties` en
el árbol ni `*.jks`/`*.keystore` en el repositorio; `.gitignore` raíz
(líneas 44-47) y `android/.gitignore` (líneas 12-14) los excluyen. Cuando el
keystore real esté disponible, la verificación es: `flutter build
appbundle --release --dart-define-from-file=.env` + `apksigner verify
--print-certs` (certificado ≠ `CN=Android Debug`, SHA-256 = keystore de
release). Hasta entonces, la clasificación del release de producción
permanece **BLOCKED** tras P0-4 del gate.

---

## 1. Por qué

Firmar release con `signingConfigs.getByName("debug")` permite:

- Publicar artefactos con una clave pública y compartida (cualquiera puede firmar
  una actualización con la misma identidad de debug en algunos entornos).
- Perder la continuidad de actualizaciones si la clave de debug cambia.
- Falsos positivos en verificaciones de integridad y en Play Console.

Por eso el proyecto exige una clave de release explícita. Los builds de debug
siguen funcionando sin configuración: usan el keystore de debug que genera el
Android SDK.

---

## 2. Crear el keystore (una sola vez)

Requisitos: JDK con `keytool` (Android Studio incluye uno).

Desde `android/`:

```bash
keytool -genkeypair -v \
  -keystore ../keys/zone-upload.jks \
  -alias zone-upload \
  -keyalg RSA -keysize 4096 -validity 10000
```

- `keytool` pedirá las contraseñas de forma interactiva. **No** las pases por
  línea de comandos (quedan en el historial/procesos).
- Guarda el `.jks` fuera del repositorio, con backup cifrado y acceso restringido.
- Guarda las contraseñas en un gestor de secretos. Si pierdes el keystore o sus
  contraseñas, **no podrás publicar actualizaciones** de la app con la misma
  identidad (salvo recuperación de Play App Signing).

> Recomendación: usa **Play App Signing**. Sube una upload key; Google custodia
> la app signing key. Así una pérdida de la upload key es recuperable.

---

## 3. Configurar credenciales

### Opción A — local: `android/key.properties` (git-ignored)

```bash
cp android/key.properties.example android/key.properties
```

Edita `android/key.properties`:

```properties
storeFile=../keys/zone-upload.jks
storePassword=...
keyAlias=zone-upload
keyPassword=...
```

- Las rutas relativas de `storeFile` se resuelven contra `android/`, no
  `android/app/`.
- En Windows usa barras `/` (Java `Properties` interpreta `\` como escape).
- Restringe los permisos del archivo (solo tu usuario).
- **Nunca** lo commitees: `android/.gitignore` y el `.gitignore` raíz ya lo
  excluyen, junto con `*.jks` y `*.keystore`.

### Opción B — CI: variables de entorno

| Variable | Contenido |
|----------|-----------|
| `ZONE_KEYSTORE_PATH` | Ruta absoluta o relativa a `android/` del `.jks` |
| `ZONE_KEYSTORE_PASSWORD` | Contraseña del keystore |
| `ZONE_KEY_ALIAS` | Alias de la clave |
| `ZONE_KEY_PASSWORD` | Contraseña de la clave |

Las variables de entorno tienen prioridad sobre `key.properties`. En CI, inyéctalas
desde el gestor de secretos y no las imprimas en logs.

---

## 4. Compilar y verificar

```bash
flutter build apk --release --dart-define-from-file=.env
# o
flutter build appbundle --release --dart-define-from-file=.env
```

Verificación de la firma (ajusta la ruta de `build-tools`):

```bash
$ANDROID_HOME/build-tools/<version>/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

Comprueba que el certificado **no** es el de debug (`CN=Android Debug`) y que el
SHA-256 coincide con el keystore de release.

También puedes validar solo la configuración, sin compilar:

```bash
cd android
./gradlew :app:validateSigningRelease
```

---

## 5. Comportamiento ante configuración ausente

El bloque de firma lee `android/key.properties` o las variables `ZONE_*`. Si falta
cualquiera de los cuatro valores, cualquier tarea de release (`assembleRelease`,
`bundleRelease`, `installRelease`, empaquetado/firma) falla con:

```
Release signing is not configured. Refusing to build a release with debug keys.
Missing: ...
Provide android/key.properties (git-ignored) or the ZONE_* environment variables.
See docs/RELEASE_SIGNING.md.
```

Si la ruta existe pero el archivo no, el error indica la ruta esperada. Los builds
`debug` y las consultas de Gradle no se ven afectados.

---

## 6. Prueba con clave temporal (sin tocar el repo)

Para validar el cableado sin la clave real:

```powershell
$tmp = Join-Path $env:TEMP "zone-signing-test"
New-Item -ItemType Directory -Force $tmp | Out-Null
keytool -genkeypair -v -keystore "$tmp/test.jks" -alias test -keyalg RSA -keysize 2048 -validity 1 -storepass testpass -keypass testpass -dname "CN=ZONE Test"
$env:ZONE_KEYSTORE_PATH = "$tmp/test.jks"
$env:ZONE_KEYSTORE_PASSWORD = "testpass"
$env:ZONE_KEY_ALIAS = "test"
$env:ZONE_KEY_PASSWORD = "testpass"
cd android
./gradlew :app:validateSigningRelease
Remove-Item Env:ZONE_KEYSTORE_PATH, Env:ZONE_KEYSTORE_PASSWORD, Env:ZONE_KEY_ALIAS, Env:ZONE_KEY_PASSWORD
Remove-Item -Recurse -Force $tmp
```

La clave temporal es solo para validación local; **no** se usa para publicar ni se
commitea.

---

## 7. Rotación y respuesta a incidentes

- Si la upload key se compromete: rota la upload key en Play Console (Play App
  Signing) y actualiza el secreto de CI.
- Si el keystore se pierde y **no** usas Play App Signing: no hay forma de
  continuar la misma app en Play; documenta el incidente y evalúa un nuevo
  listing.
- No reutilices la clave de debug ni subas keystores al repositorio, a issues o a
  artefactos de CI.
