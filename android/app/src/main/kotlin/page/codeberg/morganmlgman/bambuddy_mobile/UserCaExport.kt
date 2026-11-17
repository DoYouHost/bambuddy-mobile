package page.codeberg.morganmlgman.bambuddy_mobile

import android.content.Context
import android.util.Base64
import java.io.File
import java.security.KeyStore

/**
 * Copies the CA certificates the user installed in Settings into a PEM file Dart can read.
 *
 * Dart's TLS stack (BoringSSL inside `dart:io`) trusts only `/system/etc/security/cacerts`
 * and never consults `network_security_config.xml`, so a server behind a home CA failed
 * every handshake even with the CA installed. The user store itself is not readable by an
 * app; the `AndroidCAStore` KeyStore is, and lists those certificates as `user:` aliases.
 * `lib/core/api/user_ca.dart` adds the file to each isolate's `SecurityContext`.
 *
 * A CA removed in Settings is gone from the file on the next process start; with no
 * user CAs left the file is deleted, so nothing stale stays trusted.
 */
object UserCaExport {
    /** Mirrored in `lib/core/api/user_ca.dart`. */
    const val FILE_NAME = "user_ca.pem"

    fun write(context: Context) {
        val target = File(context.filesDir, FILE_NAME)
        try {
            val store = KeyStore.getInstance("AndroidCAStore").apply { load(null) }
            val pem = store.aliases().toList()
                .filter { it.startsWith("user:") }
                .mapNotNull { store.getCertificate(it)?.encoded }
                .joinToString("") {
                    "-----BEGIN CERTIFICATE-----\n" +
                        Base64.encodeToString(it, Base64.DEFAULT) +
                        "-----END CERTIFICATE-----\n"
                }
            if (pem.isEmpty()) {
                target.delete()
                return
            }
            // Through a temp file and a rename, so an isolate reading at the same
            // moment never sees half a certificate.
            val tmp = File(context.filesDir, "$FILE_NAME.tmp")
            tmp.writeText(pem)
            tmp.renameTo(target)
        } catch (e: Exception) {
            // A broken keystore must not stop the app from starting; the
            // previous export, if any, stays.
            android.util.Log.w("UserCaExport", "user CA export failed", e)
        }
    }
}
