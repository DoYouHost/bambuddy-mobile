package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import androidx.annotation.VisibleForTesting
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * The print alarm (#61): a notification that rings at alarm volume in a loop and, when the
 * user has granted full-screen intents, raises [AlarmActivity] over the lock screen.
 *
 * Native because `flutter_local_notifications` can only aim a full-screen intent at the
 * launcher activity, and showing `MainActivity` over the keyguard would hand the whole app —
 * stopping a print included — to whoever picks up the locked phone. [AlarmActivity] shows the
 * text and a Stop button, nothing else.
 *
 * The sound is this object's own [MediaPlayer] at alarm usage, looping until the last alarm
 * stops: a notification's sound is cut by the next noisy notification of any app. When Android
 * refuses the audio focus — Android 17 does for a background app it will not let play — the
 * notification rings on [SOUND_CHANNEL_ID] instead, played by the system, so the alarm is never
 * silent. Either way it rings with or without the full-screen permission.
 */
object PrintAlarm {
    const val METHOD_CHANNEL = "page.codeberg.morganmlgman.bambuddy/alarm"

    /** The fallback, whose sound the system plays. The id of the channel before the player. */
    const val SOUND_CHANNEL_ID = "print_alarm"

    /** Beside [player]: vibrates, makes no sound of its own. */
    const val PLAYER_CHANNEL_ID = "print_alarm_player"
    private const val ACTION_STOP = "page.codeberg.morganmlgman.bambuddy_mobile.ALARM_STOP"

    const val EXTRA_ID = "id"
    const val EXTRA_STOP = "stop"

    /** What [ring] answers, and what the bug-report log calls each sound. */
    const val SOUND_PLAYER = "player"
    const val SOUND_SYSTEM = "system"

    private val main = Handler(Looper.getMainLooper())

    /** Each alarm's own timeout, so ringing an id again restarts its clock. */
    private val timeouts = mutableMapOf<Int, Runnable>()

    /** Every alarm still ringing, oldest first: the screen lists them all. */
    private val ringing = LinkedHashMap<Int, Ring>()

    /** The alarm screen on display, so a Stop from the notification reaches it too. */
    var screen: WeakReference<AlarmActivity>? = null

    /**
     * Every engine serving the channel, newest last. A stop is reported to the newest only, so the
     * log holds it once: the service's engine goes when the app comes back while the alarm rings.
     */
    private val hosts = LinkedHashMap<BinaryMessenger, MethodChannel>()

    /** One sound for every alarm ringing; null while none is, or while the fallback rings. */
    private var player: MediaPlayer? = null
    private var focus: AudioFocusRequest? = null

    /** Lets a device test take the path Android 17 forces on a background app. */
    @VisibleForTesting
    var refuseFocusForTest = false

    /** Every alarm still ringing, newest first, as the screen shows them. */
    fun ringingNow(): List<Map<String, String>> =
        ringing.values.reversed().map { mapOf("title" to it.title, "body" to it.body, "printer" to it.printer) }

    /**
     * Serves the alarm channel on [messenger]. [activity] is null on the foreground service's
     * engine, which can ring but has no screen to open the permission page from.
     */
    fun serve(messenger: BinaryMessenger, context: Context, activity: Activity?): MethodChannel =
        MethodChannel(messenger, METHOD_CHANNEL).also { hosts.remove(messenger); hosts[messenger] = it }.apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "ring" -> result.success(
                        ring(
                            context,
                            id = call.argument<Int>("id") ?: 0,
                            title = call.argument<String>("title").orEmpty(),
                            body = call.argument<String>("body").orEmpty(),
                            stopLabel = call.argument<String>("stop").orEmpty(),
                            minutes = call.argument<Int>("minutes") ?: 10,
                            printer = call.argument<String>("printer").orEmpty(),
                        )
                    )
                    "canFullScreen" -> result.success(canFullScreen(context))
                    "openFullScreenSettings" -> {
                        if (activity == null) result.success(false)
                        else result.success(openFullScreenSettings(activity))
                    }
                    else -> result.notImplemented()
                }
            }
        }

    /** The engine behind [messenger] is going: nothing may be reported to it any more. */
    fun release(messenger: BinaryMessenger) {
        hosts.remove(messenger)?.setMethodCallHandler(null)
    }

    /**
     * Tells the newest engine, whose Dart side writes it to the bug-report log. Posted: an engine
     * takes calls on the main thread only, and a test stops alarms from its own.
     */
    private fun report(method: String, fields: Map<String, Any>) {
        main.post { hosts.values.lastOrNull()?.invokeMethod(method, fields) }
    }

    fun canFullScreen(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
            context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()

    private fun openFullScreenSettings(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
        return try {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                    .setData(Uri.parse("package:${activity.packageName}"))
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun alarmSound(): Uri? =
        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

    private val alarmAttributes: AudioAttributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

    private fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // Sound and usage are frozen once a channel exists; changing them means a new id.
        fun channel(id: String, name: String, sound: Uri?) =
            NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Rings when a print ends or stops, or drying finishes"
                setSound(sound, sound?.let { alarmAttributes })
                enableVibration(true)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }
        context.getSystemService(NotificationManager::class.java).createNotificationChannels(
            listOf(
                channel(PLAYER_CHANNEL_ID, "Print alarm", null),
                channel(SOUND_CHANNEL_ID, "Print alarm (system sound)", alarmSound()),
            )
        )
    }

    /** Whether the user switched [id] off in the system settings. */
    private fun blocked(context: Context, id: String): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            context.getSystemService(NotificationManager::class.java)
                .getNotificationChannel(id)?.importance == NotificationManager.IMPORTANCE_NONE

    /**
     * Starts the looping sound unless it already plays. False when Android refuses the focus or
     * the tone will not play: the caller rings the notification's own sound instead.
     */
    private fun startPlayer(context: Context): Boolean {
        if (player != null) return true
        val audio = context.getSystemService(AudioManager::class.java)
        if (refuseFocusForTest || !requestFocus(audio)) return false
        val app = context.applicationContext
        val started = alarmSound()?.let { sound ->
            val candidate = MediaPlayer()
            try {
                candidate.apply {
                    setAudioAttributes(alarmAttributes)
                    setDataSource(app, sound)
                    isLooping = true
                    setOnErrorListener { failed, _, _ ->
                        if (failed === player) recover(app)
                        true
                    }
                    prepare()
                    start()
                }
            } catch (_: Exception) {
                candidate.release()
                null
            }
        }
        if (started == null) {
            abandonFocus(audio)
            return false
        }
        player = started
        return true
    }

    private fun stopPlayer(context: Context) {
        val playing = player ?: return
        player = null
        try {
            playing.stop()
        } catch (_: IllegalStateException) {
        }
        playing.release()
        abandonFocus(context.getSystemService(AudioManager::class.java))
    }

    private fun requestFocus(audio: AudioManager): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            return audio.requestAudioFocus(ignoreFocus, AudioManager.STREAM_ALARM, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT) ==
                AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(alarmAttributes)
            .setOnAudioFocusChangeListener(ignoreFocus)
            .build()
        if (audio.requestAudioFocus(request) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) return false
        focus = request
        return true
    }

    /** An alarm rings on through a call or another app's sound; Stop and the timeout end it. */
    private val ignoreFocus = AudioManager.OnAudioFocusChangeListener { }

    private fun abandonFocus(audio: AudioManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            audio.abandonAudioFocus(ignoreFocus)
            return
        }
        focus?.let(audio::abandonAudioFocusRequest)
        focus = null
    }

    /**
     * Posts the alarm, and answers [SOUND_PLAYER] or [SOUND_SYSTEM] for the sound it rings with.
     * Null when notifications are off for the app, so nothing could ring.
     */
    fun ring(
        context: Context,
        id: Int,
        title: String,
        body: String,
        stopLabel: String,
        minutes: Int,
        printer: String,
    ): String? {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return null
        ensureChannels(context)
        // Switching the alarm's channel off in the system settings is a way to silence it.
        if (blocked(context, PLAYER_CHANNEL_ID)) return null
        val ringFor = minutes.coerceIn(1, 30) * 60_000L
        // An alarm already on the system sound keeps the rest there: two tones at once.
        val ownSound = (ringing.isEmpty() || player != null) && startPlayer(context)
        if (!ownSound && blocked(context, SOUND_CHANNEL_ID)) return null
        val alarm = Ring(title, body, printer, stopLabel, now(), now() + ringFor)
        if (!post(context, id, alarm, ownSound)) {
            if (ringing.isEmpty()) stopPlayer(context)
            return null
        }
        // Re-inserted, so a ring under an id already listed moves to the newest.
        ringing.remove(id)
        ringing[id] = alarm
        screen?.get()?.refresh()
        // setTimeoutAfter only removes the notification, and is a no-op below API 26; the
        // player and the screen go with this. The application context: the test alarm is
        // rung from MainActivity, which this map must not keep alive.
        val app = context.applicationContext
        val timeout = Runnable { stop(app, id, "timeout") }
        timeouts.put(id, timeout)?.let(main::removeCallbacks)
        main.postDelayed(timeout, ringFor)
        return alarm.sound
    }

    private fun post(context: Context, id: Int, alarm: Ring, ownSound: Boolean): Boolean {
        val openScreen = PendingIntent.getActivity(
            context, id,
            Intent(context, AlarmActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION)
                .putExtra(EXTRA_STOP, alarm.stopLabel),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getBroadcast(
            context, id,
            Intent(context, AlarmStopReceiver::class.java).setAction(ACTION_STOP).putExtra(EXTRA_ID, id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarm.sound = if (ownSound) SOUND_PLAYER else SOUND_SYSTEM
        val notification = NotificationCompat.Builder(context, if (ownSound) PLAYER_CHANNEL_ID else SOUND_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(alarm.title)
            .setContentText(alarm.body)
            .setSubText(alarm.printer.ifBlank { null })
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            // Below API 26 there is no channel to carry the sound.
            .setSound(if (ownSound) null else alarmSound(), AudioManager.STREAM_ALARM)
            .setFullScreenIntent(openScreen, true)
            .setContentIntent(openScreen)
            .setDeleteIntent(stop)
            .addAction(0, alarm.stopLabel, stop)
            .setTimeoutAfter((alarm.deadline - now()).coerceAtLeast(1))
            .setOngoing(true)
            .build()
            // Loops the vibration, and the fallback's sound.
            .apply { flags = flags or android.app.Notification.FLAG_INSISTENT }
        return try {
            NotificationManagerCompat.from(context).notify(id, notification)
            true
        } catch (_: SecurityException) {
            false
        }
    }

    /**
     * The player died mid-ring. A fresh one if Android still lets it play, otherwise every
     * alarm goes over to the system sound, so none is left silent.
     */
    private fun recover(context: Context) {
        stopPlayer(context)
        if (ringing.isEmpty()) return
        val sound = if (startPlayer(context)) SOUND_PLAYER else SOUND_SYSTEM
        if (sound == SOUND_SYSTEM) for ((id, alarm) in ringing) post(context, id, alarm, ownSound = false)
        for (id in ringing.keys) report("recovered", mapOf("id" to id, "sound" to sound))
    }

    /**
     * Stops one alarm; the screen drops it from its list, and closes with the last. [why] goes to
     * the bug-report log: `screen`, `notification`, `timeout` or `expired`.
     */
    fun stop(context: Context, id: Int, why: String) {
        timeouts.remove(id)?.let(main::removeCallbacks)
        ringing.remove(id)?.let {
            report("stopped", mapOf("id" to id, "why" to why, "rang_s" to (now() - it.started) / 1000, "sound" to it.sound))
        }
        NotificationManagerCompat.from(context).cancel(id)
        if (ringing.isEmpty()) stopPlayer(context)
        val shown = screen?.get() ?: return
        if (ringing.isEmpty()) shown.finish() else shown.refresh()
    }

    /**
     * The notification's Stop or its delete intent. Android also fires the delete intent when
     * `setTimeoutAfter` runs out, usually before [ringFor]'s Handler does, so a stop at or past
     * the deadline is the timeout and not the user.
     */
    fun stopFromNotification(context: Context, id: Int) {
        val expired = ringing[id]?.let { it.deadline <= now() } ?: false
        stop(context, id, if (expired) "timeout" else "notification")
    }

    /** Every alarm still ringing: the screen's Stop, which lists them all. */
    fun stopAll(context: Context) {
        for (id in (ringing.keys + timeouts.keys).toList()) stop(context, id, "screen")
        screen?.get()?.finish()
    }

    /**
     * Every alarm past its length. The timeouts' Handler stalls while the CPU sleeps, so the
     * screen calls this when it comes back.
     */
    fun stopExpired(context: Context) {
        val now = now()
        for ((id, alarm) in ringing.entries.toList()) if (alarm.deadline <= now) stop(context, id, "expired")
    }

    private fun now() = SystemClock.elapsedRealtime() + clockOffsetForTest

    /** Moves [now] forward in a device test, as a sleep that outlasted the ring would. */
    @VisibleForTesting
    var clockOffsetForTest = 0L

    private class Ring(
        val title: String,
        val body: String,
        val printer: String,
        val stopLabel: String,
        val started: Long,
        /** [now] at which it stops on its own. */
        val deadline: Long,
    ) {
        /** Set by [post]: the player dying moves it to [SOUND_SYSTEM]. */
        var sound = SOUND_PLAYER
    }
}

/**
 * The notification's Stop button. Also its delete intent, for where the system lets the user
 * swipe an ongoing notification away.
 */
class AlarmStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        PrintAlarm.stopFromNotification(context, intent.getIntExtra(PrintAlarm.EXTRA_ID, 0))
    }
}
