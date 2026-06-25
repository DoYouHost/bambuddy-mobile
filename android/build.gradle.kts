allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Niektóre pluginy (file_picker → flutter_plugin_android_lifecycle) wymagają
    // compileSdk >= 36. Wymuszamy go na wszystkich modułach Android, żeby moduły
    // pluginów nie były kompilowane przeciw starszemu API niż aplikacja.
    // Rejestrujemy PRZED evaluationDependsOn (które ewaluuje projekty).
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            (ext as com.android.build.gradle.BaseExtension).apply {
                val current = compileSdkVersion
                    ?.removePrefix("android-")
                    ?.toIntOrNull()
                if (current == null || current < 36) {
                    compileSdkVersion(36)
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
