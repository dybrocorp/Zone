# FASE D — Isar error 126 en Windows (ZONE)

**Fecha:** 2026-10-23
**Estado:** resuelto localmente, sin descargar binarios no verificados y sin
saltar/borrar tests.

---

## 1. Síntoma

La suite fallaba con 21 tests de identidad:

```
Failed to load dynamic library 'D:\Proyectos\Zone\isar.dll': error code 126
```

Afectaba a:

- `test/identity/identity_bootstrap_integration_test.dart` (3)
- `test/identity/identity_persistence_test.dart` (10)
- `test/identity/migration_persistence_test.dart` (8)

Error 126 en Windows (`ERROR_MOD_NOT_FOUND`) al abrir una DLL: la ruta
`D:\Proyectos\Zone\isar.dll` no existe. `flutter test` no registra los plugins de
Flutter, por lo que `isar_flutter_libs` no copia/expone el núcleo nativo y `isar`
cae en su resolución por defecto: `<directorio del script>/isar.dll`.

**No era un defecto de código de la app ni de los tests.** El análisis estático y
el resto de la suite pasaban.

---

## 2. Por qué no se descargó nada

`isar` 3.1.0+1 puede descargar el núcleo desde GitHub si se usa
`Isar.initializeIsarCore(download: true)`. No se usó:

- Sería un binario no verificado en tiempo de test.
- Introduce dependencia de red y de un release externo.
- El paquete **`isar_flutter_libs` 3.1.0+1**, ya fijado en `pubspec.lock`, incluye
  el núcleo oficial para Windows/Linux/macOS/Android/iOS.

Se usó ese binario, sin copiarlo al repositorio.

---

## 3. Solución implementada

### 3.1 `test/flutter_test_config.dart`

Se añadió un config global de tests que:

1. Respeta `ZONE_ISAR_CORE_PATH` si está definida (override explícito; los tests
   que ya lo soportan cargan esa ruta).
2. Si no, lee `.dart_tool/package_config.json` (generado por `flutter pub get`) y
   localiza el paquete `isar_flutter_libs`.
3. Resuelve el núcleo según la plataforma:
   - Windows: `windows/isar.dll`
   - Linux: `linux/libisar.so`
   - macOS: `macos/libisar.dylib`
4. Si el archivo existe, llama a la API pública
   `Isar.initializeIsarCore(libraries: {Abi.current(): path})` antes de ejecutar
   los tests.
5. Si no lo encuentra o falla, **no oculta el fallo**: escribe contexto en stderr
   y deja que los tests de Isar muestren su diagnóstico real. No hay skip.

No se copian DLLs al repo, no se modifican tests para saltarlos y no se cambia la
resolución de producción (dispositivo/emulador usan `isar_flutter_libs` normal).

### 3.2 Por qué `package_config.json`

El primer intento usó `Isolate.resolvePackageUri`, pero `flutter test` lo rechaza:

```
Unsupported operation: Isolate.resolvePackageUriSync
```

`package_config.json` es el mecanismo estándar de Dart/Flutter, funciona sin
plugins y permite resolver la ruta real del paquete en cualquier pub cache.

---

## 4. Evidencia

### 4.1 Binario utilizado

| Dato | Valor |
|------|-------|
| Paquete | `isar_flutter_libs` 3.1.0+1 |
| Ruta | `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\isar_flutter_libs-3.1.0+1\windows\isar.dll` |
| Tamaño | 1.171.456 bytes |
| SHA-256 | `5E67863F188C5F9681A37F84F2EB942EAF702509D3F994C0344D5049EBC9E48F` |
| Origen | Paquete publicado en pub.dev, fijado por `pubspec.lock` |
| Descarga | Ninguna |

El `pubspec.lock` fija `isar_flutter_libs` con
`sha256: bc6768cc4b9c61aabff77152e7f33b4b17d2fc93134f7af1c3dd51500fe8d5e8`.

### 4.2 Resultados

| Prueba | Comando | Resultado |
|--------|---------|-----------|
| 21 tests bloqueados, con override manual | `ZONE_ISAR_CORE_PATH=...isar.dll flutter test <3 archivos>` | **21/21 PASS**, exit 0 |
| 21 tests sin variable manual (config global) | `flutter test --no-pub <3 archivos>` | **21/21 PASS**, exit 0 |
| Suite completa sin variable manual | `flutter test --no-pub` | **244/244 PASS**, exit 0 |
| Analyze | `flutter analyze --no-pub test/flutter_test_config.dart` | **No issues found** |

La suite completa incluye los 21 tests de identidad, los 4 del guard SQL de Z-212
y los 3 del guard de firma de release.

---

## 5. Reproducibilidad y CI

### Windows (host validado)

```powershell
flutter pub get
flutter test
```

No hace falta definir `ZONE_ISAR_CORE_PATH`; el config resuelve el paquete.

### Linux/macOS

El config implementa las rutas `linux/libisar.so` y `macos/libisar.dylib`. No se
ejecutaron en este host Windows; deben validarse en CI Linux/macOS antes de
declararlos verificados.

### CI

- Ejecutar `flutter pub get` antes de `flutter test` para generar
  `.dart_tool/package_config.json` y poblar el pub cache.
- No se necesita `flutter test --platform` ni emulador.
- Si se usa un pub cache aislado, el `package_config.json` apunta a él; no hay
  rutas hardcodeadas.
- Si el paquete no está, los tests fallan con el error original (fail-closed), no
  se saltan.

---

## 6. Riesgos residuales

1. **Acoplamiento al layout de `isar_flutter_libs`.** Si una versión futura
   cambia la ubicación del binario, el config no lo encontrará y los tests
   fallarán con error 126. Es un fallo visible, no silencioso; la actualización
   del paquete debe revisar este config.
2. **Linux/macOS no ejecutados aquí.** El código sigue el layout del paquete,
   pero falta evidencia real en CI.
3. **El override `ZONE_ISAR_CORE_PATH` sigue existiendo.** Es útil para
   diagnóstico, pero un valor incorrecto puede cargar otra biblioteca; es una
   variable de entorno local/CI, no una entrada de usuario.
4. **No se valida la firma del DLL en runtime.** Se confía en el paquete fijado
   por `pubspec.lock`; el hash queda documentado para auditoría. Añadir una
   verificación criptográfica en el config sería posible, pero requeriría fijar
   el hash y actualizarlo en cada bump; se deja como mejora.

---

## 7. Criterios de aceptación

- [x] Error 126 diagnosticado (DLL ausente en cwd, no corrupción).
- [x] Sin descarga de binarios no verificados.
- [x] Sin copiar DLLs al repositorio.
- [x] Sin borrar ni saltar tests.
- [x] 21/21 tests de identidad PASS sin variable manual.
- [x] Suite completa 244/244 PASS.
- [x] Override explícito sigue funcionando.
- [ ] Validación en CI Linux/macOS (pendiente de ejecución real).
