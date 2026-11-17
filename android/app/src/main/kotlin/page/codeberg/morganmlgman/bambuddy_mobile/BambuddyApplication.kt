package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.Application
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin

/**
 * Exists to run two things before anything else: registering [OngoingNotificationHost], and
 * [UserCaExport].
 *
 * It has to be here rather than in [MainActivity]. The foreground service is `START_STICKY`,
 * so Android restarts it on its own without ever starting an activity — and after such a
 * restart the service's Dart isolate would be calling a method channel nobody serves.
 * `Application.onCreate` is the only callback that runs in both cases.
 *
 * Extends `android.app.Application`, which is also what the `${applicationName}` placeholder
 * this replaces expands to. Not `io.flutter.app.FlutterApplication`: that class is deprecated
 * and its body is empty, kept only so projects on the v1 embedding still build.
 *
 * The watch flavor puts `${applicationName}` back (see its manifest) — it strips the
 * foreground service, so there is no task lifecycle to listen to.
 */
class BambuddyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Before any engine starts, for the same reason as the listener below:
        // every isolate reads the export when it opens its first connection.
        UserCaExport.write(this)
        FlutterForegroundTaskPlugin.addTaskLifecycleListener(OngoingNotificationHost(this))
    }
}
