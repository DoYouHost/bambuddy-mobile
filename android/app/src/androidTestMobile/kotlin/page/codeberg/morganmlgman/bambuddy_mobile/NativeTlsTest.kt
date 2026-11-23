package page.codeberg.morganmlgman.bambuddy_mobile

import android.net.http.SslError
import android.webkit.SslErrorHandler
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.platform.app.InstrumentationRegistry
import java.net.ServerSocket
import java.net.URL
import java.security.KeyStore
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLHandshakeException
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/**
 * Why the timelapse player and the G-code viewer cannot reach a server behind a private CA
 * (#62) or mutual TLS (#65) by themselves: both run on Android's own network stack, which
 * knows nothing of the CA the app imported (`useTls` only sets `HttpOverrides`, which is
 * `dart:io`). A server whose certificate no system root vouches for stands in for it.
 *
 * ExoPlayer, which `video_player` uses, opens `HttpURLConnection`s; the viewer is a WebView.
 * Both are asked here, and both refuse. The app's answer is the loopback bridge
 * (`lib/core/api/loopback_proxy.dart`), which fetches through `dart:io`.
 *
 * And the way back: both reach a plain-http server on the loopback, which is what the bridge
 * is, and a page whose base URL is that loopback fetches from it same-origin.
 *
 * Run on the phone AVD, after `flutter build apk --debug --flavor mobile`:
 *
 *     cd android && ./gradlew :app:connectedMobileDebugAndroidTest \
 *       -Pandroid.testInstrumentationRunnerArguments.class=page.codeberg.morganmlgman.bambuddy_mobile.NativeTlsTest
 */
class NativeTlsTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val server = run {
        val keys = KeyStore.getInstance("PKCS12")
        instrumentation.context.assets.open("native_tls_server.p12").use {
            keys.load(it, "changeit".toCharArray())
        }
        val factory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
        factory.init(keys, "changeit".toCharArray())
        val context = SSLContext.getInstance("TLS")
        context.init(factory.keyManagers, null, null)
        context.serverSocketFactory.createServerSocket(0)
    }
    private val url = "https://127.0.0.1:${server.localPort}/"
    private var webView: WebView? = null

    @Before
    fun setUp() {
        Thread {
            while (!server.isClosed) {
                val socket = try { server.accept() } catch (_: Exception) { break }
                Thread {
                    try {
                        socket.use {
                            val input = it.getInputStream().bufferedReader()
                            while (input.readLine().let { line -> line != null && line.isNotEmpty() }) { }
                            it.getOutputStream().write(
                                ("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok").toByteArray()
                            )
                        }
                    } catch (_: Exception) {
                        // A client that refused the certificate hangs up mid-handshake.
                    }
                }.start()
            }
        }.apply { isDaemon = true }.start()
    }

    @After
    fun tearDown() {
        server.close()
        instrumentation.runOnMainSync { webView?.destroy() }
    }

    @Test
    fun theStackExoPlayerUsesDoesNotTrustAnImportedCa() {
        try {
            (URL(url).openConnection() as HttpsURLConnection).apply {
                connectTimeout = 10_000
                readTimeout = 10_000
            }.inputStream.close()
            fail("the certificate was accepted")
        } catch (_: SSLHandshakeException) {
            // As it must: no system root vouches for it.
        }
    }

    @Test
    fun aWebViewRefusesItToo() {
        val refused = CountDownLatch(1)
        var primary = -1
        instrumentation.runOnMainSync {
            val view = WebView(instrumentation.targetContext)
            view.webViewClient = object : WebViewClient() {
                override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                    primary = error.primaryError
                    handler.cancel()
                    refused.countDown()
                }
            }
            webView = view
            view.loadUrl(url)
        }
        assertTrue("the WebView never objected", refused.await(30, TimeUnit.SECONDS))
        assertEquals(SslError.SSL_UNTRUSTED, primary)
    }

    /** A plain-http server on the loopback, standing in for the bridge. */
    private fun loopback(): ServerSocket {
        val plain = ServerSocket(0, 50, java.net.InetAddress.getByName("127.0.0.1"))
        Thread {
            while (!plain.isClosed) {
                val socket = try { plain.accept() } catch (_: Exception) { break }
                Thread {
                    try {
                        socket.use {
                            val input = it.getInputStream().bufferedReader()
                            while (input.readLine().let { line -> line != null && line.isNotEmpty() }) { }
                            it.getOutputStream().write(
                                ("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok").toByteArray()
                            )
                        }
                    } catch (_: Exception) {
                    }
                }.start()
            }
        }.apply { isDaemon = true }.start()
        return plain
    }

    @Test
    fun theStackExoPlayerUsesReachesTheLoopbackOverCleartext() {
        val plain = loopback()
        try {
            val body = (URL("http://127.0.0.1:${plain.localPort}/").openConnection() as java.net.HttpURLConnection)
                .inputStream.bufferedReader().readText()
            assertEquals("ok", body)
        } finally {
            plain.close()
        }
    }

    @Test
    fun aPageBasedOnTheLoopbackFetchesFromItSameOrigin() {
        val plain = loopback()
        val answered = CountDownLatch(1)
        var seen = ""
        try {
            instrumentation.runOnMainSync {
                val view = WebView(instrumentation.targetContext)
                view.settings.javaScriptEnabled = true
                view.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView, url: String) {
                        view.evaluateJavascript("fetch('/gcode').then(r => r.text()).then(t => { document.title = t; })", null)
                    }
                }
                view.webChromeClient = object : android.webkit.WebChromeClient() {
                    override fun onReceivedTitle(view: WebView, title: String) {
                        if (title == "ok") {
                            seen = title
                            answered.countDown()
                        }
                    }
                }
                webView = view
                val base = "http://127.0.0.1:${plain.localPort}"
                view.loadDataWithBaseURL(base, "<html><title>page</title><body>x</body></html>", "text/html", "utf-8", null)
            }
            assertTrue("the page never got its answer", answered.await(30, TimeUnit.SECONDS))
            assertEquals("ok", seen)
        } finally {
            plain.close()
        }
    }
}
