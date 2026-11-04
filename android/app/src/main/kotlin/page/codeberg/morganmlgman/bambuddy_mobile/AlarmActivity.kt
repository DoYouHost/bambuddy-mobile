package page.codeberg.morganmlgman.bambuddy_mobile

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * The alarm screen over the lock screen: every alarm still ringing, each with its printer, and
 * one Stop button, drawn by Flutter from `alarmMain` (lib/features/alarm/alarm_screen.dart) in
 * an engine of its own. That entry point builds nothing of the app but this screen — it shows
 * while the phone is still locked (see [PrintAlarm]). Back leaves the alarm ringing; only Stop,
 * the notification's Stop or the timeout end it.
 */
class AlarmActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    override fun getDartEntrypointFunctionName() = "alarmMain"

    override fun onCreate(savedInstanceState: Bundle?) {
        wakeOverLockScreen()
        super.onCreate(savedInstanceState)
        PrintAlarm.screen = WeakReference(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "content" -> result.success(content())
                    // The screen lists every alarm ringing, so its one Stop stops them all.
                    "stop" -> {
                        PrintAlarm.stopAll(this@AlarmActivity)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // A later alarm can reach this screen while the display is off again.
        wakeOverLockScreen()
        refresh()
    }

    /** Pushes the alarms still ringing to the screen. */
    fun refresh() {
        channel?.invokeMethod("show", content())
    }

    override fun onResume() {
        super.onResume()
        // The timeout's Handler stalls while the CPU sleeps, so a screen the
        // sound already outlived would otherwise come back on the next wake.
        val deadline = intent.getLongExtra(PrintAlarm.EXTRA_DEADLINE, Long.MAX_VALUE)
        if (SystemClock.elapsedRealtime() >= deadline) {
            // stop, not finish: below API 26 nothing else cancels the sound. It closes
            // the screen with the last alarm and leaves it up while others still ring.
            PrintAlarm.stop(this, intent.getIntExtra(PrintAlarm.EXTRA_ID, 0))
            if (PrintAlarm.ringingNow().isEmpty()) finish()
        }
    }

    override fun onDestroy() {
        if (PrintAlarm.screen?.get() === this) PrintAlarm.screen = null
        super.onDestroy()
    }

    private fun content() = mapOf(
        "stop" to intent.getStringExtra(PrintAlarm.EXTRA_STOP),
        "alarms" to PrintAlarm.ringingNow(),
    )

    private fun wakeOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private companion object {
        const val CHANNEL = "page.codeberg.morganmlgman.bambuddy/alarm_screen"
    }
}
