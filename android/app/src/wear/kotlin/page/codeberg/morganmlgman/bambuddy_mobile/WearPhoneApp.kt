package page.codeberg.morganmlgman.bambuddy_mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.ContextCompat
import androidx.wear.remote.interactions.RemoteActivityHelper
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val WEAR_PHONE_APP_CHANNEL = "page.codeberg.morganmlgman.bambuddy/wear_phone_app"

// Advertised by the phone flavor in res/values/wear.xml.
private const val PHONE_APP_CAPABILITY = "bambuddy_phone_app"

/**
 * Whether the paired phone has the app, and a way to install it from the watch: the watch
 * app takes its server from the phone (`standalone=false`), and this is Google's pattern for
 * a watch app that needs its phone app. Only the application context is held, so nothing
 * here outlives an activity.
 */
fun FlutterEngine.serveWearPhoneApp(context: Context) {
    val app = context.applicationContext
    MethodChannel(dartExecutor.binaryMessenger, WEAR_PHONE_APP_CHANNEL).setMethodCallHandler { call, result ->
        when (call.method) {
            // Null rather than false without a connected phone: there is nothing to install
            // on, and an install button that can only fail is worse than none.
            "installed" -> Wearable.getNodeClient(app).connectedNodes
                .addOnSuccessListener { nodes ->
                    if (nodes.isEmpty()) {
                        result.success(null)
                        return@addOnSuccessListener
                    }
                    Wearable.getCapabilityClient(app)
                        .getCapability(PHONE_APP_CAPABILITY, CapabilityClient.FILTER_ALL)
                        .addOnSuccessListener { result.success(it.nodes.isNotEmpty()) }
                        .addOnFailureListener { result.success(null) }
                }
                .addOnFailureListener { result.success(null) }
            // The web address rather than market://: RemoteActivityHelper insists on
            // CATEGORY_BROWSABLE, and the store opens the listing from it anyway.
            "openStore" -> {
                val intent = Intent(Intent.ACTION_VIEW)
                    .addCategory(Intent.CATEGORY_BROWSABLE)
                    .setData(Uri.parse("https://play.google.com/store/apps/details?id=${app.packageName}"))
                val started = RemoteActivityHelper(app).startRemoteActivity(intent)
                started.addListener(
                    { result.success(runCatching { started.get() }.isSuccess) },
                    ContextCompat.getMainExecutor(app),
                )
            }
            else -> result.notImplemented()
        }
    }
}
