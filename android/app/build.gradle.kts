import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) load(keyPropertiesFile.inputStream())
}
// Without key.properties, the "release" signingConfig below would be left with
// all-null fields, and Gradle fails the release build with a cryptic
// "keystore file not set" error. Fall back to the debug key instead, with a
// clear warning — a contributor building locally still gets a working APK,
// just not one suitable for distribution.
val hasReleaseKeystore = keyPropertiesFile.exists()
if (!hasReleaseKeystore) {
    logger.warn(
        "key.properties not found — release build will be signed with the " +
            "debug key, not the real release keystore. Not suitable for distribution."
    )
}

android {
    namespace = "page.codeberg.morganmlgman.bambuddy_mobile"
    // file_picker (via flutter_plugin_android_lifecycle) wymaga compileSdk >= 36;
    // przypięte na sztywno, bo domyślne flutter.compileSdkVersion jest niższe.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Wymagane przez flutter_local_notifications (v18+): część jego API
        // korzysta z nowszych klas java.time, dostępnych na starszych Androidach
        // dopiero przez desugaring biblioteki standardowej.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                keyAlias = keyProperties["keyAlias"] as String?
                keyPassword = keyProperties["keyPassword"] as String?
                storeFile = keyProperties["storeFile"]?.let { file(it) }
                storePassword = keyProperties["storePassword"] as String?
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "page.codeberg.morganmlgman.bambuddy_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Phone and watch ship as one Google Play listing (same applicationId),
    // differentiated only by the merged manifest: the `wear` source set adds
    // `uses-feature android.hardware.type.watch`, which routes that APK to
    // watches. Both Dart entry points share this module; the flavor picks which
    // manifest merges. NOTE: once flavors exist every `flutter build/run` must
    // pass `--flavor` (see justfile).
    flavorDimensions += "device"
    productFlavors {
        create("mobile") {
            dimension = "device"
            // Inherits versionCode/versionName from defaultConfig (pubspec).
        }
        create("wear") {
            dimension = "device"
            // Play requires a distinct versionCode per APK under one listing,
            // so every flavor adds its own offset on top of the phone code. The
            // band layout, and the arithmetic that keeps the bands apart, is
            // documented next to `_bump` in the justfile — read it before you
            // give a new flavor an offset here.
            //
            // A billion is far more room than a band needs (~20 M), but this
            // number can no longer be lowered: 1_001_300_000 is already
            // published, and Play refuses a code at or below one it has seen.
            versionCode = (flutter.versionCode ?: 0) + 1_000_000_000
            // Wear OS 3+ only (API 30). Keeps Play from serving the watch APK
            // to Wear OS 2 devices, where nothing has ever been tested.
            minSdk = 30
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKeystore) "release" else "debug")
            // Flutter enables R8 for release; add our keep rules so ML Kit
            // (mobile_scanner's barcode backend) survives shrinking/obfuscation.
            // Without this the QR scanner crashes on start (black preview).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
