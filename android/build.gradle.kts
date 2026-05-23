
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Fix for "Namespace not specified" error and "lStar" resource error
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library") || project.plugins.hasPlugin("com.android.application")) {
            val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            if (android != null) {
                // Ensure compile SDK is at least 36 to satisfy new dependency requirements (androidx.core 1.18.0)
                android.compileSdkVersion(36)
                
                if (android.namespace == null) {
                    android.namespace = "dev.isar.${project.name.replace("-", "_")}"
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
