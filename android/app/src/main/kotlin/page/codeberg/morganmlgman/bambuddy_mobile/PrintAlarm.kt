package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
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
 * The sound is the notification's own (alarm usage, `FLAG_INSISTENT`), so it plays with or
 * without the full-screen permission and stops exactly when the notification goes.
 */
object PrintAlarm {
    const val METHOD_CHANNEL = "page.codeberg.morganmlgman.bambuddy/alarm"
    private const val CHANNEL_ID = "print_alarm"
    private const val ACTION_STOP = "page.codeberg.morganmlgman.bambuddy_mobile.ALARM_STOP"

    const val EXTRA_ID = "id"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_STOP = "stop"

    private val main = Handler(Looper.getMainLooper())

    /** Each alarm's own timeout, so ringing an id again restarts its clock. */
    private val timeouts = mutableMapOf<Int, Runnable>()

    /** The alarm screen on display, so a Stop from the notification can close it too. */
    var screen: WeakReference<Activity>? = null

    /**
     * Serves the alarm channel on [messenger]. [activity] is null on the foreground service's
     * engine, which can ring but has no screen to open the permission page from.
     */
    fun serve(messenger: BinaryMessenger, context: Context, activity: Activity?): MethodChannel =
        MethodChannel(messenger, METHOD_CHANNEL).apply {
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

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // Sound and usage are frozen once the channel exists; changing them means a new id.
        val channel = NotificationChannel(CHANNEL_ID, "Print alarm", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Rings when a print ends or stops, or drying finishes"
            setSound(
                alarmSound(),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            enableVibration(true)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
        }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    /** Posts the alarm. False when notifications are off for the app, so nothing could ring. */
    fun ring(
        context: Context,
        id: Int,
        title: String,
        body: String,
        stopLabel: String,
        minutes: Int,
    ): Boolean {
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return false
        ensureChannel(context)
        val ringFor = minutes.coerceIn(1, 30) * 60_000L

        val screenIntent = Intent(context, AlarmActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION)
            .putExtra(EXTRA_ID, id)
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_BODY, body)
            .putExtra(EXTRA_STOP, stopLabel)
        val screen = PendingIntent.getActivity(
            context, id, screenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getBroadcast(
            context, id,
            Intent(context, AlarmStopReceiver::class.java).setAction(ACTION_STOP).putExtra(EXTRA_ID, id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            // Below API 26 there is no channel to carry the sound.
            .setSound(alarmSound(), AudioManager.STREAM_ALARM)
            .setFullScreenIntent(screen, true)
            .setContentIntent(screen)
            .setDeleteIntent(stop)
            .addAction(0, stopLabel, stop)
            .setTimeoutAfter(ringFor)
            .setOngoing(true)
            .build()
            .apply { flags = flags or android.app.Notification.FLAG_INSISTENT }
        try {
            manager.notify(id, notification)
        } catch (_: SecurityException) {
            return false
        }
        // setTimeoutAfter is a no-op below API 26, and the screen has to close with the sound.
        val timeout = Runnable { stop(context, id) }
        timeouts.put(id, timeout)?.let(main::removeCallbacks)
        main.postDelayed(timeout, ringFor)
        return true
    }

    fun stop(context: Context, id: Int) {
        timeouts.remove(id)?.let(main::removeCallbacks)
        NotificationManagerCompat.from(context).cancel(id)
        val shown = screen?.get()
        if (shown != null && shown.intent.getIntExtra(EXTRA_ID, -1) == id) shown.finish()
    }
}

/** The notification's Stop button, and its dismissal: both end the alarm. */
class AlarmStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        PrintAlarm.stop(context, intent.getIntExtra(PrintAlarm.EXTRA_ID, 0))
    }
}
