package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine

// No-op twin: a watch holds no spool to a tag. The channels stay unregistered, which the
// Dart side reads as "unsupported". See the same file in `src/mobile`.
fun FlutterEngine.serveNfc(activity: Activity) = Unit

fun FlutterEngine.releaseNfc() = Unit

fun nfcPause(activity: Activity) = Unit

fun nfcResume(activity: Activity) = Unit
