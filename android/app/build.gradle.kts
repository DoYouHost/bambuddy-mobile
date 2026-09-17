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
    // file_picker (via flutter_plugin_android_lifecycle) needs compileSdk >= 36;
    // pinned here because the default flutter.compileSdkVersion is lower.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (v18+): part of its API uses
        // newer java.time classes, which reach older Androids only through
        // desugaring of the standard library.
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
        // Pinned rather than `flutter.minSdkVersion`: that value is the SDK's
        // default of the day, so the floor moved with every Flutter upgrade and
        // no commit here recorded it. `flutter_local_notifications` 21+ needs
        // API 24, and building with an SDK that still defaulted to 21 would
        // ship an app whose notifications fail at runtime on old phones. 24 is
        // what Flutter 3.44 already resolved to, so this strands nobody.
        minSdk = 24
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

// Assets are declared once in pubspec.yaml and Flutter has no per-flavor list,
// so the watch APK carries the phone's G-code viewer, the slicer schemas, the
// dashboard's cover placeholder and four JetBrains Mono faces — ~2.2 MB behind
// screens the wear entry point does not have.
//
// Unreachable was verified, not assumed: none of these paths, and not the
// family name "JetBrainsMono", survives Dart tree shaking into the wear
// snapshot, while the phone's snapshot names them. `tool/check_wear_apk.py`
// asserts both halves against the built APK on every CI run, which is what
// makes deleting files out of a build directory safe to do at all — nothing
// else here would notice a path that stopped matching.
val wearPrunedAssetPaths = listOf(
    "assets/gcode",
    "assets/slicer",
    "assets/icons/cover_placeholder.png",
)

/// Dropped from the APK *and* from FontManifest.json. Leaving the manifest
/// naming a file that is gone is what turns a saved megabyte into an engine
/// that logs a missing asset on every start.
val wearPrunedFontFamilies = listOf("JetBrainsMono")

tasks.configureEach {
    // `copyFlutterAssets<Variant>` is a Copy into the merged assets directory,
    // registered by the Flutter plugin — so this runs once the assets are in
    // place and before they are packaged. Variants are wearDebug/wearProfile/
    // wearRelease; the mobile ones never match.
    if (!name.startsWith("copyFlutterAssetsWear")) return@configureEach
    doLast {
        // Gradle's Kotlin DSL gives `doLast` a Task receiver, not an `it`.
        val assets = (this as Copy).destinationDir.resolve("flutter_assets")
        var freed = 0L
        for (path in wearPrunedAssetPaths) {
            val target = assets.resolve(path)
            if (!target.exists()) continue
            freed += target.walkBottomUp().filter { f -> f.isFile }.sumOf { f -> f.length() }
            target.deleteRecursively()
        }

        val manifest = assets.resolve("FontManifest.json")
        if (manifest.exists()) {
            @Suppress("UNCHECKED_CAST")
            val families = groovy.json.JsonSlurper().parse(manifest) as List<Map<String, Any>>
            val keep = families.filterNot { family -> family["family"] in wearPrunedFontFamilies }
            if (keep.size != families.size) {
                for (family in families - keep.toSet()) {
                    @Suppress("UNCHECKED_CAST")
                    for (font in family["fonts"] as List<Map<String, Any>>) {
                        val file = assets.resolve(font["asset"] as String)
                        if (!file.exists()) continue
                        freed += file.length()
                        file.delete()
                    }
                }
                manifest.writeText(groovy.json.JsonOutput.toJson(keep))
            }
        }
        logger.lifecycle("wear: pruned ${freed / 1024} KiB of phone-only assets")
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Already on the classpath through watch_connectivity's `api` dependency,
    // declared here because `wear/WearRelayListenerService.kt` is our own code
    // and must not break if that plugin ever narrows it to `implementation`.
    // Keep the version equal to the plugin's.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    // Branded launch on the watch (Play's Wear quality check WO-V15). Wear OS 3
    // (API 30) has no system splash screen, so the icon on black only exists
    // there through this backport. Wear-only: the phone keeps Flutter's stock
    // launch theme, and — as with wear-input above — both flavors compile
    // `src/main`, so the call sits in each flavor's own BrandedLaunch.kt.
    "wearImplementation"("androidx.core:core-splashscreen:1.2.0")
}
