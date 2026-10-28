# FASE C — Firma de release Android (ZONE)

**Fecha:** 2026-10-23
**Rama:** `main`
**HEAD:** `7f59b776c62cc131fd05dc999e99cbb7804385e8`
**Estado:** implementado y validado localmente; **sin commit/push** y **sin keystore real**.

---

## 1. Objetivo

Eliminar la firma de release con la clave de debug y exigir una configuración
explícita, sin romper los builds de debug y sin permitir que claves o contraseñas
entren al repositorio.

Antes, `android/app/build.gradle.kts` hacía:

```kotlin
release {
    signingConfig = signingConfigs.getByName("debug")
}
```

Eso permitía publicar un artefacto de release con la identidad de debug.

---

## 2. Cambios

### 2.1 `android/app/build.gradle.kts`

- Lee `android/key.properties` (git-ignored) **o** las variables de entorno
  `ZONE_KEYSTORE_PATH`, `ZONE_KEYSTORE_PASSWORD`, `ZONE_KEY_ALIAS`,
  `ZONE_KEY_PASSWORD` (las variables tienen prioridad).
- Solo crea `signingConfigs.release` si los cuatro valores están presentes.
- El `buildType` release usa esa configuración; **no** hay fallback a debug.
- Un guard en `gradle.taskGraph.whenReady` falla antes de producir el artefacto
  cuando se ejecuta `assembleRelease`, `bundleRelease`, `installRelease`,
  `validateSigningRelease` o tareas de empaquetado/firma, si:
  - falta cualquier credencial, o
  - la ruta del keystore no existe.
- Los builds debug y las consultas de Gradle no se ven afectados.
- Las rutas relativas de `storeFile` se resuelven contra `android/`.
- Los mensajes de error no imprimen contraseñas.

### 2.2 Archivos de soporte

| Archivo | Contenido |
|---------|-----------|
| `android/key.properties.example` | Plantilla con `CHANGE_ME`; sin secretos |
| `docs/RELEASE_SIGNING.md` | Creación de keystore, configuración, CI, verificación, rotación y prueba temporal |
| `.gitignore` (raíz) | `android/key.properties`, `*.jks`, `*.keystore` |
| `android/.gitignore` | Ya ignoraba `key.properties`, `*.jks`, `*.keystore` (se conserva) |
| `test/android_release_signing_test.dart` | Guard: no debug signing, fail-fast presente, secretos ignorados, ejemplo sin credenciales |

### 2.3 Toolchain necesario para poder compilar

El proyecto no compilaba con el Flutter actual (3.47.2). Se corrigió el drift
mínimo para que debug y release puedan ejecutarse:

| Componente | Antes | Después | Motivo |
|------------|-------|---------|--------|
| Gradle wrapper | 8.13 | **8.14.3** | Flutter exige ≥8.14.0 |
| Kotlin (KGP) | 2.1.0 | **2.2.20** | Flutter exige ≥2.2.20 |
| AGP | 8.11.1 | 8.11.1 (sin cambio) | Funciona; Flutter avisa de un futuro mínimo 9.0.1 |
| Memoria Gradle | `-Xmx8G`, metaspace 4G | `-Xmx2G`, metaspace 768m, Kotlin 1.5G, 2 workers | El host tiene 7,9 GB; la JVM murió por OOM nativo |

El cambio de memoria está en `android/gradle.properties`. No cambia código de app.

---

## 3. Evidencia ejecutada

| Prueba | Comando | Resultado |
|--------|---------|-----------|
| Release sin configuración | `gradlew :app:assembleRelease --dry-run` | **FAIL esperado**: `Release signing is not configured... Missing: ...` |
| Release con ruta inexistente | mismas variables apuntando a un `.jks` ausente | **FAIL esperado**: `Release signing keystore not found: ...` |
| Firma con clave temporal | `keytool` en `%TEMP%` + `gradlew :app:validateSigningRelease` | **BUILD SUCCESSFUL**, `GRADLE_EXIT=0`; keystore temporal borrado |
| Debug no bloqueado | `gradlew :app:assembleDebug --dry-run` | **BUILD SUCCESSFUL** |
| Debug real | `flutter build apk --debug --no-pub` | **`app-debug.apk` construido**, `FLUTTER_EXIT=0` |
| Guard de firma | `flutter test --no-pub test/android_release_signing_test.dart` | **3/3 PASS** |
| Analyze | `flutter analyze --no-pub test/android_release_signing_test.dart test/flutter_test_config.dart` | **No issues found** |

La clave temporal se generó fuera del repositorio, con validez de 1 día y
contraseña efímera; se eliminó al terminar. **No** se usó para publicar.

---

## 4. Advertencias y riesgos residuales

1. **No hay keystore real disponible.** No se puede producir un release firmado
   definitivo hasta que el responsable entregue la upload key por el canal seguro.
   El flujo está listo y falla cerrado mientras no exista.
2. **Play App Signing recomendado.** Sin él, perder la upload key impide publicar
   actualizaciones con la misma identidad.
3. **Avisos de Flutter (no bloqueantes):**
   - Gradle 8.14.3: Flutter avisa de un futuro mínimo 9.1.0.
   - AGP 8.11.1: Flutter avisa de un futuro mínimo 9.0.1.
   - Kotlin 2.2.20: Flutter avisa de un futuro mínimo 2.3.20.
   Actualizar a esas versiones es un cambio mayor (AGP 9/Gradle 9) y debe hacerse
   en una tarea separada con validación completa; hoy el build funciona.
4. **Memoria:** el ajuste es para este host de 7,9 GB. En CI con más memoria se
   puede subir, pero no es necesario para compilar.
5. **`key.properties` en texto plano local.** Restringir permisos; en CI usar
   secretos. Nunca commitear.

---

## 5. Criterios de aceptación

- [x] Release no usa `signingConfigs.getByName("debug")`.
- [x] Falta de configuración → fallo claro antes del artefacto.
- [x] Ruta de keystore inexistente → fallo claro.
- [x] Configuración completa + clave temporal → validación de firma OK.
- [x] Debug sigue compilando.
- [x] `.gitignore` cubre `key.properties`, `*.jks`, `*.keystore`.
- [x] Ejemplo sin credenciales reales.
- [x] Guard de regresión y analyze.
- [ ] Release real con la upload key definitiva (bloqueado por disponibilidad de la clave).
