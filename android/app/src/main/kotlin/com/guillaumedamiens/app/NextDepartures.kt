package com.guillaumedamiens.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home screen widget (design 2k1): the next departures of a stop, one row per line and direction. Plain RemoteViews
 * and size options, so that it looks the same from Android 7 (the app's minimum) to the latest: the layout is chosen
 * from the size the launcher reports ([AppWidgetManager.getAppWidgetOptions]), not with Android 12's responsive
 * layouts.
 */
class NextDepartures : HomeWidgetProvider() {

    companion object {
        private val ROW_IDS = intArrayOf(R.id.departure_row_1, R.id.departure_row_2, R.id.departure_row_3, R.id.departure_row_4)
        private val LINE_IDS = intArrayOf(R.id.tv_line_1, R.id.tv_line_2, R.id.tv_line_3, R.id.tv_line_4)
        private val BADGE_IDS = intArrayOf(R.id.iv_line_1, R.id.iv_line_2, R.id.iv_line_3, R.id.iv_line_4)
        private val DEST_IDS = intArrayOf(R.id.tv_dest_1, R.id.tv_dest_2, R.id.tv_dest_3, R.id.tv_dest_4)
        private val NEXT_IDS = intArrayOf(R.id.tv_next_1, R.id.tv_next_2, R.id.tv_next_3, R.id.tv_next_4)
        private val TIME_IDS = intArrayOf(R.id.tv_time_1, R.id.tv_time_2, R.id.tv_time_3, R.id.tv_time_4)

        /** Narrower than this (dp, the launcher's minimum width in portrait): the small layout, one departure */
        private const val SMALL_WIDTH = 200
    }

    /**
     * One line and direction, as written by the app, one per line of text: `line|background|text color|time|destination|
     * mode|state|next` (colors in hex without `#`, `state` = `live`, `late` or empty, `next` the following departure or
     * empty). An older version of the app joined five fields per row with `||`: still read, until the app writes again.
     */
    private data class Row(
        val line: String,
        val background: Int,
        val foreground: Int,
        val time: String,
        val destination: String,
        val mode: String = "",
        val state: String = "",
        val next: String = "",
    )

    private fun color(hex: String?, fallback: Int): Int =
        try {
            if (hex.isNullOrEmpty()) fallback else Color.parseColor("#$hex")
        } catch (e: IllegalArgumentException) {
            fallback
        }

    private fun parse(data: String): List<Row> = (if ('\n' in data) data.split('\n') else data.split("||")).mapNotNull { row ->
        val parts = row.split("|")
        if (row.isBlank()) return@mapNotNull null
        when {
            parts.size >= 5 -> Row(
                parts[0], color(parts[1], Color.DKGRAY), color(parts[2], Color.WHITE), parts[3], parts[4],
                parts.getOrElse(5) { "" }, parts.getOrElse(6) { "" }, parts.getOrElse(7) { "" },
            )
            // Written by a much older version: `line  time|destination`
            parts.size == 2 -> Row(parts[0].substringBefore("  "), Color.DKGRAY, Color.WHITE, parts[0].substringAfter("  "), parts[1])
            else -> null
        }
    }

    /** The IDFM shape of a line's badge: round metro, rounded RER and train, square bus and tram */
    private fun badge(mode: String): Int = when (mode) {
        "metro" -> R.drawable.widget_badge_round
        "bus", "noctilien", "tram" -> R.drawable.widget_badge_bus
        else -> R.drawable.widget_badge_rail
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId -> render(context, appWidgetManager, widgetId, widgetData) }
    }

    /** Resized: the layout may change (on every launcher, since Android 4.1) */
    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    private fun render(context: Context, appWidgetManager: AppWidgetManager, widgetId: Int, widgetData: SharedPreferences) {
        val width = appWidgetManager.getAppWidgetOptions(widgetId).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        // Unknown (0): some old launchers don't say; the full layout, as placed at first
        val small = width in 1 until SMALL_WIDTH
        val rows = widgetData.getString("departures_json", null)?.let(::parse).orEmpty()
        val known = widgetData.contains("stop_id") || widgetData.contains("departures_json")
        val live = ContextCompat.getColor(context, R.color.widget_live)
        val late = ContextCompat.getColor(context, R.color.widget_late)
        val text = ContextCompat.getColor(context, R.color.widget_text)

        val views = RemoteViews(context.packageName, if (small) R.layout.next_departures_small else R.layout.next_departures).apply {
            val stopName = widgetData.getString("stop_name", null)
            setTextViewText(R.id.tv_stop_name, stopName ?: if (small) "" else context.getString(R.string.widget_no_stop))
            setViewVisibility(R.id.tv_stop_name, if (stopName == null && small) View.GONE else View.VISIBLE)

            if (rows.isEmpty()) {
                // Before any stop: what to do; then why nothing is shown
                val message = widgetData.getString("departures_list", null)
                    ?: context.getString(if (known) R.string.widget_no_departure else R.string.widget_tap_to_load)
                setViewVisibility(R.id.tv_status_message, View.VISIBLE)
                setTextViewText(R.id.tv_status_message, message)
            } else {
                setViewVisibility(R.id.tv_status_message, View.GONE)
            }

            // The small layout has one row, without destination nor following departure
            val shown = if (small) 1 else ROW_IDS.size
            for (i in 0 until shown) {
                val row = rows.getOrNull(i)
                setViewVisibility(ROW_IDS[i], if (row == null) View.GONE else View.VISIBLE)
                if (row == null) {
                    continue
                }
                setImageViewResource(BADGE_IDS[i], badge(row.mode))
                setInt(BADGE_IDS[i], "setColorFilter", row.background)
                setTextViewText(LINE_IDS[i], row.line)
                setTextColor(LINE_IDS[i], row.foreground)
                setTextViewText(TIME_IDS[i], row.time)
                setTextColor(TIME_IDS[i], when (row.state) {
                    "live" -> live
                    "late" -> late
                    else -> text
                })
                if (!small) {
                    setTextViewText(DEST_IDS[i], row.destination)
                    setViewVisibility(NEXT_IDS[i], if (row.next.isEmpty()) View.GONE else View.VISIBLE)
                    setTextViewText(NEXT_IDS[i], row.next)
                }
            }

            if (!small) {
                // Written by the app in its language ("Mis à jour : 08:05")
                setTextViewText(R.id.tv_last_updated, widgetData.getString("last_updated", null) ?: "")
                setOnClickPendingIntent(
                    R.id.btn_refresh,
                    HomeWidgetBackgroundIntent.getBroadcast(context, "guillaumedamiens://refreshdepartures".toUri())
                )
            }
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { intent ->
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                setOnClickPendingIntent(
                    R.id.widget_root,
                    PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                )
            }
        }
        appWidgetManager.updateAppWidget(widgetId, views)
    }
}
