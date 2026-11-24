package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

private const val NFC_CHANNEL = "page.codeberg.morganmlgman.bambuddy/nfc"
private const val NFC_TAGS_CHANNEL = "page.codeberg.morganmlgman.bambuddy/nfc_tags"

/**
 * Reads the UID of an NFC tag held to the phone, for the inventory to find the spool it was
 * linked to (#71). Only the UID: the tags a spool carries are linked to it by that number
 * (`tag_uid` on the spool), so nothing on the tag is read or written.
 *
 * Reader mode rather than foreground dispatch: it needs no intent filter, so the app is
 * never offered for a tag the user did not hold to it on purpose, and it works only while
 * a Dart listener is subscribed and the activity is resumed.
 *
 * `nfc` answers [Reader.status] ("ready", "disabled" in the system settings, or
 * "unsupported") and opens the system's NFC settings; `nfc_tags` streams one upper-case hex
 * UID per tag, and an error `nfc_unavailable` each time NFC is, or goes, off while somebody
 * is listening.
 *
 * One [Reader] per engine and activity: a second activity may be served before the first is
 * released, and what one of them subscribes, cancels or tears down must not reach the
 * other's reader.
 */
object NfcReader {
    private val readers = mutableMapOf<FlutterEngine, Reader>()

    fun serve(engine: FlutterEngine, host: Activity) {
        readers.remove(engine)?.close()
        readers[engine] = Reader(engine, host)
    }

    fun release(engine: FlutterEngine) {
        readers.remove(engine)?.close()
    }

    fun pause(host: Activity) = readers.values.firstOrNull { it.host === host }?.pause()

    fun resume(host: Activity) = readers.values.firstOrNull { it.host === host }?.resume()

    private class Reader(private val engine: FlutterEngine, val host: Activity) :
        EventChannel.StreamHandler {
        private val main = Handler(Looper.getMainLooper())
        private var sink: EventChannel.EventSink? = null
        private var resumed = false

        /** Counts subscriptions, so a tag read for one is never handed to the next. */
        private var generation = 0
        private var receiver: BroadcastReceiver? = null

        init {
            val messenger = engine.dartExecutor.binaryMessenger
            MethodChannel(messenger, NFC_CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(status())
                    "openSettings" -> {
                        try {
                            host.startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
                        } catch (_: Exception) {
                            // No settings screen for it on this device: nothing more to do.
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
            EventChannel(messenger, NFC_TAGS_CHANNEL).setStreamHandler(this)
        }

        fun close() {
            val messenger = engine.dartExecutor.binaryMessenger
            MethodChannel(messenger, NFC_CHANNEL).setMethodCallHandler(null)
            EventChannel(messenger, NFC_TAGS_CHANNEL).setStreamHandler(null)
            generation++
            stop()
            sink = null
        }

        private fun status(): String {
            val adapter = NfcAdapter.getDefaultAdapter(host)
            return when {
                adapter == null -> "unsupported"
                !adapter.isEnabled -> "disabled"
                else -> "ready"
            }
        }

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            generation++
            sink = events
            if (resumed) start()
        }

        override fun onCancel(arguments: Any?) {
            generation++
            stop()
            sink = null
        }

        /** The activity left the foreground: reader mode must not outlive it. */
        fun pause() {
            resumed = false
            stop()
        }

        /** The activity came to the foreground; a listener already waiting starts reading. */
        fun resume() {
            resumed = true
            if (sink != null) start()
        }

        private fun start() {
            val adapter = NfcAdapter.getDefaultAdapter(host)
            if (adapter == null) {
                sink?.error("nfc_unavailable", "This phone has no NFC", null)
                return
            }
            // Watched before the enabled check: switching NFC on later is what starts it.
            watchAdapter()
            if (!adapter.isEnabled) {
                sink?.error("nfc_unavailable", "NFC is off", null)
                return
            }
            enableReader(adapter)
        }

        private fun enableReader(adapter: NfcAdapter) {
            val mine = generation
            try {
                adapter.enableReaderMode(
                    host,
                    { tag -> emit(tag, mine) },
                    // Every technology that has a UID. NDEF is not read, so its check is
                    // skipped: it would only delay the callback.
                    NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or
                        NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_NFC_V or
                        NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK,
                    null,
                )
            } catch (e: Exception) {
                sink?.error("nfc_failed", e.message, null)
            }
        }

        private fun stop() {
            try {
                NfcAdapter.getDefaultAdapter(host)?.disableReaderMode(host)
            } catch (_: Exception) {
                // Already off, or the activity is going away.
            }
            unwatchAdapter()
        }

        /**
         * The quick-settings tile switches NFC without pausing the activity, so the state is
         * watched while somebody listens: off becomes the error, on starts the reader that
         * the listener has been waiting for.
         */
        private fun watchAdapter() {
            if (receiver != null) return
            val watcher = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    if (sink == null || !resumed) return
                    when (intent.getIntExtra(NfcAdapter.EXTRA_ADAPTER_STATE, NfcAdapter.STATE_OFF)) {
                        NfcAdapter.STATE_OFF -> sink?.error("nfc_unavailable", "NFC is off", null)
                        NfcAdapter.STATE_ON ->
                            NfcAdapter.getDefaultAdapter(host)?.let { enableReader(it) }
                    }
                }
            }
            ContextCompat.registerReceiver(
                host,
                watcher,
                IntentFilter(NfcAdapter.ACTION_ADAPTER_STATE_CHANGED),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            receiver = watcher
        }

        private fun unwatchAdapter() {
            val watcher = receiver ?: return
            receiver = null
            try {
                host.unregisterReceiver(watcher)
            } catch (_: Exception) {
                // Never registered, or already gone with the activity.
            }
        }

        private fun emit(tag: Tag, subscription: Int) {
            val uid = tag.id.joinToString("") { "%02X".format(it) }
            // The callback runs on a binder thread; a channel is answered on the main one.
            main.post { if (subscription == generation) sink?.success(uid) }
        }
    }
}

fun FlutterEngine.serveNfc(activity: Activity) = NfcReader.serve(this, activity)

fun FlutterEngine.releaseNfc() = NfcReader.release(this)

fun nfcPause(activity: Activity) = NfcReader.pause(activity)

fun nfcResume(activity: Activity) = NfcReader.resume(activity)
