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
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The print alarm on a real Android (#61, PrintAlarm.kt): what no host test can see — its own
 * player and the system-sound fallback, the notification's flags, the sound on a silenced phone
 * and under another app's notification, the screen over the lock screen, and the four ways it
 * stops, each reported to the bug-report log.
 *
 * Run on the phone AVD (`just emu-boot pixel35`), after `flutter build apk --debug --flavor mobile`:
 *
 *     cd android && ./gradlew :app:connectedMobileDebugAndroidTest \
 *       -Pandroid.testInstrumentationRunnerArguments.class=page.codeberg.morganmlgman.bambuddy_mobile.PrintAlarmTest
 *
 * In the phone flavor's own test sources: the watch strips the alarm, and Patrol runs every
 * class of its flavor's test APK there.
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
    private val reports = Reports()

    @Before
    fun setUp() {
        shell("pm grant $pkg android.permission.POST_NOTIFICATIONS")
        shell("appops set $pkg USE_FULL_SCREEN_INTENT allow")
        ringerBefore = audio.ringerMode
        wakeAndUnlock()
    }

    @After
    fun tearDown() {
        PrintAlarm.refuseFocusForTest = false
        PrintAlarm.clockOffsetForTest = 0
        PrintAlarm.stopAll(context)
        PrintAlarm.release(reports)
        device.pressHome()
        shell("cmd notification allow_dnd $pkg")
        audio.ringerMode = ringerBefore
        shell("cmd notification disallow_dnd $pkg")
        wakeAndUnlock()
    }

    @Test
    fun itRingsOnItsOwnPlayerBesideASilentChannel() {
        appInForeground()
        assertEquals(PrintAlarm.SOUND_PLAYER, sound(1))
        assertEquals(PrintAlarm.PLAYER_CHANNEL_ID, waitFor { active(1) }!!.channelId)
        val channel = notifications.getNotificationChannel(PrintAlarm.PLAYER_CHANNEL_ID)
        assertNull(channel.sound)
        assertTrue(channel.shouldVibrate())
        assertEquals(NotificationManager.IMPORTANCE_HIGH, channel.importance)
        assertNotNull("no alarm-usage playback", waitFor { playing("USAGE_ALARM") })
    }

    @Test
    fun aRefusedFocusRingsTheSystemSound() {
        PrintAlarm.refuseFocusForTest = true
        assertEquals(PrintAlarm.SOUND_SYSTEM, sound(1))
        assertEquals(PrintAlarm.SOUND_CHANNEL_ID, waitFor { active(1) }!!.channelId)
        val channel = notifications.getNotificationChannel(PrintAlarm.SOUND_CHANNEL_ID)
        assertEquals(AudioAttributes.USAGE_ALARM, channel.audioAttributes.usage)
        assertNotNull(channel.sound)
        assertNotNull("the fallback made no sound", waitFor { playing("USAGE_ALARM") })
    }

    @Test
    fun theLastStopSilencesThePlayer() {
        appInForeground()
        assertTrue(ring(1))
        assertTrue(ring(2))
        assertNotNull(waitFor { playing("USAGE_ALARM") })
        waitFor { active(1) }!!.actions.single().actionIntent.send()
        assertNotNull(waitFor { if (active(1) == null) true else null })
        assertNotNull("one alarm still rings", playing("USAGE_ALARM"))
        waitFor { active(2) }!!.actions.single().actionIntent.send()
        assertNotNull("the player outlived the last alarm", waitFor { if (playing("USAGE_ALARM") == null) true else null })
    }

    @Test
    fun theNotificationLoopsAndTimesOut() {
        assertTrue(ring(1, minutes = 3))
        val posted = waitFor { active(1) }!!
        assertTrue(posted.flags and Notification.FLAG_INSISTENT != 0)
        assertEquals(Notification.CATEGORY_ALARM, posted.category)
        assertNotNull(posted.fullScreenIntent)
        // Counted from the alarm's deadline, so a few milliseconds have gone by.
        assertTrue(posted.timeoutAfter in (3 * 60_000L - 5_000)..(3 * 60_000L))
        assertEquals(STOP, posted.actions.single().title.toString())
        assertEquals("Printer 1", posted.extras.getCharSequence(Notification.EXTRA_SUB_TEXT))
    }

    @Test
    fun itRingsOnASilencedPhone() {
        shell("cmd notification allow_dnd $pkg")
        audio.ringerMode = AudioManager.RINGER_MODE_SILENT
        assertEquals(AudioManager.RINGER_MODE_SILENT, audio.ringerMode)
        assertTrue(audio.getStreamVolume(AudioManager.STREAM_ALARM) > 0)

        appInForeground()
        assertTrue(ring(1))
        assertEquals(PrintAlarm.PLAYER_CHANNEL_ID, waitFor { active(1) }!!.channelId)
        assertNotNull("no alarm-usage playback while silenced", waitFor { playing("USAGE_ALARM") })
    }

    @Test
    fun anotherAppsNotificationDoesNotCutTheLoop() {
        appInForeground()
        assertTrue(ring(1))
        assertEquals(PrintAlarm.PLAYER_CHANNEL_ID, waitFor { active(1) }!!.channelId)
        assertNotNull("the alarm never started", waitFor { playing("USAGE_ALARM") })
        // Posted as the shell, so it is another app with a sound of its own.
        shell("cmd notification post -t Ping $OTHER_TAG 'Another app'")
        // The other sound has to have played, or the check below proves nothing.
        assertNotNull(
            "the other notification made no sound",
            waitFor { playing("USAGE_NOTIFICATION") },
        )
        SystemClock.sleep(3_000)
        assertNotNull(
            "the alarm went quiet after another app's notification",
            playing("USAGE_ALARM"),
        )
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
        listen()
        assertNotNull("alarm screen not on top", waitFor { if (alarmOnTop()) true else null })
        // The app's own Stop: the second alarm's heads-up is SystemUI's and has one too.
        val button = By.pkg(pkg).desc(STOP)
        device.wait(Until.findObject(button), WAIT_MS)
            ?.click() ?: error("no Stop on the alarm screen")
        assertNotNull(waitFor { if (active(1) == null && active(2) == null) true else null })
        assertNotNull(waitFor { if (!alarmOnTop()) true else null })
        assertEquals(listOf(1 to "screen", 2 to "screen"), reports.stops(2))
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
        listen()
        waitFor { active(1) }!!.actions.single().actionIntent.send()
        assertNotNull(waitFor { if (active(1) == null) true else null })
        assertNotNull(active(2))
        assertEquals(listOf(1 to "notification"), reports.stops(1))
    }

    @Test
    fun aScreenPastEveryDeadlineStopsEveryAlarm() {
        appInForeground()
        assertTrue(ring(1, minutes = 10))
        assertTrue(ring(2, minutes = 5))
        waitFor { active(2) }!!
        listen()
        // The screen as it would come back after a sleep that outlasted both rings.
        PrintAlarm.clockOffsetForTest = 11 * 60_000L
        context.startActivity(
            Intent(context, AlarmActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(PrintAlarm.EXTRA_STOP, STOP),
        )
        assertNotNull(waitFor { if (active(1) == null && active(2) == null) true else null })
        assertNotNull("the player outlived the alarms", waitFor { if (playing("USAGE_ALARM") == null) true else null })
        assertEquals(listOf(1 to "expired", 2 to "expired"), reports.stops(2))
        assertEquals(PrintAlarm.SOUND_PLAYER, reports.calls.first().argument<String>("sound"))
        // The offset is in the ring's age too: it rang 11 minutes as far as the alarm can tell.
        // A Kotlin Long, which the codec keeps a Long.
        assertTrue(reports.calls.first().argument<Long>("rang_s")!! >= 660)
    }

    @Test
    fun anAlarmOnTheSystemSoundKeepsTheNextOneThere() {
        PrintAlarm.refuseFocusForTest = true
        assertTrue(ring(1))
        PrintAlarm.refuseFocusForTest = false
        appInForeground()
        assertTrue(ring(2))
        assertEquals(PrintAlarm.SOUND_CHANNEL_ID, waitFor { active(2) }!!.channelId)
    }

    @Test
    fun itStopsOnItsOwnAfterTheTimeout() {
        assertTrue(ring(1, minutes = 1))
        waitFor { active(1) }!!
        listen()
        assertNotNull(
            "still ringing after a minute",
            waitFor(timeoutMs = 75_000) { if (active(1) == null) true else null },
        )
        assertNotNull(waitFor { if (!alarmOnTop()) true else null })
        assertEquals(listOf(1 to "timeout"), reports.stops(1))
    }

    // --- helpers ---

    /**
     * Android refuses the audio focus to an app with neither a visible activity nor a foreground
     * service ("Audio focus request blocked by hardening"), and this test process has no service.
     * In the app the monitor's service is what lets the player ring.
     */
    private fun appInForeground() {
        context.startActivity(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        // Resumed in this process, not in dumpsys: the system lists the activity as resumed
        // before its onCreate has run, and with it the engine's PrintAlarm.serve, which
        // would then land after listen() and take the reports.
        assertNotNull(
            "the app never came to the front",
            waitFor {
                var resumed = false
                instrumentation.runOnMainSync {
                    resumed = ActivityLifecycleMonitorRegistry.getInstance()
                        .getActivitiesInStage(Stage.RESUMED).any { it is MainActivity }
                }
                if (resumed) true else null
            },
        )
    }

    private fun sound(id: Int, minutes: Int = 10) =
        PrintAlarm.ring(context, id, TITLE, "Benchy is done", STOP, minutes, printer = "Printer $id")

    private fun ring(id: Int, minutes: Int = 10) = sound(id, minutes) != null

    /**
     * Makes [reports] the newest engine on the alarm channel. After [appInForeground]: the app's
     * own engine would be newer, and take the reports.
     */
    private fun listen() {
        PrintAlarm.serve(reports, context, activity = null)
    }

    /** Stands in for an engine: keeps every call the alarm makes to Dart. */
    private inner class Reports : BinaryMessenger {
        val calls = CopyOnWriteArrayList<io.flutter.plugin.common.MethodCall>()

        override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)

        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            message?.let { calls += StandardMethodCodec.INSTANCE.decodeMethodCall(it.rewind() as ByteBuffer) }
        }

        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit

        /** The first [count] stops, as (id, why), once that many arrived. */
        fun stops(count: Int): List<Pair<Int, String>>? = waitFor {
            calls.filter { it.method == "stopped" }
                .takeIf { it.size >= count }
                ?.map { it.argument<Int>("id")!! to it.argument<String>("why")!! }
        }
    }

    private fun active(id: Int): Notification? =
        notifications.activeNotifications.firstOrNull { it.id == id }?.notification

    /** A started player of this usage, from the audio service's list of what is playing. */
    private fun playing(usage: String): String? =
        shell("dumpsys audio").lines().firstOrNull { "usage=$usage" in it && "state:started" in it }

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
        const val OTHER_TAG = "other_app"
    }
}
