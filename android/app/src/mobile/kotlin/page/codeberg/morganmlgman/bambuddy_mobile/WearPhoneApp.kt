package page.codeberg.morganmlgman.bambuddy_mobile

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine

// No-op twin: only the watch asks about the phone app. See the same file in `src/wear`.
fun FlutterEngine.serveWearPhoneApp(context: Context) = Unit
