package page.codeberg.morganmlgman.bambuddy_mobile.wear

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InvalidClassException
import java.io.ObjectInputStream
import java.io.ObjectOutputStream
import java.io.ObjectStreamClass

/**
 * The watch↔phone RPC as it travels over the Data Layer, for the one side that
 * has no Dart to do it: the listener service.
 *
 * `watch_connectivity` puts a Java-serialized map on the wire and hardcodes a
 * single message path for every message, so the contract here is the plugin's
 * encoding plus the field names from `lib/core/watch/wear_rpc.dart`. Both
 * halves are mirrors — change one and change the other.
 */
internal object WearRpcCodec {
    /**
     * The plugin's one path for everything (`WatchConnectivityPlugin.sendMessage`).
     * It has no leading slash, which is why the manifest's intent filter cannot
     * match on `pathPrefix` and matches every wear message instead.
     */
    const val PATH = "watch_connectivity"

    /** Mirror of `wearRpcVersion`. */
    private const val VERSION = 2

    private const val KEY_VERSION = "v"
    private const val KEY_KIND = "kind"
    private const val KEY_ID = "id"
    private const val KEY_STATE = "state"

    private const val KIND_REQUEST = "req"
    private const val KIND_ACK = "ack"
    private const val ACK_WAKING = "waking"

    /**
     * The request in [data], or null when it is not one — a response echo, a
     * malformed map, or anything else that came down the shared path.
     */
    fun requestOrNull(data: ByteArray): HashMap<String, Any?>? {
        val decoded = try {
            SafeObjectInputStream(ByteArrayInputStream(data)).use { it.readObject() }
        } catch (_: Exception) {
            // Includes the whitelist's own refusal. Nothing on this path is
            // worth a crash in a service the system started on our behalf.
            return null
        }
        if (decoded !is Map<*, *> || decoded[KEY_KIND] != KIND_REQUEST) return null
        if (decoded[KEY_ID] !is String) return null
        val request = HashMap<String, Any?>(decoded.size)
        for ((key, value) in decoded) {
            if (key is String) request[key] = value
        }
        return request
    }

    fun idOf(request: Map<String, Any?>): String? =
        (request[KEY_ID] as? String)?.takeIf { it.isNotEmpty() }

    /**
     * "Hold on, waking up" for [id] — the phone had no relay listening and the
     * answer will be later than the watch's normal deadline. A watch built
     * before this kind existed drops it and keeps that deadline.
     */
    fun ack(id: String): ByteArray {
        val ack = HashMap<String, Any?>(4)
        ack[KEY_VERSION] = VERSION
        ack[KEY_KIND] = KIND_ACK
        ack[KEY_ID] = id
        ack[KEY_STATE] = ACK_WAKING
        val bytes = ByteArrayOutputStream()
        ObjectOutputStream(bytes).use { it.writeObject(ack) }
        return bytes.toByteArray()
    }

    /**
     * Java deserialization of bytes that crossed a process boundary, so the
     * class graph is fixed to what the protocol can contain. The Data Layer
     * only carries messages between installs of the *same* app (package name
     * and signing key), and the service is nonetheless the app's one exported
     * surface that runs before any of our Dart does.
     */
    private class SafeObjectInputStream(input: ByteArrayInputStream) :
        ObjectInputStream(input) {
        override fun resolveClass(desc: ObjectStreamClass): Class<*> {
            if (desc.name !in ALLOWED) {
                throw InvalidClassException(desc.name, "not part of the wear RPC")
            }
            return super.resolveClass(desc)
        }

        private companion object {
            /** What the Flutter standard codec can hand the plugin to serialize. */
            val ALLOWED = setOf(
                "java.util.HashMap",
                "java.util.LinkedHashMap",
                "java.util.ArrayList",
                "java.lang.Integer",
                "java.lang.Long",
                "java.lang.Double",
                "java.lang.Boolean",
                "java.lang.Number",
            )
        }
    }
}
