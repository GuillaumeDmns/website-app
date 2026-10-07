package com.guillaumedamiens.website_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider
import androidx.core.net.toUri

class NextDepartures : HomeWidgetProvider() {

    companion object {
        private val ROW_IDS = intArrayOf(R.id.departure_row_1, R.id.departure_row_2, R.id.departure_row_3, R.id.departure_row_4)
        private val LINE_IDS = intArrayOf(R.id.tv_line_1, R.id.tv_line_2, R.id.tv_line_3, R.id.tv_line_4)
        private val PILL_IDS = intArrayOf(R.id.iv_line_1, R.id.iv_line_2, R.id.iv_line_3, R.id.iv_line_4)
        private val DEST_IDS = intArrayOf(R.id.tv_dest_1, R.id.tv_dest_2, R.id.tv_dest_3, R.id.tv_dest_4)
        private val TIME_IDS = intArrayOf(R.id.tv_time_1, R.id.tv_time_2, R.id.tv_time_3, R.id.tv_time_4)
    }

    /** One departure, as written by the app: `line|background|text color|time|destination` (colors in hex, no `#`) */
    private data class Row(val line: String, val background: Int, val foreground: Int, val time: String, val destination: String)

    private fun color(hex: String?, fallback: Int): Int =
        try {
            if (hex.isNullOrEmpty()) fallback else Color.parseColor("#$hex")
        } catch (e: IllegalArgumentException) {
            fallback
        }

    private fun parse(data: String): List<Row> = data.split("||").mapNotNull { row ->
        val parts = row.split("|")
        when {
            parts.size >= 5 -> Row(parts[0], color(parts[1], Color.DKGRAY), color(parts[2], Color.WHITE), parts[3], parts[4])
            // Written by an older version: `line  time|destination`
            parts.size == 2 -> Row(parts[0].substringBefore("  "), Color.DKGRAY, Color.WHITE, parts[0].substringAfter("  "), parts[1])
            else -> null
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.next_departures).apply {
                setTextViewText(R.id.tv_stop_name, widgetData.getString("stop_name", null) ?: context.getString(R.string.widget_no_stop))
                // Written by the app in its language ("Mis à jour : 08:05")
                setTextViewText(R.id.tv_last_updated, widgetData.getString("last_updated", null) ?: "")

                val rows = widgetData.getString("departures_json", null)?.let(::parse).orEmpty()
                if (rows.isEmpty()) {
                    val message = widgetData.getString("departures_list", null)
                        ?: context.getString(if (widgetData.contains("departures_json")) R.string.widget_no_departure else R.string.widget_tap_to_load)
                    setViewVisibility(R.id.tv_status_message, View.VISIBLE)
                    setTextViewText(R.id.tv_status_message, message)
                } else {
                    setViewVisibility(R.id.tv_status_message, View.GONE)
                }
                for (i in ROW_IDS.indices) {
                    val row = rows.getOrNull(i)
                    setViewVisibility(ROW_IDS[i], if (row == null) View.GONE else View.VISIBLE)
                    if (row != null) {
                        setTextViewText(LINE_IDS[i], row.line)
                        setTextColor(LINE_IDS[i], row.foreground)
                        setInt(PILL_IDS[i], "setColorFilter", row.background)
                        setTextViewText(DEST_IDS[i], row.destination)
                        setTextViewText(TIME_IDS[i], row.time)
                    }
                }

                setOnClickPendingIntent(
                    R.id.btn_refresh,
                    HomeWidgetBackgroundIntent.getBroadcast(context, "guillaumedamiens://refreshdepartures".toUri())
                )
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
}
