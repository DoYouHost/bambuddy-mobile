package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Puts a progress bar on the foreground service's notification, and on Android 16 asks the
 * system to promote it to a Live Update (status-bar chip, lock-screen card).
 *
 * `flutter_foreground_task` owns that notification and offers only a title and a text, so the
 * `progress` the monitor computes has never had anywhere to go. Rather than rebuild the
 * notification here — which would mean copying the plugin's content and delete intents, and
 * re-copying them after every upgrade — this recovers the one the plugin already posted and
 * changes what it has to. Re-posting under the service's own id is the same call the plugin
 * makes to update itself (`ForegroundService.updateNotification`).
 */
class OngoingNotificationHost(private val context: Context) :
    FlutterForegroundTaskLifecycleListener {

    private var channel: MethodChannel? = null

    /**
     * The last notification we posted.
     *
     * Android 14+ lets the user swipe a foreground-service notification away without stopping
     * the service. The plugin forwards that to Dart and re-posts nothing itself, so by the time
     * the isolate asks us to put it back there is nothing in `activeNotifications` to recover
     * from — this is the copy that makes that path keep its bar.
     */
    private var lastPosted: Notification? = null

    override fun onEngineCreate(flutterEngine: FlutterEngine?) {
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger ?: return
        channel = MethodChannel(messenger, ONGOING_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method != "show") {
                    result.notImplemented()
                } else {
                    result.success(
                        show(
                            title = call.argument<String>("title").orEmpty(),
                            body = call.argument<String>("body").orEmpty(),
                            progress = call.argument<Int>("progress"),
                            printing = call.argument<Boolean>("printing") ?: false,
                        )
                    )
                }
            }
        }
    }

    override fun onEngineWillDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        // This listener is registered once per process and outlives any single service, so a
        // notification cached during one monitoring session must not become the recovery
        // source for the next one.
        lastPosted = null
    }

    override fun onTaskStart(starter: FlutterForegroundTaskStarter) = Unit

    override fun onTaskRepeatEvent() = Unit

    override fun onTaskDestroy() = Unit

    /**
     * Whether the notification was posted; `false` sends the Dart side to the plugin instead.
     *
     * [printing] and [progress] are three states, not two: no print, a print whose position is
     * known, and a print running before the first percent arrives — heating or levelling, where
     * a bar pinned at zero says "nothing is happening" about a machine that is busy.
     */
    private fun show(
        title: String,
        body: String,
        progress: Int?,
        printing: Boolean,
    ): Boolean = try {
        // Early return rather than `nm?.` throughout: `getSystemService(Class)` is a platform
        // type (the SDK annotates its parameter, not its return), so Kotlin would accept
        // either, and one non-null receiver reads better than four safe calls.
        val nm = context.getSystemService(NotificationManager::class.java)
        val source = nm?.activeNotifications
            ?.firstOrNull { it.id == SERVICE_NOTIFICATION_ID }
            ?.notification
            ?: lastPosted

        if (nm == null || source == null) {
            false
        } else {
            val builder = Notification.Builder.recoverBuilder(context, source)
            builder.setContentTitle(title)
            builder.setContentText(body)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Set rather than trusted to survive the recovery: it is one line, and losing
                // it means the notification takes ten seconds to appear on a cold start.
                builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }

            // Every branch sets every field any of them touches. `recoverBuilder` carries
            // the previous notification's style and extras forward, and once `lastPosted` is
            // the recovery source those are our own — so leaving them alone would strand a
            // finished print's bar, chip and promotion on the idle "monitoring" notification,
            // which Android 16 would go on promoting.
            when {
                !printing -> {
                    builder.setProgress(0, 0, false)
                    if (Build.VERSION.SDK_INT >= ANDROID_16) {
                        builder.setStyle(Notification.BigTextStyle()) // what the plugin sets
                        builder.setShortCriticalText(null)
                        builder.addExtras(promotionRequest(false))
                    }
                }

                progress == null -> {
                    builder.setProgress(0, 0, true)
                    if (Build.VERSION.SDK_INT >= ANDROID_16) {
                        builder.setStyle(
                            Notification.ProgressStyle().setProgressIndeterminate(true)
                        )
                        // No percent to put on the chip, and a stale one would be a lie.
                        builder.setShortCriticalText(null)
                        builder.addExtras(promotionRequest(true))
                    }
                }

                else -> {
                    builder.setProgress(100, progress, false)
                    if (Build.VERSION.SDK_INT >= ANDROID_16) {
                        builder.setStyle(Notification.ProgressStyle().setProgress(progress))
                        // The percent rather than the ETA: the ETA is a clock time whose
                        // 12/24-hour format the isolate resolves, and re-deriving it here
                        // would get it wrong.
                        builder.setShortCriticalText("$progress%")
                        builder.addExtras(promotionRequest(true))
                    }
                }
            }

            val built = builder.build()
            nm.notify(SERVICE_NOTIFICATION_ID, built)
            lastPosted = built
            true
        }
    } catch (e: Exception) {
        // Anything at all — a manufacturer's ROM refusing the recovery included. The Dart side
        // then posts through the plugin, which is the path that ships today: a notification
        // without a bar beats a foreground service with no notification.
        false
    }

    private fun promotionRequest(requested: Boolean) =
        Bundle().apply { putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, requested) }

    private companion object {
        const val ONGOING_CHANNEL = "page.codeberg.morganmlgman.bambuddy/ongoing"

        /** Must equal `foregroundServiceNotificationId` in `background_monitor.dart`. */
        const val SERVICE_NOTIFICATION_ID = 1

        /**
         * `Build.VERSION_CODES.BAKLAVA` by another name. `compileSdk` is 36, where the constant
         * exists but the typed promotion API below does not.
         */
        const val ANDROID_16 = 36

        /**
         * The literal value of `Notification.EXTRA_REQUEST_PROMOTED_ONGOING`, which is public
         * API but only from 36.1 — `compileSdk` is 36, so the typed
         * `Builder.setRequestPromotedOngoing` does not compile here. Writing the extra is not a
         * workaround: `NotificationCompat.Builder.setRequestPromotedOngoing` in androidx.core
         * 1.17.0 is exactly this `putBoolean` and nothing else. Becomes the typed call on the
         * day `compileSdk` reaches 36.1.
         */
        const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"
    }
}
