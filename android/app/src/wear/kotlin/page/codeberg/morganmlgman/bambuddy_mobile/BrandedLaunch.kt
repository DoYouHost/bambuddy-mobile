package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.Activity
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen

/**
 * Hands `WearLaunchTheme` to core-splashscreen, which is what puts the app icon on
 * screen on Wear OS 3 as well: API 30 has no system splash, and that icon is what
 * Play's Wear quality check (WO-V15) looks for. Must run before
 * `super.onCreate`, i.e. before FlutterActivity swaps the window to NormalTheme.
 *
 * It lives in the flavor source set because the library is a `wearImplementation`
 * dependency: both flavors compile `src/main`, so the phone build must not see this
 * call — its no-op twin is in `src/mobile`.
 */
fun Activity.installBrandedLaunch() {
    installSplashScreen()
}
