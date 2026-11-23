package page.codeberg.morganmlgman.bambuddy_mobile

import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager

/**
 * What the `edge_cookie` channel does with the sign-in WebView's cookie store (#72), apart from
 * the channel so an instrumented test can drive it against a real WebView.
 */
object EdgeCookies {
    /**
     * The `Cookie` header the WebView would send to [url], HttpOnly cookies included:
     * Cloudflare Access's `CF_Authorization` is one, and no script in the page can see it.
     * Null when the store holds none.
     */
    fun header(url: String): String? = CookieManager.getInstance().getCookie(url)

    /**
     * Flushed before [done] runs: the store writes to disk in batches, and a process killed
     * now would bring the cookie back on the next start. The flush blocks on disk, so it runs
     * off the main thread that the removal reports on, and [done] is posted back to it (a
     * channel result is answered there).
     */
    fun clear(done: () -> Unit) {
        val cookies = CookieManager.getInstance()
        val main = Handler(Looper.getMainLooper())
        cookies.removeAllCookies {
            Thread {
                cookies.flush()
                main.post(done)
            }.start()
        }
    }
}
