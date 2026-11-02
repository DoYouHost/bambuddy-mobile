package page.codeberg.morganmlgman.bambuddy_mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.text.format.DateFormat
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/** What one channel method does; it answers [MethodChannel.Result] itself. */
private typealias MethodHandler = (MethodCall, MethodChannel.Result) -> Unit

/**
 * Native side of four platform channels.
 *
 * `battery` is a bridge to the battery-optimization state: the Dart side asks whether the app
 * is exempt and, at the user's request, opens the app's settings page — that exemption is what
 * unblocks starting a foreground service from the background on Android 12+ and saves the
 * process from an OEM killer (critical on Samsung).
 *
 * `clock` answers whether the user reads a 24-hour clock. Flutter learns that once, when
 * the view attaches, and never again — so an app that was running while the switch was flipped
 * keeps the old `MediaQuery` value until the process dies, and the foreground service's engine
 * is never told at all (`lib/core/format/datetime_format.dart`).
 *
 * `wear_shape` answers whether the display is round. Flutter never surfaces that: a round
 * watch face is not reported as a view inset, so `SafeArea` resolves to zero on it and the
 * layout has to inset itself (`lib/wear/wear_geometry.dart`).
 *
 * `window` holds the screen on while wall mode is up (`lib/features/wall/`). A window flag
 * rather than a wake lock: it needs no permission, acts only while this window is visible,
 * and so needs nothing re-asserted on resume. It also dims this window's backlight while
 * the controller's screen saver is up — the window's own `screenBrightness`, not the
 * system setting, so it needs no permission either and ends with the window.
 */
class MainActivity : FlutterActivity() {

    // Before super: FlutterActivity swaps the window to NormalTheme in its own onCreate,
    // and the splash has to be installed while the launch theme is still the one applied.
    // Does nothing in the phone flavor — see BrandedLaunch.kt in each flavor source set.
    override fun onCreate(savedInstanceState: Bundle?) {
        installBrandedLaunch()
        super.onCreate(savedInstanceState)
    }

    // Null in the phone flavor, which keeps an engine per activity — see WearOngoing.kt in each
    // flavor source set.
    override fun provideFlutterEngine(context: Context): FlutterEngine? = wearEngine()

    /**
     * The watch's engine outlives this activity, so nothing it can still call may lead back
     * here: these handlers would act on a destroyed window, and keep it from being collected.
     * The next activity registers its own in [configureFlutterEngine].
     */
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        for (channel in listOf(BATTERY_CHANNEL, CLOCK_CHANNEL, WEAR_SHAPE_CHANNEL, WINDOW_CHANNEL)) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler(null)
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.serveWearOngoing(this)
        flutterEngine.serveWearPhoneApp(this)
        flutterEngine.serveWatchFaceColours(this)
        flutterEngine.serve(
            BATTERY_CHANNEL,
            mapOf<String, MethodHandler>(
                "isIgnoringBatteryOptimizations" to { _, result ->
                    result.success(isIgnoringBatteryOptimizations())
                },
                "openBatterySettings" to { _, result ->
                    openBatterySettings()
                    result.success(null)
                }
            )
        )
        flutterEngine.serve(
            CLOCK_CHANNEL,
            mapOf<String, MethodHandler>(
                // The resolved setting, locale default included — the same value Android
                // itself formats notification timestamps with, and the same one Flutter
                // would have pushed as `alwaysUse24HourFormat` had it pushed anything.
                "is24HourFormat" to { _, result ->
                    result.success(DateFormat.is24HourFormat(this))
                },
                // The IANA id Dart cannot name: `DateTime.timeZoneName` is "CET".
                "timeZone" to { _, result ->
                    result.success(TimeZone.getDefault().id)
                }
            )
        )
        flutterEngine.serve(
            WEAR_SHAPE_CHANNEL,
            mapOf<String, MethodHandler>(
                // Read per call rather than cached: the value comes from the current
                // Configuration, and an activity that is recreated for a configuration
                // change asks again anyway.
                "isScreenRound" to { _, result ->
                    result.success(resources.configuration.isScreenRound)
                }
            )
        )
        flutterEngine.serve(
            WINDOW_CHANNEL,
            mapOf<String, MethodHandler>(
                "keepScreenOn" to { call, result ->
                    val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(flag)
                    } else {
                        window.clearFlags(flag)
                    }
                    result.success(null)
                },
                // `level` 0..1 overrides the backlight for this window only; null hands it
                // back to the system setting.
                "screenBrightness" to { call, result ->
                    val level = call.argument<Double>("level")
                    window.attributes = window.attributes.apply {
                        screenBrightness = level?.toFloat()?.coerceIn(0f, 1f)
                            ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    }
                    result.success(null)
                }
            )
        )
    }

    /**
     * Register [channel] with one handler per method, and one answer for a method that has
     * none.
     *
     * That fallback is the native half of the policy `PlatformQuery` states on the Dart
     * side: a host that does not implement something says so, so the caller falls back to
     * what a device without the feature would give instead of waiting for an answer that
     * is not coming.
     */
    private fun FlutterEngine.serve(channel: String, methods: Map<String, MethodHandler>) {
        MethodChannel(dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            val handler = methods[call.method]
            if (handler == null) result.notImplemented() else handler(call, result)
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun openBatterySettings() {
        // This app's own settings page, one tap from its battery setting. The direct
        // exemption dialog would need REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, which Play
        // refuses for a print monitor.
        val appPage = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        try {
            startActivity(appPage)
        } catch (_: Exception) {
            // No settings app on this device — nothing more we can do.
        }
    }

    private companion object {
        const val BATTERY_CHANNEL = "page.codeberg.morganmlgman.bambuddy/battery"
        const val WEAR_SHAPE_CHANNEL = "page.codeberg.morganmlgman.bambuddy/wear_shape"
        const val CLOCK_CHANNEL = "page.codeberg.morganmlgman.bambuddy/clock"
        const val WINDOW_CHANNEL = "page.codeberg.morganmlgman.bambuddy/window"
    }
}
