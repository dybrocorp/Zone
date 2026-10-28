import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Release signing (Phase C / ZONE) ─────────────────────────────────────────
// Release builds MUST use an explicit upload/release key. Debug builds keep the
// default debug keystore, so `flutter run` / `flutter build apk --debug` work
// without any signing setup.
//
// Configuration sources (environment wins over key.properties):
//   1. Environment: ZONE_KEYSTORE_PATH, ZONE_KEYSTORE_PASSWORD,
//      ZONE_KEY_ALIAS, ZONE_KEY_PASSWORD.
//   2. android/key.properties (git-ignored): storeFile, storePassword,
//      keyAlias, keyPassword.
//
// Relative storeFile paths resolve against android/ (rootProject), not app/.
// Use forward slashes on Windows. Never commit key.properties or the keystore.
val releaseSigningFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties().apply {
    if (releaseSigningFile.exists()) {
        releaseSigningFile.inputStream().use { load(it) }
    }
}

fun releaseSigningValue(propertyName: String, envName: String): String? =
    System.getenv(envName)?.takeIf { it.isNotBlank() }
        ?: releaseSigningProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val releaseStorePath = releaseSigningValue("storeFile", "ZONE_KEYSTORE_PATH")
val releaseStorePassword = releaseSigningValue("storePassword", "ZONE_KEYSTORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("keyAlias", "ZONE_KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("keyPassword", "ZONE_KEY_PASSWORD")

val missingReleaseSigning = mutableListOf<String>()
if (releaseStorePath == null) missingReleaseSigning += "storeFile / ZONE_KEYSTORE_PATH"
if (releaseStorePassword == null) missingReleaseSigning += "storePassword / ZONE_KEYSTORE_PASSWORD"
if (releaseKeyAlias == null) missingReleaseSigning += "keyAlias / ZONE_KEY_ALIAS"
if (releaseKeyPassword == null) missingReleaseSigning += "keyPassword / ZONE_KEY_PASSWORD"

val releaseSigningConfigured = missingReleaseSigning.isEmpty()
val releaseStoreFile: File? = releaseStorePath?.let { path ->
    val candidate = File(path)
    if (candidate.isAbsolute) candidate else rootProject.file(path)
}

android {
    namespace = "com.dybrocorp.zone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_21.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dybrocorp.zone"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // No debug-key fallback. If signing is missing, the task-graph guard
            // below fails the release build with an actionable message.
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Fail before any release artifact is produced. This runs for assembleRelease,
// bundleRelease, installRelease and the packaging/signing tasks, but never for
// debug builds or ordinary Gradle queries.
gradle.taskGraph.whenReady {
    val releaseTasks = allTasks.filter { task ->
        task.project == project && (
            task.name == "assembleRelease" ||
                task.name == "bundleRelease" ||
                task.name == "installRelease" ||
                task.name == "validateSigningRelease" ||
                task.name.startsWith("packageRelease") ||
                task.name.startsWith("signRelease")
            )
    }
    if (releaseTasks.isEmpty()) {
        // Nothing to do: debug builds and configuration-only queries stay usable.
    } else if (!releaseSigningConfigured) {
        throw GradleException(
            buildString {
                appendLine("Release signing is not configured. Refusing to build a release with debug keys.")
                appendLine("Missing: ${missingReleaseSigning.joinToString(", ")}.")
                appendLine("Provide android/key.properties (git-ignored) or the ZONE_* environment variables.")
                append("See docs/RELEASE_SIGNING.md.")
            }
        )
    } else if (releaseStoreFile == null || !releaseStoreFile.exists()) {
        throw GradleException(
            "Release signing keystore not found: ${releaseStoreFile?.absolutePath ?: "<unset>"}. " +
                "Check storeFile / ZONE_KEYSTORE_PATH in docs/RELEASE_SIGNING.md."
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
