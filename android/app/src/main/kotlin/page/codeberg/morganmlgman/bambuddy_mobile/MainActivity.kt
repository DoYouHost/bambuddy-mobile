package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native side of two platform channels.
 *
 * `battery` is a bridge to the battery-optimization state: the Dart side asks whether the app
 * is exempt and, at the user's request, fires the system prompt — that exemption is what
 * unblocks starting a foreground service from the background on Android 12+ and saves the
 * process from an OEM killer (critical on Samsung).
 *
 * `wear_input` is text entry on the watch — see [requestWearText].
 */
class MainActivity : FlutterActivity() {

    /** The Dart caller waiting for the watch input activity to come back. */
    private var pendingWearText: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" ->
                        result.success(isIgnoringBatteryOptimizations())
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WEAR_INPUT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Answered from the device feature, not by resolving the intent:
                    // Android 11 package visibility filters a query for an activity we
                    // are still allowed to launch, so resolveActivity would report a
                    // false negative here.
                    "isSupported" ->
                        result.success(packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH))
                    "requestText" -> requestWearText(call.argument<String>("label"), result)
                    else -> result.notImplemented()
                }
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
