package page.codeberg.morganmlgman.bambuddy_mobile

import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.platform.app.InstrumentationRegistry
import java.net.ServerSocket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The `edge_cookie` channel's native half (#72, EdgeCookies.kt) against a real WebView: that
 * Cloudflare Access's HttpOnly `CF_Authorization` is out of the page's reach and still readable
 * here, and that `clear` really empties the store. No host test can see either.
 *
 * Run on the phone AVD (`just emu-boot pixel35`), after `flutter build apk --debug --flavor mobile`:
 *
 *     cd android && ./gradlew :app:connectedMobileDebugAndroidTest \
 *       -Pandroid.testInstrumentationRunnerArguments.class=page.codeberg.morganmlgman.bambuddy_mobile.EdgeCookiesTest
 *
 * The server is a loopback socket in the test process; the app's manifest allows cleartext, so
 * the WebView loads it as it would a LAN bambuddy.
 */
class EdgeCookiesTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val server = ServerSocket(0)
    private val origin = "http://127.0.0.1:${server.localPort}"
    private var webView: WebView? = null

    @Before
    fun setUp() {
        Thread {
            while (!server.isClosed) {
                val socket = try { server.accept() } catch (_: Exception) { break }
                socket.use {
                    // The request is read to its blank line so the close is not a reset.
                    val input = it.getInputStream().bufferedReader()
                    val requestLine = input.readLine() ?: ""
                    while (input.readLine().let { line -> line != null && line.isNotEmpty() }) { }
                    // Persistent like Access's own (a session cookie would survive a clear that only
                    // drops those). Only the page sets cookies: the favicon the WebView asks for after it
                    // would otherwise put them back once a test has cleared them.
                    val page = requestLine.startsWith("GET / ")
                    val body = if (page) "<html><body>ok</body></html>" else ""
                    it.getOutputStream().write(
                        (
                            "HTTP/1.1 ${if (page) "200 OK" else "404 Not Found"}\r\n" +
                                "Content-Type: text/html\r\n" +
                                (
                                    if (page) {
                                        "Set-Cookie: CF_Authorization=token-value; Path=/; Max-Age=3600; HttpOnly\r\n" +
                                            "Set-Cookie: visible=1; Path=/; Max-Age=3600\r\n"
                                    } else {
                                        ""
                                    }
                                    ) +
                                "Content-Length: ${body.length}\r\n" +
                                "Connection: close\r\n\r\n" + body
                            ).toByteArray()
                    )
                }
            }
        }.apply { isDaemon = true }.start()
        clear()
    }

    @After
    fun tearDown() {
        server.close()
        instrumentation.runOnMainSync { webView?.destroy() }
        clear()
    }

    private fun clear() {
        val done = CountDownLatch(1)
        instrumentation.runOnMainSync { EdgeCookies.clear { done.countDown() } }
        assertTrue(done.await(10, TimeUnit.SECONDS))
    }

    private fun header(): String? {
        var value: String? = null
        instrumentation.runOnMainSync { value = EdgeCookies.header("$origin/") }
        return value
    }

    private fun load() {
        val loaded = CountDownLatch(1)
        instrumentation.runOnMainSync {
            val view = WebView(instrumentation.targetContext)
            // evaluateJavascript answers "null" without it, which would pass the premise below.
            view.settings.javaScriptEnabled = true
            view.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) = loaded.countDown()
            }
            webView = view
            view.loadUrl("$origin/")
        }
        assertTrue("the page never finished loading", loaded.await(30, TimeUnit.SECONDS))
    }

    private fun pageSees(): String {
        val answer = CountDownLatch(1)
        var seen = ""
        instrumentation.runOnMainSync {
            webView!!.evaluateJavascript("document.cookie") {
                seen = it
                answer.countDown()
            }
        }
        assertTrue(answer.await(10, TimeUnit.SECONDS))
        return seen
    }

    @Test
    fun readsTheHttpOnlyCookieThePageCannotSee() {
        load()
        val seen = pageSees()
        // The premise: a script gets the plain cookie and not Access's.
        assertTrue(seen, seen.contains("visible=1"))
        assertFalse(seen, seen.contains("CF_Authorization"))

        val header = header()
        assertNotNull(header)
        assertTrue(header, header!!.contains("CF_Authorization=token-value"))
    }

    @Test
    fun holdsNothingForAnAddressItNeverVisited() {
        load()
        var other: String? = "unset"
        instrumentation.runOnMainSync { other = EdgeCookies.header("http://127.0.0.2:${server.localPort}/") }
        assertNull(other)
    }

    @Test
    fun clearEmptiesTheStoreBeforeItAnswers() {
        load()
        assertNotNull(header())
        clear()
        assertNull(header())
        assertEquals("", pageSees().trim('"'))
    }
}
