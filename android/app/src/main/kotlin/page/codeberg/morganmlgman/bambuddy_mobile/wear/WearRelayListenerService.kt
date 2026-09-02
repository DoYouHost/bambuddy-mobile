package page.codeberg.morganmlgman.bambuddy_mobile.wear

import android.content.Context
import android.os.Process
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import java.util.concurrent.TimeUnit

/**
 * Answers the watch on a phone whose app is not running.
 *
 * Declared in the manifest, which is the whole point: Play services binds a
 * declared listener service and **starts the process for it**. Before this, a
 * command from the watch reached a live plugin listener or nobody at all, and
 * nobody was what the user saw as "the phone did not respond".
 *
 * It executes nothing itself — the request needs the phone's authenticated
 * session, which lives in Dart ([WearRelayEngineHost]) — and it answers
 * nothing that a live responder in this process is already answering
 * ([relayClaimedInThisProcess]).
 */
class WearRelayListenerService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        // Every message of ours shares one path (the plugin's design), so this
        // only filters out other traffic on the node.
        if (event.path != WearRpcCodec.PATH) return
        if (relayClaimedInThisProcess()) return
        val request = WearRpcCodec.requestOrNull(event.data) ?: return
        val id = WearRpcCodec.idOf(request) ?: return
        // The service is exported (Play services binds it from its own
        // process), so the sender is checked rather than assumed: a real
        // request comes from a node that is connected to this phone right now,
        // and a node id is not something another app on the phone can produce.
        if (!isConnectedNode(event.sourceNodeId)) return
        // Before the wake, not after: the extra time the watch grants has to
        // cover the engine boot it is waiting through.
        sendAck(event.sourceNodeId, id)
        WearRelayEngineHost.handle(this, request)
    }

    /**
     * Whether a Dart responder in *this* process is listening.
     *
     * The mark is a process id and not a flag on purpose (`WearRelayClaim` in
     * Dart has the reasoning): a process that was killed cannot leave a claim
     * that silences this service for good, because the pid it wrote can never
     * equal ours again.
     */
    private fun relayClaimedInThisProcess(): Boolean {
        val prefs = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val claimed = try {
            prefs.getLong(CLAIM_KEY, NO_CLAIM)
        } catch (_: ClassCastException) {
            NO_CLAIM
        }
        return claimed == Process.myPid().toLong()
    }

    private fun isConnectedNode(nodeId: String): Boolean = try {
        // The callback runs on a background thread, which is what makes this
        // wait legal here.
        Tasks.await(Wearable.getNodeClient(this).connectedNodes, 3, TimeUnit.SECONDS)
            .any { it.id == nodeId }
    } catch (e: Exception) {
        // Fails closed: a watch that really sent this is a connected node by
        // definition. Logged because a dropped request is indistinguishable
        // from the bug this whole service fixes — silence.
        Log.w(TAG, "wear relay: cannot verify the sending node", e)
        false
    }

    private fun sendAck(nodeId: String, id: String) {
        try {
            Wearable.getMessageClient(this)
                .sendMessage(nodeId, WearRpcCodec.PATH, WearRpcCodec.ack(id))
        } catch (_: Exception) {
            // The ack is an optimisation; without it the watch simply keeps the
            // deadline it had before this service existed.
        }
    }

    private companion object {
        const val TAG = "BambuddyWearRelay"

        /** `shared_preferences`' own file and the `flutter.` prefix it adds. */
        const val FLUTTER_PREFS = "FlutterSharedPreferences"
        const val CLAIM_KEY = "flutter.wear_relay_pid"
        const val NO_CLAIM = -1L
    }
}
