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
        val errorText = widgetData.getString("error_text", null) ?: ""
        val printName = widgetData.getString("print_name", null) ?: ""
        val statusKey = widgetData.getString("status_key", null) ?: "offline"
        val eta = widgetData.getString("eta", null) ?: ""
        val layers = widgetData.getString("layers", null) ?: ""
        val coverPath = widgetData.getString("cover_path", null) ?: ""
        val progress = widgetData.getInt("progress", 0).coerceIn(0, 100)
        val printing = widgetData.getBoolean("printing", false)

        val statusColor = ContextCompat.getColor(context, statusColorRes(statusKey))

        val views = RemoteViews(context.packageName, R.layout.bambuddy_widget).apply {
            setTextViewText(R.id.widget_printer_name, printerName)
            setTextViewText(R.id.widget_status_label, statusLabel)
            setTextColor(R.id.widget_status_label, statusColor)
            setInt(R.id.widget_status_dot, "setColorFilter", statusColor)
            setInt(R.id.widget_accent_line, "setBackgroundColor", statusColor)
            // Chip statusu: tło (obrys + lekkie wypełnienie) w kolorze statusu.
            setInt(R.id.widget_status_label, "setBackgroundResource", chipRes(statusKey))

            // Błąd HMS ma pierwszeństwo w centralnym pasie: pełne zdanie (zawija
            // się) zamiast podglądu/żartu; chip niesie tylko krótkie „Błąd".
            val showError = statusKey == "error" && errorText.isNotEmpty()

            // Wiersz 2 (miniatura + nazwa wydruku) tylko podczas druku (nie przy błędzie).
            setViewVisibility(R.id.widget_file_row, visIf(!showError && printName.isNotEmpty()))
            setTextViewText(R.id.widget_print_name, printName)

            if (showError) {
                setTextViewText(R.id.widget_error_text, errorText)
                setTextColor(R.id.widget_error_text, statusColor)
                setViewVisibility(R.id.widget_error_text, View.VISIBLE)
            } else {
                setViewVisibility(R.id.widget_error_text, View.GONE)
            }

            // Zamiast podglądu: żartobliwy tekst, gdy drukarka idle/offline (nie przy błędzie).
            val showQuip = !showError && (statusKey == "idle" || statusKey == "offline")
            if (showQuip) {
                setTextViewText(R.id.widget_quip, randomQuip(context))
                setViewVisibility(R.id.widget_quip, View.VISIBLE)
            } else {
                setViewVisibility(R.id.widget_quip, View.GONE)
            }

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

            // Miniatura: zawsze gdy mamy plik okładki. Rozmiar dobiera sam layout
            // (wiersz z weight=1 + miniatura match_parent/adjustViewBounds), więc
            // dopasowuje się do każdego rozmiaru/DPI bez liczenia w kodzie.
            val bitmap = if (coverPath.isNotEmpty()) decodeCover(coverPath) else null
            when {
                bitmap != null -> {
                    setImageViewBitmap(R.id.widget_thumbnail, bitmap)
                    setViewVisibility(R.id.widget_thumbnail, View.VISIBLE)
                }
                // Druk bez okładki (np. kalibracja) — placeholder zamiast pustki.
                printing -> {
                    setImageViewResource(
                        R.id.widget_thumbnail, R.drawable.widget_cover_placeholder)
                    setViewVisibility(R.id.widget_thumbnail, View.VISIBLE)
                }
                else -> setViewVisibility(R.id.widget_thumbnail, View.GONE)
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

    /** Dekoduje okładkę z pliku, downsamplując do ~512 px (limit transakcji RemoteViews).
     *  Przycina centralne ~83% (zoom 120%), bo render okładki ma puste marginesy wokół
     *  modelu — dzięki temu podgląd wypełnia kafel bez zmiany jego rozmiaru. */
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

    /** Powiększa zawartość bitmapy o [zoom], przycinając centralny prostokąt. */
    private fun zoomCrop(src: android.graphics.Bitmap, zoom: Float): android.graphics.Bitmap {
        if (zoom <= 1f) return src
        val w = (src.width / zoom).toInt().coerceIn(1, src.width)
        val h = (src.height / zoom).toInt().coerceIn(1, src.height)
        val x = (src.width - w) / 2
        val y = (src.height - h) / 2
        return android.graphics.Bitmap.createBitmap(src, x, y, w, h)
    }

    /** Losowy żart z zasobów (zestaw zależny od języka launchera — PL/EN osobno).
     *  Indeks po 15-min oknie: stabilny przy odświeżeniach, rotuje w czasie. */
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
        /** Powiększenie podglądu okładki (przycięcie pustych marginesów renderu). */
        private const val COVER_ZOOM = 1.2f
    }
}
