package page.codeberg.morganmlgman.bambuddy_mobile

import android.content.Context
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val WATCH_FACE_COLOURS_CHANNEL = "page.codeberg.morganmlgman.bambuddy/watch_face_colours"

// Wear Compose Material 3's `isDynamicColorSchemeEnabled`: off, the system colour
// resources still answer, with defaults that have nothing to do with the face.
private const val DYNAMIC_THEMING_SETTING = "dynamic_color_theme_enabled"

/**
 * The watch face's colour roles, read the way Wear Compose Material 3's
 * `dynamicColorScheme` reads them (androidx-main `DynamicColorScheme.kt`), keyed by
 * the Flutter `ColorScheme` field each one fills. Null where that function returns
 * null: below Android 15, or with dynamic theming switched off.
 */
fun FlutterEngine.serveWatchFaceColours(context: Context) {
    val app = context.applicationContext
    MethodChannel(dartExecutor.binaryMessenger, WATCH_FACE_COLOURS_CHANNEL).setMethodCallHandler { call, result ->
        if (call.method == "roles") result.success(watchFaceRoles(app)) else result.notImplemented()
    }
}

private fun watchFaceRoles(context: Context): Map<String, Int>? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return null
    if (Settings.Global.getInt(context.contentResolver, DYNAMIC_THEMING_SETTING, 0) != 1) return null
    return mapOf(
        "primary" to android.R.color.system_primary_fixed,
        "onPrimary" to android.R.color.system_on_primary_fixed,
        "primaryContainer" to android.R.color.system_primary_container_dark,
        "onPrimaryContainer" to android.R.color.system_on_primary_container_dark,
        "secondary" to android.R.color.system_secondary_fixed,
        "onSecondary" to android.R.color.system_on_secondary_fixed,
        "secondaryContainer" to android.R.color.system_secondary_container_dark,
        "onSecondaryContainer" to android.R.color.system_on_secondary_container_dark,
        "tertiary" to android.R.color.system_tertiary_fixed,
        "onTertiary" to android.R.color.system_on_tertiary_fixed,
        "tertiaryContainer" to android.R.color.system_tertiary_container_dark,
        "onTertiaryContainer" to android.R.color.system_on_tertiary_container_dark,
        "surfaceContainerLow" to android.R.color.system_surface_container_low_dark,
        "surfaceContainer" to android.R.color.system_surface_container_dark,
        "surfaceContainerHigh" to android.R.color.system_surface_container_high_dark,
        "onSurface" to android.R.color.system_on_surface_dark,
        "onSurfaceVariant" to android.R.color.system_on_surface_variant_dark,
        "outline" to android.R.color.system_outline_dark,
        "outlineVariant" to android.R.color.system_outline_variant_dark,
        "error" to android.R.color.system_error_dark,
        "onError" to android.R.color.system_on_error_dark,
        "errorContainer" to android.R.color.system_error_container_dark,
        "onErrorContainer" to android.R.color.system_on_error_container_dark,
    ).mapValues { context.resources.getColor(it.value, null) }
}
