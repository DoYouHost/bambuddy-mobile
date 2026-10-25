package page.codeberg.morganmlgman.bambuddy_mobile

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine

// No-op twin: only the watch has a face to take colours from. See the same file in `src/wear`.
fun FlutterEngine.serveWatchFaceColours(context: Context) = Unit
