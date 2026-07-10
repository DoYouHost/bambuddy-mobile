package page.codeberg.morganmlgman.bambuddy_mobile

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Multi-printer home screen widget (resizable). Renders the fleet state saved by
 * the Dart side ([MultiWidgetPublisher]): up to [MAX_ROWS] printer rows (name,
 * status, sub-label, percent) with an "+N more" overflow line. At 2x2 it swaps
 * to a compact summary: a gauge with the printing count plus idle/offline
 * tallies. All labels are pre-localized in Dart; the native side only maps
 * status keys to colors and lays views out. Tapping the card opens the app.
 */
class BambuddyMultiWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { id -> render(context, appWidgetManager, id, widgetData) }
    }

    // Re-render on resize — switches the list/compact variant by width.
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
        val accentColor = ContextCompat.getColor(context, R.color.widget_accent)
        val title = widgetData.getString("multi_title", null) ?: "Printers"

        val views = RemoteViews(context.packageName, R.layout.bambuddy_multi_widget).apply {
            setTextViewText(R.id.widget_multi_title, title)
            setTextViewText(R.id.widget_multi_compact_title, title)
            setTextOrGone(R.id.widget_multi_count, widgetData.getString("multi_count", "") ?: "")

            val minWidthDp = appWidgetManager.getAppWidgetOptions(widgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val compact = minWidthDp in 1 until COMPACT_MAX_WIDTH_DP
            setViewVisibility(R.id.widget_multi_wide, visIf(!compact))
            setViewVisibility(R.id.widget_multi_compact, visIf(compact))

            if (compact) {
                renderCompact(context, widgetData, accentColor)
            } else {
                renderList(context, widgetData)
            }

            // Tap the card → open the app (printers list / dashboard).
            setOnClickPendingIntent(
                R.id.widget_multi_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )
        }
        appWidgetManager.updateAppWidget(widgetId, views)
    }

    private fun RemoteViews.renderList(context: Context, data: SharedPreferences) {
        for (i in 0 until MAX_ROWS) {
            val rowId = ROW_IDS[i]
            val name = data.getString("multi_name_$i", null)
            if (name.isNullOrEmpty()) {
                setViewVisibility(rowId, View.GONE)
                continue
            }
            setViewVisibility(rowId, View.VISIBLE)
            val statusKey = data.getString("multi_status_$i", null) ?: "offline"
            val color = ContextCompat.getColor(context, statusColorRes(statusKey))
            setInt(DOT_IDS[i], "setColorFilter", color)
            setTextViewText(NAME_IDS[i], name)
            setTextOrGone(SUB_IDS[i], data.getString("multi_sub_$i", "") ?: "")

            val pct = data.getInt("multi_pct_$i", -1)
            if (pct >= 0) {
                setTextViewText(PCT_IDS[i], "$pct%")
                setTextColor(PCT_IDS[i], color)
                setViewVisibility(PCT_IDS[i], View.VISIBLE)
            } else {
                setViewVisibility(PCT_IDS[i], View.GONE)
            }
        }
        setTextOrGone(R.id.widget_multi_more, data.getString("multi_more", "") ?: "")
    }

    private fun RemoteViews.renderCompact(
        context: Context,
        data: SharedPreferences,
        accentColor: Int,
    ) {
        val printing = data.getInt("multi_printing", 0)
        val total = data.getInt("multi_total", 0)
        val ratio = if (total > 0) printing * 100 / total else 0
        setImageViewBitmap(
            R.id.widget_multi_gauge,
            WidgetGauge.build(context, GAUGE_SIZE_DP, ratio, accentColor, printing > 0)
        )
        setTextViewText(R.id.widget_multi_gauge_count, printing.toString())
        setTextViewText(R.id.widget_multi_gauge_label, data.getString("multi_gauge_label", "") ?: "")

        val neutral = ContextCompat.getColor(context, R.color.widget_status_idle)
        setInt(R.id.widget_multi_idle_dot, "setColorFilter", neutral)
        setInt(R.id.widget_multi_offline_dot, "setColorFilter", neutral)
        toggleTally(
            R.id.widget_multi_idle_label, R.id.widget_multi_idle_dot,
            data.getString("multi_idle_label", "") ?: ""
        )
        toggleTally(
            R.id.widget_multi_offline_label, R.id.widget_multi_offline_dot,
            data.getString("multi_offline_label", "") ?: ""
        )
    }

    private fun RemoteViews.toggleTally(labelId: Int, dotId: Int, text: String) {
        val show = text.isNotEmpty()
        setTextViewText(labelId, text)
        setViewVisibility(labelId, visIf(show))
        setViewVisibility(dotId, visIf(show))
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
        /** Number of printer rows rendered in the list layout. */
        private const val MAX_ROWS = 3

        /** Below this min width (dp) the widget renders the compact 2x2 summary. */
        private const val COMPACT_MAX_WIDTH_DP = 190

        /** Gauge ring size (dp) — matches @id/widget_multi_gauge. */
        private const val GAUGE_SIZE_DP = 80

        private val ROW_IDS = intArrayOf(
            R.id.widget_multi_row_0, R.id.widget_multi_row_1, R.id.widget_multi_row_2
        )
        private val DOT_IDS = intArrayOf(
            R.id.widget_multi_dot_0, R.id.widget_multi_dot_1, R.id.widget_multi_dot_2
        )
        private val NAME_IDS = intArrayOf(
            R.id.widget_multi_name_0, R.id.widget_multi_name_1, R.id.widget_multi_name_2
        )
        private val SUB_IDS = intArrayOf(
            R.id.widget_multi_sub_0, R.id.widget_multi_sub_1, R.id.widget_multi_sub_2
        )
        private val PCT_IDS = intArrayOf(
            R.id.widget_multi_pct_0, R.id.widget_multi_pct_1, R.id.widget_multi_pct_2
        )
    }
}
