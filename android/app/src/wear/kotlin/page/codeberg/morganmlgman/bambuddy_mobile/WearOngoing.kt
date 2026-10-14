package page.codeberg.morganmlgman.bambuddy_mobile

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Play's WO-V4: a print followed from the watch is an ongoing activity, so while the app is in
 * the background it gets an ongoing notification carrying an [OngoingActivity] — the icon on
 * the watch face and the entry in the launcher's Recents.
 *
 * The service only keeps the process (and with it the Dart isolate, which goes on polling)
 * alive and owns the notification. Dart decides what it says and when it ends.
 */
fun FlutterEngine.serveWearOngoing(activity: Activity) {
    // The application context for the service: the engine outlives this activity
    // ([wearEngine]), so a later call can arrive after it is destroyed.
    val app = activity.applicationContext
    MethodChannel(dartExecutor.binaryMessenger, WEAR_ONGOING_CHANNEL).setMethodCallHandler { call, result ->
        when (call.method) {
            "show" -> result.success(WearOngoingService.show(app, call.arguments as Map<*, *>))
            "stop" -> {
                WearOngoingService.stop(app)
                result.success(null)
            }
            // What the system holds, not what this file believes it asked for: the on-device
            // tests (patrol_test/) read it, since they cannot reach `dumpsys`.
            "status" -> {
                @Suppress("DEPRECATION") // Still answers for the caller's own services.
                val foreground = app.getSystemService(ActivityManager::class.java)
                    .getRunningServices(Int.MAX_VALUE)
                    .any { it.service.className == WearOngoingService::class.java.name && it.foreground }
                result.success(
                    mapOf(
                        "foreground" to foreground,
                        "ongoingActivity" to (OngoingActivity.recoverOngoingActivity(app) != null),
                    )
                )
            }
            "requestPermission" -> {
                // The handler outlives `activity` with the engine; a destroyed one cannot ask.
                if (!activity.isDestroyed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    !notificationsAllowed(activity)
                ) {
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        NOTIFICATION_PERMISSION_REQUEST,
                    )
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}

/**
 * One engine for the whole process, handed to every [MainActivity] instead of one per activity.
 *
 * The swipe off a watch app's root screen is the system's own back-to-home, which finishes the
 * activity without asking Flutter — and an engine owned by the activity dies with it, taking the
 * poll the Ongoing Activity lives on. A provided engine is not destroyed with its host
 * (`FlutterActivity.shouldDestroyEngineWithHost`), and the next activity attaches to it.
 */
fun Activity.wearEngine(): FlutterEngine =
    engine ?: FlutterEngine(applicationContext).also { engine = it }

private var engine: FlutterEngine? = null

private fun notificationsAllowed(context: Context) =
    Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
        PackageManager.PERMISSION_GRANTED

private const val WEAR_ONGOING_CHANNEL = "page.codeberg.morganmlgman.bambuddy/wear_ongoing"
private const val NOTIFICATION_PERMISSION_REQUEST = 7301

class WearOngoingService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val args = latestArgs
        if (args == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Owed after every startForegroundService, a stop that arrived first included: a
        // service that goes away without it takes the process down with
        // ForegroundServiceDidNotStartInTimeException.
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            build(this, args),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )
        if (state == State.STOPPING) {
            state = State.IDLE
            stopSelf()
        } else {
            state = State.FOREGROUND
        }
        return START_NOT_STICKY
    }

    /**
     * Kept here, not in the service: a stop is followed by `onDestroy` only later, and a show
     * in between belongs to the next instance — a flag the old one cleared on its way out
     * would leave the new one unaccounted for. All of it runs on the main thread.
     */
    private enum class State { IDLE, STARTING, STOPPING, FOREGROUND }

    companion object {
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "wear_ongoing"

        private var state = State.IDLE

        /** What `onStartCommand` posts: an update that arrived while the start was pending is
         *  newer than what the start was asked with. */
        private var latestArgs: Bundle? = null

        /** Whether the notification went up. False when the service could not be started. */
        fun show(context: Context, map: Map<*, *>): Boolean {
            val args = Bundle().apply {
                putString("title", map["title"] as? String)
                putString("body", map["body"] as? String)
                putString("chip", map["chip"] as? String)
                putString("channelName", map["channelName"] as? String)
                (map["progress"] as? Number)?.let { putInt("progress", it.toInt()) }
                (map["etaInMs"] as? Number)?.let { putLong("etaInMs", it.toLong()) }
                putBoolean("paused", map["paused"] as? Boolean ?: false)
            }
            latestArgs = args
            ensureChannel(context, args.getString("channelName").orEmpty())
            when (state) {
                State.FOREGROUND -> {
                    // The id the service is in the foreground under: an update never goes
                    // through a second start, which the background may refuse.
                    if (notificationsAllowed(context)) {
                        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, build(context, args))
                    }
                    return true
                }
                State.STARTING -> return true
                State.STOPPING -> {
                    state = State.STARTING
                    return true
                }
                State.IDLE -> return try {
                    state = State.STARTING
                    ContextCompat.startForegroundService(
                        context,
                        Intent(context, WearOngoingService::class.java),
                    )
                    true
                } catch (e: IllegalStateException) {
                    // ForegroundServiceStartNotAllowedException: asked from the background,
                    // past the grace period an activity that just left the screen gets.
                    state = State.IDLE
                    false
                }
            }
        }

        fun stop(context: Context) {
            when (state) {
                State.IDLE, State.STOPPING -> Unit
                State.STARTING -> state = State.STOPPING
                State.FOREGROUND -> {
                    state = State.IDLE
                    context.stopService(Intent(context, WearOngoingService::class.java))
                }
            }
        }
        private fun ensureChannel(context: Context, name: String) {
            NotificationManagerCompat.from(context).createNotificationChannel(
                NotificationChannelCompat.Builder(CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_LOW)
                    .setName(name.ifEmpty { "Bambuddy" })
                    .build()
            )
        }

        private fun build(context: Context, args: Bundle): Notification {
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val progress = if (args.containsKey("progress")) args.getInt("progress") else null
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_notify)
                .setContentTitle(args.getString("title"))
                .setContentText(args.getString("body"))
                .setContentIntent(open)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setOngoing(true)
                // Null is a preparing machine: a bar pinned at zero would say nothing is
                // happening (the phone's notification makes the same call).
                .setProgress(100, progress ?: 0, progress == null)

            OngoingActivity.Builder(context, NOTIFICATION_ID, builder)
                .setStaticIcon(R.drawable.ic_stat_notify)
                .setTouchIntent(open)
                .apply { status(args)?.let(::setStatus) }
                .build()
                .apply(context)
            return builder.build()
        }

        /**
         * "45% · 1:23:05" in the launcher's Recents. The timer counts down on the system's
         * side, so it keeps moving between the polls; a paused print freezes it where it is.
         * Null leaves Recents to the notification's own text.
         */
        private fun status(args: Bundle): Status? {
            val chip = args.getString("chip")?.takeIf { it.isNotEmpty() }
            val eta = if (args.containsKey("etaInMs")) args.getLong("etaInMs") else null
            if (chip == null && eta == null) return null
            val builder = Status.Builder()
            val template = listOfNotNull(chip?.let { "#chip#" }, eta?.let { "#eta#" })
                .joinToString(" · ")
            builder.addTemplate(template)
            chip?.let { builder.addPart("chip", Status.TextPart(it)) }
            eta?.let {
                val now = SystemClock.elapsedRealtime()
                val end = now + it
                builder.addPart(
                    "eta",
                    if (args.getBoolean("paused")) Status.TimerPart(end, now) else Status.TimerPart(end),
                )
            }
            return builder.build()
        }
    }
}
