package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.util.TypedValue
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.lang.ref.WeakReference

/**
 * The alarm screen over the lock screen: what happened and one Stop button. It deliberately
 * offers no way into the app — it shows while the phone is still locked (see [PrintAlarm]).
 * Back leaves the alarm ringing; only Stop, the notification's Stop or the timeout end it.
 * Scrolls, so Stop stays reachable in landscape or at a large font.
 */
class AlarmActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        wakeOverLockScreen()
        show(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // A later alarm can reach this screen while the display is off again.
        wakeOverLockScreen()
        show(intent)
    }

    override fun onResume() {
        super.onResume()
        // The timeout's Handler stalls while the CPU sleeps, so a screen the
        // sound already outlived would otherwise come back on the next wake.
        val deadline = intent.getLongExtra(PrintAlarm.EXTRA_DEADLINE, Long.MAX_VALUE)
        if (SystemClock.elapsedRealtime() >= deadline) {
            // stop, not finish: below API 26 nothing else cancels the sound.
            PrintAlarm.stop(this, intent.getIntExtra(PrintAlarm.EXTRA_ID, 0))
            finish()
        }
    }

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

    override fun onDestroy() {
        if (PrintAlarm.screen?.get() === this) PrintAlarm.screen = null
        super.onDestroy()
    }

    private fun show(intent: Intent) {
        PrintAlarm.screen = WeakReference(this)
        val pad = dp(24)
        val content =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(pad, pad, pad, pad)
                addView(text(intent.getStringExtra(PrintAlarm.EXTRA_TITLE), 32f))
                addView(text(intent.getStringExtra(PrintAlarm.EXTRA_BODY), 20f))
                addView(
                    Button(this@AlarmActivity).apply {
                        text = intent.getStringExtra(PrintAlarm.EXTRA_STOP)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
                        minHeight = dp(72)
                        setOnClickListener { PrintAlarm.stopAll(this@AlarmActivity) }
                    },
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { topMargin = dp(48) },
                )
            }
        setContentView(ScrollView(this).apply { isFillViewport = true; addView(content) })
    }

    private fun text(value: String?, sp: Float) = TextView(this).apply {
        text = value
        gravity = Gravity.CENTER
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
        setPadding(0, dp(8), 0, dp(8))
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
