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

    // Some plugins (file_picker → flutter_plugin_android_lifecycle) need
    // compileSdk >= 36. Force it on every Android module so plugin modules are
    // not compiled against an older API than the app.
    // Registered BEFORE evaluationDependsOn (which evaluates the projects).
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            (ext as com.android.build.gradle.BaseExtension).apply {
                val current = compileSdkVersion
                    ?.removePrefix("android-")
                    ?.toIntOrNull()
                if (current == null || current < 36) {
                    compileSdkVersion(36)
                }
                // home_widget, patrol, printing and watch_connectivity still
                // compile as Java 8, which javac 21 warns is obsolete. Set, not
                // compared: AGP 9 refuses to read the value this early, and no
                // plugin asks for more than the app's 17.
                if (project.name != "app") {
                    compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                    compileOptions.targetCompatibility = JavaVersion.VERSION_17
                    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                    }
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
