package page.codeberg.morganmlgman.bambuddy_mobile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.TypedValue

/**
 * Draws the circular progress gauge (ring) used by the compact 2x2 widget
 * variants. The ring itself is a Canvas bitmap; the centered percent/label sit
 * on top as real TextViews in the layout (crisper text, still localizable), so
 * this only renders the track + the accent arc.
 */
object WidgetGauge {

    /**
     * Builds a square ring bitmap sized [sizeDp] dp. [progress] is 0..100; when
     * [drawProgress] is false only the faint track is drawn (idle/offline/error).
     */
    fun build(
        context: Context,
        sizeDp: Int,
        progress: Int,
        accentColor: Int,
        drawProgress: Boolean,
    ): Bitmap {
        val size = dp(context, sizeDp.toFloat()).toInt()
        val stroke = dp(context, 7f)
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)

        val inset = stroke / 2f + dp(context, 1f)
        val rect = RectF(inset, inset, size - inset, size - inset)
        // rect uses Float; size is Int px, inset is Float dp.

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
            color = Color.argb(28, 255, 255, 255)
        }
        canvas.drawArc(rect, 0f, 360f, false, trackPaint)

        if (drawProgress && progress > 0) {
            val sweep = 360f * progress.coerceIn(0, 100) / 100f
            val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = stroke
                strokeCap = Paint.Cap.ROUND
                color = accentColor
            }
            // Start at 12 o'clock (-90) and sweep clockwise, matching the design.
            canvas.drawArc(rect, -90f, sweep, false, arcPaint)
        }
        return bmp
    }

    private fun dp(context: Context, value: Float): Float =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value, context.resources.displayMetrics
        )
}
