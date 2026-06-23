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
 * Widget ekranu głównego (zmienny rozmiar, min 2x2). Renderuje stan JEDNEJ
 * drukarki zapisany przez stronę Dart ([HomeWidgetPublisher]): nazwę, status
 * (lub treść błędu HMS), nazwę wydruku, ETA, warstwy i pasek postępu. Przy
 * większych rozmiarach dokłada miniaturę bieżącego wydruku. Przycisk skanera
 * otwiera apkę deep-linkiem `bambuddy://widget?action=scan`.
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

    // Re-render po zmianie rozmiaru (przeciągnięcie krawędzi) — przełącza
    // wariant kompaktowy/duży (miniatura).
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
        val printName = widgetData.getString("print_name", null) ?: ""
        val statusKey = widgetData.getString("status_key", null) ?: "offline"
        val eta = widgetData.getString("eta", null) ?: ""
        val layers = widgetData.getString("layers", null) ?: ""
        val coverPath = widgetData.getString("cover_path", null) ?: ""
        val progress = widgetData.getInt("progress", 0).coerceIn(0, 100)
        val printing = widgetData.getBoolean("printing", false)

        val statusColor = ContextCompat.getColor(context, statusColorRes(statusKey))
        val wide = isWide(appWidgetManager, widgetId)

        val views = RemoteViews(context.packageName, R.layout.bambuddy_widget).apply {
            setTextViewText(R.id.widget_printer_name, printerName)
            setTextViewText(R.id.widget_status_label, statusLabel)
            setTextColor(R.id.widget_status_label, statusColor)
            setInt(R.id.widget_status_dot, "setColorFilter", statusColor)

            // Wiersz 2 (miniatura + nazwa wydruku) tylko podczas druku.
            setViewVisibility(R.id.widget_file_row, visIf(printName.isNotEmpty()))
            setTextViewText(R.id.widget_print_name, printName)

            // Meta: ETA + warstwy, każdy człon osobno, cały wiersz gdy oba puste.
            setTextOrGone(R.id.widget_eta, eta)
            setViewVisibility(R.id.widget_eta_icon, visIf(eta.isNotEmpty()))
            setTextOrGone(R.id.widget_layers, layers)
            setViewVisibility(R.id.widget_layers_icon, visIf(layers.isNotEmpty()))
            setViewVisibility(R.id.widget_meta_row, visIf(eta.isNotEmpty() || layers.isNotEmpty()))

            // Pasek postępu tylko przy aktywnym druku (drukuje/pauza).
            if (printing) {
                setViewVisibility(R.id.widget_progress_row, View.VISIBLE)
                setProgressBar(R.id.widget_progress, 100, progress, false)
                setTextViewText(R.id.widget_progress_text, "$progress%")
            } else {
                setViewVisibility(R.id.widget_progress_row, View.GONE)
            }

            // Miniatura: tylko gdy widget dość szeroki i mamy plik okładki.
            val bitmap = if (wide && coverPath.isNotEmpty()) decodeCover(coverPath) else null
            if (bitmap != null) {
                setImageViewBitmap(R.id.widget_thumbnail, bitmap)
                setViewVisibility(R.id.widget_thumbnail, View.VISIBLE)
            } else {
                setViewVisibility(R.id.widget_thumbnail, View.GONE)
            }

            // Tap na kartę → otwórz apkę (dashboard).
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )
            // Tap na przycisk skanera → otwórz apkę z deep-linkiem skanera.
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

    /** Miniaturę (mały kwadrat po lewej) pokazujemy, gdy widget jest dość szeroki
     *  — 2x2 (≈150dp) jest za wąski na okładkę + tekst, 4x2 (≈360dp) już mieści. */
    private fun isWide(appWidgetManager: AppWidgetManager, widgetId: Int): Boolean {
        val options = appWidgetManager.getAppWidgetOptions(widgetId)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        return minWidth >= 250
    }

    /** Dekoduje okładkę z pliku, downsamplując do ~512 px (limit transakcji RemoteViews). */
    private fun decodeCover(path: String): android.graphics.Bitmap? {
        val file = File(path)
        if (!file.exists()) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            val widest = maxOf(bounds.outWidth, bounds.outHeight)
            while (widest / sample > 512) sample *= 2
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
        } catch (e: Exception) {
            null
        }
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
}
