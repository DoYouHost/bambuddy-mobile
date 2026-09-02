package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import android.text.format.DateFormat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * What one channel method does. It answers [MethodChannel.Result] itself rather than
 * returning a value, because one of them (`requestText`) only answers once an activity
 * comes back.
 */
private typealias MethodHandler = (MethodCall, MethodChannel.Result) -> Unit

/**
 * Native side of four platform channels.
 *
 * `battery` is a bridge to the battery-optimization state: the Dart side asks whether the app
 * is exempt and, at the user's request, fires the system prompt — that exemption is what
 * unblocks starting a foreground service from the background on Android 12+ and saves the
 * process from an OEM killer (critical on Samsung).
 *
 * `wear_input` is text entry on the watch — see [requestWearText].
 *
 * `clock` answers whether the user reads a 24-hour clock. Flutter learns that once, when
 * the view attaches, and never again — so an app that was running while the switch was flipped
 * keeps the old `MediaQuery` value until the process dies, and the foreground service's engine
 * is never told at all (`lib/core/format/datetime_format.dart`).
 *
 * `wear_shape` answers whether the display is round. Flutter never surfaces that: a round
 * watch face is not reported as a view inset, so `SafeArea` resolves to zero on it and the
 * layout has to inset itself (`lib/wear/wear_geometry.dart`).
 */
class MainActivity : FlutterActivity() {

    /** The Dart caller waiting for the watch input activity to come back. */
    private var pendingWearText: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.serve(
            BATTERY_CHANNEL,
            mapOf<String, MethodHandler>(
                "isIgnoringBatteryOptimizations" to { _, result ->
                    result.success(isIgnoringBatteryOptimizations())
                },
                "requestIgnoreBatteryOptimizations" to { _, result ->
                    requestIgnoreBatteryOptimizations()
                    result.success(null)
                }
            )
        )
        flutterEngine.serve(
            WEAR_INPUT_CHANNEL,
            mapOf<String, MethodHandler>(
                // Answered from the device feature, not by resolving the intent:
                // Android 11 package visibility filters a query for an activity we
                // are still allowed to launch, so resolveActivity would report a
                // false negative here.
                "isSupported" to { _, result ->
                    result.success(packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH))
                },
                "requestText" to { call, result ->
                    requestWearText(call.argument<String>("label"), result)
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

    /**
     * Hand text entry over to the watch's own input activity (keyboard, handwriting, dictation).
     *
     * A Flutter `TextField` has no working soft-keyboard path on Wear OS: the engine stamps
     * `IME_FLAG_NO_FULLSCREEN` on every EditorInfo while the watch IME is a fullscreen window of
     * its own, and the app is never even handed a bottom inset to scroll the field clear of it
     * (measured on a Wear AVD: the IME reports `onShown`, `viewInsets.bottom` stays 0). On a
     * Pixel Watch 3 it does not appear at all. RemoteInput is the entry path Wear apps are
     * expected to use, and it is not subject to any of the above.
     */
    private fun requestWearText(label: String?, result: MethodChannel.Result) {
        if (pendingWearText != null) {
            result.error("busy", "A text request is already open", null)
            return
        }
        val remoteInput = RemoteInput.Builder(WEAR_TEXT_KEY).setLabel(label.orEmpty()).build()
        val intent = Intent(ACTION_REMOTE_INPUT)
            .putExtra(EXTRA_REMOTE_INPUTS, arrayOf(remoteInput))
        if (!label.isNullOrEmpty()) intent.putExtra(EXTRA_TITLE, label)
        pendingWearText = result
        try {
            startActivityForResult(intent, REQUEST_WEAR_TEXT)
        } catch (e: Exception) {
            // Deliberately broad. Beyond a missing activity, a skin that keeps its input
            // activity behind a permission answers with SecurityException — and a crash
            // there would take away the field the Dart side falls back to.
            pendingWearText = null
            result.error("unavailable", "Cannot open the remote input activity: $e", null)
        }
    }

    // Should the activity be recreated while the input screen is up, the reply is dropped and the
    // Dart future never completes — the field keeps its old value and the next tap starts over.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_WEAR_TEXT) {
            val pending = pendingWearText
            pendingWearText = null
            val text = data
                ?.let { RemoteInput.getResultsFromIntent(it) }
                ?.getCharSequence(WEAR_TEXT_KEY)
                ?.toString()
            pending?.success(if (resultCode == RESULT_OK) text else null)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        // Ask for this one app directly (system dialog). Should a manufacturer have blocked or
        // hidden that screen, fall back to the full list.
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        try {
            startActivity(direct)
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
                // No such screen on this device — nothing more we can do.
            }
        }
    }

    private companion object {
        const val BATTERY_CHANNEL = "page.codeberg.morganmlgman.bambuddy/battery"
        const val WEAR_INPUT_CHANNEL = "page.codeberg.morganmlgman.bambuddy/wear_input"
        const val WEAR_SHAPE_CHANNEL = "page.codeberg.morganmlgman.bambuddy/wear_shape"
        const val CLOCK_CHANNEL = "page.codeberg.morganmlgman.bambuddy/clock"

        const val WEAR_TEXT_KEY = "bambuddy_wear_text"
        const val REQUEST_WEAR_TEXT = 0x7EA1

        // Copied from androidx.wear.input.RemoteInputIntentHelper, which keeps them private.
        // Inlining them keeps androidx.wear:wear-input out of the phone flavor: both flavors
        // compile this one source set, so a wear-only dependency would break the phone build.
        // The extra carries platform android.app.RemoteInput parcelables, not the AndroidX ones.
        const val ACTION_REMOTE_INPUT = "android.support.wearable.input.action.REMOTE_INPUT"
        const val EXTRA_REMOTE_INPUTS = "android.support.wearable.input.extra.REMOTE_INPUTS"
        const val EXTRA_TITLE = "android.support.wearable.input.extra.TITLE"
    }
}
