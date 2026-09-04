package page.codeberg.morganmlgman.bambuddy_mobile.wear

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The Flutter engine that answers the watch when the app's own engines are
 * gone, and the only thing that drives it.
 *
 * Google Play services starts our process to deliver the watch's message
 * ([WearRelayListenerService]); this puts Dart back on top of it long enough to
 * run the request against the phone's authenticated session.
 *
 * The engine **never listens** on the Data Layer itself, even though the plugin
 * inside it could: every message also reaches the service, and the service only
 * forwards what no live responder claimed. That is what keeps a woken engine
 * from executing a command that the app's own engine is executing at the same
 * moment — one answer per request, or a `startNext` prints the next plate
 * twice.
 */
internal object WearRelayEngineHost {
    /** Mirror of `wearRelayChannel` in `lib/core/watch/wear_relay_engine.dart`. */
    private const val CHANNEL = "page.codeberg.morganmlgman.bambuddy/wear_relay"

    /**
     * Looked up in the app's own entry library (`lib/main.dart`), which is
     * where `wearRelayMain` has to be declared: a library the Dart program
     * does not import is not in the release snapshot at all, pragma or no
     * pragma. The comment on the function has the measurement.
     */
    private const val ENTRYPOINT_FUNCTION = "wearRelayMain"

    /**
     * How long the caller waits for Dart. Covers the cold path end to end —
     * engine boot, keystore, an authenticated request — and stays under the
     * watch's own post-ack deadline (`wearRpcWakeTimeout`), so the watch is
     * never the first to give up on a phone that is still working.
     */
    private const val ANSWER_TIMEOUT_MS = 12_000L

    /** Idle engine kept warm for a follow-up: the watch usually sends one. */
    private const val IDLE_SHUTDOWN_MS = 60_000L

    private val main = Handler(Looper.getMainLooper())

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null

    /** Requests in flight, read and written on the main thread only. */
    private var busy = 0

    private val idleShutdown = Runnable {
        if (busy > 0) {
            scheduleIdleShutdown()
        } else {
            channel = null
            engine?.destroy()
            engine = null
        }
    }

    /**
     * Runs [request] in Dart and returns whether Dart answered the watch.
     *
     * **Blocks the calling thread** on purpose: it is one of the listener
     * service's background threads, and Play services keeps the service — and
     * with it this process — bound while the callback is inside. Returning
     * early would let Android reclaim the process with the reply half written.
     */
    fun handle(context: Context, request: HashMap<String, Any?>): Boolean {
        val answered = AtomicBoolean(false)
        val done = CountDownLatch(1)
        val application = context.applicationContext
        // Engine creation and channel calls belong to the main thread; this
        // hops there and waits below.
        main.post {
            busy++
            main.removeCallbacks(idleShutdown)
            val result = object : MethodChannel.Result {
                override fun success(result: Any?) {
                    answered.set(result == true)
                    finish()
                }

                override fun error(code: String, message: String?, details: Any?) =
                    finish()

                override fun notImplemented() = finish()

                private fun finish() {
                    busy--
                    scheduleIdleShutdown()
                    done.countDown()
                }
            }
            try {
                ensureEngine(application).invokeMethod("handle", request, result)
            } catch (_: Exception) {
                // An engine that cannot start (a broken Flutter loader) must
                // release the waiting thread and the idle timer with it —
                // otherwise the caller sits out the full timeout and this host
                // keeps a half-built engine forever.
                result.error("engine", null, null)
            }
        }
        val inTime = done.await(ANSWER_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        return inTime && answered.get()
    }

    /**
     * The engine's channel, starting the engine on first use.
     *
     * `invokeMethod` right after the entry point is launched is deliberate: the
     * message waits in Dart's channel buffer until `wearRelayMain` installs its
     * handler, which is milliseconds of Dart but the whole engine boot in wall
     * clock. The buffer holds one message per channel, and one is all the cold
     * path ever sends — every later request finds the engine already up.
     */
    private fun ensureEngine(context: Context): MethodChannel {
        channel?.let { return it }
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) loader.startInitialization(context)
        loader.ensureInitializationComplete(context, null)
        // FlutterEngine(Context) registers every plugin of the app by itself
        // (reflection on GeneratedPluginRegistrant) — which is what gives the
        // relay `watch_connectivity`, secure storage and prefs in here, the
        // same way the foreground service's engine gets them.
        val created = FlutterEngine(context)
        created.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRYPOINT_FUNCTION)
        )
        engine = created
        return MethodChannel(created.dartExecutor.binaryMessenger, CHANNEL)
            .also { channel = it }
    }

    private fun scheduleIdleShutdown() {
        main.removeCallbacks(idleShutdown)
        main.postDelayed(idleShutdown, IDLE_SHUTDOWN_MS)
    }
}
