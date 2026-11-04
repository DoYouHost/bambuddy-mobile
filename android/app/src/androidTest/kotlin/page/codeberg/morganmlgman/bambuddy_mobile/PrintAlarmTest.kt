package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The print alarm on a real Android (#61, PrintAlarm.kt): what no host test can see — the
 * channel's audio, the notification's flags, the sound on a silenced phone, the screen over
 * the lock screen, and the three ways it stops.
 *
 * Run on the phone AVD (`just emu-boot pixel35`), after `flutter build apk --debug --flavor mobile`:
 *
 *     cd android && ./gradlew :app:connectedMobileDebugAndroidTest \
 *       -Pandroid.testInstrumentationRunnerArguments.class=page.codeberg.morganmlgman.bambuddy_mobile.PrintAlarmTest
 *
 * It turns the ringer to silent, the lock screen on and the screen off, and puts all three
 * back afterwards.
 */
class PrintAlarmTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val audio = context.getSystemService(AudioManager::class.java)
    private val pkg = context.packageName
    private var ringerBefore = AudioManager.RINGER_MODE_NORMAL

    @Before
    fun setUp() {
        shell("pm grant $pkg android.permission.POST_NOTIFICATIONS")
        shell("appops set $pkg USE_FULL_SCREEN_INTENT allow")
        ringerBefore = audio.ringerMode
        wakeAndUnlock()
    }

    @After
    fun tearDown() {
        PrintAlarm.stopAll(context)
        shell("cmd notification allow_dnd $pkg")
        audio.ringerMode = ringerBefore
        shell("cmd notification disallow_dnd $pkg")
        wakeAndUnlock()
    }

    @Test
    fun theChannelRingsAsAnAlarm() {
        assertTrue(ring(1))
        val channel = notifications.getNotificationChannel("print_alarm")
        assertNotNull(channel)
        assertEquals(AudioAttributes.USAGE_ALARM, channel.audioAttributes.usage)
        assertNotNull(channel.sound)
        assertEquals(NotificationManager.IMPORTANCE_HIGH, channel.importance)
    }

    @Test
    fun theNotificationLoopsAndTimesOut() {
        assertTrue(ring(1, minutes = 3))
        val posted = waitFor { active(1) }!!
        assertTrue(posted.flags and Notification.FLAG_INSISTENT != 0)
        assertEquals(Notification.CATEGORY_ALARM, posted.category)
        assertNotNull(posted.fullScreenIntent)
        assertEquals(3 * 60_000L, posted.timeoutAfter)
        assertEquals(STOP, posted.actions.single().title.toString())
        assertEquals("Printer 1", posted.extras.getCharSequence(Notification.EXTRA_SUB_TEXT))
    }

    @Test
    fun itRingsOnASilencedPhone() {
        shell("cmd notification allow_dnd $pkg")
        audio.ringerMode = AudioManager.RINGER_MODE_SILENT
        assertEquals(AudioManager.RINGER_MODE_SILENT, audio.ringerMode)
        assertTrue(audio.getStreamVolume(AudioManager.STREAM_ALARM) > 0)

        assertTrue(ring(1))
        // The system plays a notification's sound from its own process, so the
        // only witness is the audio service's list of what is playing.
        val playing = waitFor {
            shell("dumpsys audio").lines().firstOrNull {
                "usage=USAGE_ALARM" in it && "state:started" in it
            }
        }
        assertNotNull("no alarm-usage playback while silenced", playing)
    }

    @Test
    fun itTakesTheScreenOverTheLockScreen() {
        // An AVD often has its lock screen switched off, which would make this
        // pass without a lock screen to show over. A swipe lock, put back after.
        val lockWasDisabled = shell("locksettings get-disabled").trim() == "true"
        shell("locksettings set-disabled false")
        try {
            showsOverTheLockScreen()
        } finally {
            if (lockWasDisabled) shell("locksettings set-disabled true")
        }
    }

    private fun showsOverTheLockScreen() {
        sleep()
        assertTrue(ring(1))
        val power = context.getSystemService(PowerManager::class.java)
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        assertNotNull(
            "alarm screen not on top",
            waitFor { if (alarmOnTop() && power.isInteractive) true else null },
        )
        assertTrue("the phone was never locked", keyguard.isKeyguardLocked)
        // The screen is Flutter, which hands its text to accessibility as descriptions.
        assertNotNull(
            "the alarm screen drew nothing",
            device.wait(Until.findObject(By.pkg(pkg).desc(TITLE)), WAIT_MS),
        )
    }

    @Test
    fun stopOnTheScreenStopsEveryAlarm() {
        // On an awake, unlocked phone Android shows a full-screen intent as a
        // heads-up instead, whose Stop is the notification's own.
        sleep()
        assertTrue(ring(1))
        assertTrue(ring(2))
        assertNotNull("alarm screen not on top", waitFor { if (alarmOnTop()) true else null })
        // The app's own Stop: the second alarm's heads-up is SystemUI's and has one too.
        val button = By.pkg(pkg).desc(STOP)
        device.wait(Until.findObject(button), WAIT_MS)
            ?.click() ?: error("no Stop on the alarm screen")
        assertNotNull(waitFor { if (active(1) == null && active(2) == null) true else null })
        assertNotNull(waitFor { if (!alarmOnTop()) true else null })
    }

    @Test
    fun theScreenListsEveryPrinterAndKeepsTheOneStillRinging() {
        sleep()
        assertTrue(ring(1))
        assertTrue(ring(2))
        for (name in listOf("Printer 1", "Printer 2")) {
            assertNotNull(name, device.wait(Until.findObject(By.pkg(pkg).desc(name)), WAIT_MS))
        }
        // The notification's own Stop for one: the screen drops it and stays up.
        waitFor { active(1) }!!.actions.single().actionIntent.send()
        assertNotNull(waitFor { if (device.hasObject(By.pkg(pkg).desc("Printer 1"))) null else true })
        assertTrue(device.hasObject(By.pkg(pkg).desc("Printer 2")))
        assertTrue(alarmOnTop())
    }

    @Test
    fun stopOnTheNotificationStopsOnlyItsOwn() {
        assertTrue(ring(1))
        assertTrue(ring(2))
        waitFor { active(1) }!!.actions.single().actionIntent.send()
        assertNotNull(waitFor { if (active(1) == null) true else null })
        assertNotNull(active(2))
    }

    @Test
    fun aScreenPastItsDeadlineStopsTheAlarm() {
        assertTrue(ring(1))
        waitFor { active(1) }!!
        // The screen as it would come back after a sleep that outlasted the ring.
        context.startActivity(
            Intent(context, AlarmActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(PrintAlarm.EXTRA_ID, 1)
                .putExtra(PrintAlarm.EXTRA_STOP, STOP)
                .putExtra(PrintAlarm.EXTRA_DEADLINE, SystemClock.elapsedRealtime() - 1),
        )
        assertNotNull(waitFor { if (active(1) == null) true else null })
    }

    @Test
    fun itStopsOnItsOwnAfterTheTimeout() {
        assertTrue(ring(1, minutes = 1))
        waitFor { active(1) }!!
        assertNotNull(
            "still ringing after a minute",
            waitFor(timeoutMs = 75_000) { if (active(1) == null) true else null },
        )
        assertNotNull(waitFor { if (!alarmOnTop()) true else null })
    }

    // --- helpers ---

    private fun ring(id: Int, minutes: Int = 10) =
        PrintAlarm.ring(context, id, TITLE, "Benchy is done", STOP, minutes, printer = "Printer $id")

    private fun active(id: Int): Notification? =
        notifications.activeNotifications.firstOrNull { it.id == id }?.notification

    private fun alarmOnTop() =
        shell("dumpsys activity activities").lines().any {
            "ResumedActivity" in it && "AlarmActivity" in it
        }

    private fun sleep() {
        shell("input keyevent KEYCODE_SLEEP")
        val power = context.getSystemService(PowerManager::class.java)
        waitFor { if (!power.isInteractive) true else null }
    }

    private fun wakeAndUnlock() {
        shell("input keyevent KEYCODE_WAKEUP")
        shell("wm dismiss-keyguard")
    }

    private fun shell(command: String): String {
        val pfd = instrumentation.uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).bufferedReader().use { it.readText() }
    }

    private fun <T> waitFor(timeoutMs: Long = WAIT_MS, probe: () -> T?): T? {
        val end = SystemClock.uptimeMillis() + timeoutMs
        while (SystemClock.uptimeMillis() < end) {
            probe()?.let { return it }
            SystemClock.sleep(200)
        }
        return null
    }

    private companion object {
        const val TITLE = "Print finished"
        const val STOP = "Stop"
        const val WAIT_MS = 10_000L
    }
}
