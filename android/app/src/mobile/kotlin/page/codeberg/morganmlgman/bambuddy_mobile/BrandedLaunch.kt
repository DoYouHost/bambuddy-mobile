package page.codeberg.morganmlgman.bambuddy_mobile

import android.app.Activity

/**
 * No-op twin of the watch's branded launch: the phone keeps Flutter's stock
 * LaunchTheme/NormalTheme pair, and core-splashscreen is not on its classpath.
 * See the same file in `src/wear` for what this stands in for.
 */
fun Activity.installBrandedLaunch() = Unit
