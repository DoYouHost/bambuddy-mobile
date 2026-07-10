package page.codeberg.morganmlgman.bambuddy_mobile

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Home screen widget (resizable, min 2x2). Renders the state of ONE printer
 * saved by the Dart side ([HomeWidgetPublisher]): name, status (or HMS error
 * text), print name, ETA, layers and progress bar. At larger sizes it adds the
 * current print's thumbnail; at 2x2 it swaps to a compact circular gauge. The
 * scan button opens the app via the `bambuddy://widget?action=scan` deep link.
 */
class BambuddyWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { id -> render(context, appWidgetManager, id, widgetData) }
    }

    // Re-render on resize (edge drag) — switches the compact/wide variant.
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        widgetData: SharedPreferences
    ) {
        val printerName = widgetData.getString("printer_name", null) ?: "BambuBuddy"
        val statusLabel = widgetData.getString("status_label", null) ?: ""
        val errorText = widgetData.getString("error_text", null) ?: ""
        val printName = widgetData.getString("print_name", null) ?: ""
        val statusKey = widgetData.getString("status_key", null) ?: "offline"
        val eta = widgetData.getString("eta", null) ?: ""
        val layers = widgetData.getString("layers", null) ?: ""
        val coverPath = widgetData.getString("cover_path", null) ?: ""
        val progress = widgetData.getInt("progress", 0).coerceIn(0, 100)
        val printing = widgetData.getBoolean("printing", false)

        val statusColor = ContextCompat.getColor(context, statusColorRes(statusKey))
        val accentColor = ContextCompat.getColor(context, R.color.widget_accent)

        val views = RemoteViews(context.packageName, R.layout.bambuddy_widget).apply {
            setTextViewText(R.id.widget_printer_name, printerName)
            setTextViewText(R.id.widget_status_label, statusLabel)
            setTextColor(R.id.widget_status_label, statusColor)
            setInt(R.id.widget_status_dot, "setColorFilter", statusColor)
            setInt(R.id.widget_accent_line, "setBackgroundColor", statusColor)
            // Tint the scan icon with the mint accent (button bg is now a subtle surface).
            setInt(R.id.widget_scan_button, "setColorFilter", accentColor)
            // Status pill: background (outline + faint fill) in the status color.
            setInt(R.id.widget_status_label, "setBackgroundResource", chipRes(statusKey))

            // HMS error wins the central band: the full sentence (wraps) instead
            // of the preview/quip; the pill only carries a short "Error" label.
            val showError = statusKey == "error" && errorText.isNotEmpty()

            // Row 2 (thumbnail + print name) only while printing (not on error).
            setViewVisibility(R.id.widget_file_row, visIf(!showError && printName.isNotEmpty()))
            setTextViewText(R.id.widget_print_name, printName)

            if (showError) {
                setTextViewText(R.id.widget_error_text, errorText)
                setTextColor(R.id.widget_error_text, statusColor)
                setViewVisibility(R.id.widget_error_text, View.VISIBLE)
            } else {
                setViewVisibility(R.id.widget_error_text, View.GONE)
            }

            // Instead of a preview: a jokey line when the printer is idle/offline
            // (not on error).
            val showQuip = !showError && (statusKey == "idle" || statusKey == "offline")
            if (showQuip) {
                setTextViewText(R.id.widget_quip, randomQuip(context))
                setViewVisibility(R.id.widget_quip, View.VISIBLE)
            } else {
                setViewVisibility(R.id.widget_quip, View.GONE)
            }

            // Meta: ETA + layers, each member toggled separately; whole row gone
            // when both are empty.
            setTextOrGone(R.id.widget_eta, eta)
            setViewVisibility(R.id.widget_eta_icon, visIf(eta.isNotEmpty()))
            setTextOrGone(R.id.widget_layers, layers)
            setViewVisibility(R.id.widget_layers_icon, visIf(layers.isNotEmpty()))
            setViewVisibility(R.id.widget_meta_row, visIf(eta.isNotEmpty() || layers.isNotEmpty()))

            // Progress bar only during an active print (printing/paused).
            if (printing) {
                setViewVisibility(R.id.widget_progress_row, View.VISIBLE)
                setProgressBar(R.id.widget_progress, 100, progress, false)
                setTextViewText(R.id.widget_progress_text, "$progress%")
            } else {
                setViewVisibility(R.id.widget_progress_row, View.GONE)
            }

            // Thumbnail: whenever we have a cover file. The size is chosen by the
            // layout (weight=1 row + match_parent/adjustViewBounds thumbnail), so
            // it adapts to any size/DPI with no dp math in code.
            val bitmap = if (coverPath.isNotEmpty()) decodeCover(coverPath) else null
            when {
                bitmap != null -> {
                    setImageViewBitmap(R.id.widget_thumbnail, bitmap)
                    setViewVisibility(R.id.widget_thumbnail, View.VISIBLE)
                }
                // Print without a cover (e.g. calibration) — placeholder over emptiness.
                printing -> {
                    setImageViewResource(
                        R.id.widget_thumbnail, R.drawable.widget_cover_placeholder)
                    setViewVisibility(R.id.widget_thumbnail, View.VISIBLE)
                }
                else -> setViewVisibility(R.id.widget_thumbnail, View.GONE)
            }

            // Width-gated compact 2x2 mode: swap to the square gauge layout on
            // narrow sizes. MIN_WIDTH is the portrait (narrow) width — the right
            // signal here (unlike MIN_HEIGHT, which understates in portrait).
            val minWidthDp = appWidgetManager.getAppWidgetOptions(widgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val compact = minWidthDp in 1 until COMPACT_MAX_WIDTH_DP
            setViewVisibility(R.id.widget_wide, visIf(!compact))
            setViewVisibility(R.id.widget_compact, visIf(compact))
            if (compact) {
                setInt(R.id.widget_compact_dot, "setColorFilter", statusColor)
                setTextViewText(R.id.widget_compact_name, printerName)
                setImageViewBitmap(
                    R.id.widget_gauge,
                    WidgetGauge.build(context, GAUGE_SIZE_DP, progress, statusColor, printing)
                )
                if (printing) {
                    setViewVisibility(R.id.widget_gauge_pct, View.VISIBLE)
                    setTextViewText(R.id.widget_gauge_pct, "$progress%")
                    setViewVisibility(R.id.widget_gauge_sub, View.GONE)
                    setTextOrGone(R.id.widget_compact_eta, eta)
                } else {
                    // Not printing: empty ring with the status word centered, no ETA.
                    setViewVisibility(R.id.widget_gauge_pct, View.GONE)
                    setTextViewText(R.id.widget_gauge_sub, statusLabel)
                    setTextColor(R.id.widget_gauge_sub, statusColor)
                    setViewVisibility(R.id.widget_gauge_sub, View.VISIBLE)
                    setViewVisibility(R.id.widget_compact_eta, View.GONE)
                }
            }

            // Tap the card → open the app (dashboard).
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )
            // Tap the scan button → open the app with the scanner deep link.
            setOnClickPendingIntent(
                R.id.widget_scan_button,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("bambuddy://widget?action=scan")
                )
            )
        }
        appWidgetManager.updateAppWidget(widgetId, views)
    }

    private fun RemoteViews.setTextOrGone(viewId: Int, text: String) {
        if (text.isNotEmpty()) {
            setTextViewText(viewId, text)
            setViewVisibility(viewId, View.VISIBLE)
        } else {
            setViewVisibility(viewId, View.GONE)
        }
    }

    private fun visIf(show: Boolean) = if (show) View.VISIBLE else View.GONE

    /** Decodes the cover from file, downsampling to ~512 px (RemoteViews transaction
     *  limit). Crops the central ~83% (120% zoom) because the cover render has empty
     *  margins around the model — so the preview fills the tile without resizing it. */
    private fun decodeCover(path: String): android.graphics.Bitmap? {
        val file = File(path)
        if (!file.exists()) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            val widest = maxOf(bounds.outWidth, bounds.outHeight)
            while (widest / sample > 512) sample *= 2
            val full = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
                ?: return null
            zoomCrop(full, COVER_ZOOM)
        } catch (e: Exception) {
            null
        }
    }

    /** Enlarges the bitmap content by [zoom], cropping the central rectangle. */
    private fun zoomCrop(src: android.graphics.Bitmap, zoom: Float): android.graphics.Bitmap {
        if (zoom <= 1f) return src
        val w = (src.width / zoom).toInt().coerceIn(1, src.width)
        val h = (src.height / zoom).toInt().coerceIn(1, src.height)
        val x = (src.width - w) / 2
        val y = (src.height - h) / 2
        return android.graphics.Bitmap.createBitmap(src, x, y, w, h)
    }

    /** Random quip from resources (set depends on launcher language — PL/EN separate).
     *  Indexed by a 15-min window: stable across refreshes, rotates over time. */
    private fun randomQuip(context: Context): String {
        val quips = context.resources.getStringArray(R.array.widget_idle_quips)
        if (quips.isEmpty()) return ""
        val bucket = System.currentTimeMillis() / (15 * 60 * 1000)
        return quips[(bucket % quips.size).toInt()]
    }

    private fun chipRes(key: String): Int = when (key) {
        "printing" -> R.drawable.widget_chip_printing
        "paused" -> R.drawable.widget_chip_paused
        "finished" -> R.drawable.widget_chip_finished
        "failed" -> R.drawable.widget_chip_failed
        "error" -> R.drawable.widget_chip_failed
        "idle" -> R.drawable.widget_chip_idle
        else -> R.drawable.widget_chip_offline
    }

    private fun statusColorRes(key: String): Int = when (key) {
        "printing" -> R.color.widget_status_printing
        "paused" -> R.color.widget_status_paused
        "finished" -> R.color.widget_status_finished
        "failed" -> R.color.widget_status_failed
        "error" -> R.color.widget_status_error
        "idle" -> R.color.widget_status_idle
        else -> R.color.widget_status_offline
    }

    companion object {
        /** Cover preview zoom (crops the render's empty margins). */
        private const val COVER_ZOOM = 1.2f

        /** Below this min width (dp) the widget renders the compact 2x2 layout.
         *  A 2x2 reports ~110-150dp; a 3x2 reports ~210dp+. */
        private const val COMPACT_MAX_WIDTH_DP = 190

        /** Gauge ring size (dp) in the compact layout — matches @id/widget_gauge. */
        private const val GAUGE_SIZE_DP = 86
    }
}
