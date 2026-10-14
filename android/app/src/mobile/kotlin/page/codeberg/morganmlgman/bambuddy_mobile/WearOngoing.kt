package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine

// No-op twins of the watch's Ongoing Activity: the phone's ongoing notification is the
// foreground service's own, and wear-ongoing is not on its classpath. See the same file in
// `src/wear`.
fun FlutterEngine.serveWearOngoing(activity: Activity) = Unit

fun Activity.wearEngine(): FlutterEngine? = null
