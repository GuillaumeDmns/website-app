package com.guillaumedamiens.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.core.net.toUri
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home screen widget "Mes lignes": the traffic of the user's favorite lines, the interrupted and disrupted ones first
 * with their first disruption's title. No setup: every such widget shows the same lines, which the app writes
 * (`traffic_widget.dart`): `traffic_rows` (`id|name|background|text color|mode|state|title`, state `b` interrupted,
 * `d` disrupted, `n` normal), `traffic_message`, `traffic_updated`, `traffic_fetched_at`. Fetched by the app's home
 * page, its refresh button, [WidgetRefreshWorker] every 15 min while the screen is on, and as the screen comes back on
 * when over 10 min old; the traffic is the backend's snapshot of the whole network, which costs no PRIM quota.
 * Tapping a line opens it, the rest of the widget the traffic page.
 */
class LinesTraffic : HomeWidgetProvider() {

    private data class Row(
        val id: String,
        val name: String,
        val background: Int,
        val foreground: Int,
        val mode: String,
        val state: Char,
        val title: String,
    )

    companion object {
        private const val STALE_MS = 10 * 60_000L
        private const val FETCHED_AT = "traffic_fetched_at"
        private const val ASKED_AT = "traffic_asked_at"

        fun ids(context: Context): IntArray =
            AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, LinesTraffic::class.java))

        /** The app fetches the traffic of the favorite lines in the background (`homeWidgetBackgroundCallback`) */
        fun requestRefresh(context: Context) {
            HomeWidgetPlugin.getData(context).edit { putString(ASKED_AT, System.currentTimeMillis().toString()) }
            refreshIntent(context).send()
        }

        private fun refreshIntent(context: Context): PendingIntent =
            HomeWidgetBackgroundIntent.getBroadcast(context, "guillaumedamiens://refreshtraffic".toUri())
    }

    private fun color(hex: String?, fallback: Int): Int =
        try {
            if (hex.isNullOrEmpty()) fallback else Color.parseColor("#$hex")
        } catch (e: IllegalArgumentException) {
            fallback
        }

    private fun parse(data: String?): List<Row> = data.orEmpty().split('\n').mapNotNull { line ->
        val parts = line.split('|')
        if (parts.size < 7 || parts[0].isEmpty()) return@mapNotNull null
        Row(
            id = parts[0],
            name = parts[1],
            background = color(parts[2], Color.DKGRAY),
            foreground = color(parts[3], Color.WHITE),
            mode = parts[4],
            state = parts[5].firstOrNull() ?: 'n',
            title = parts[6],
        )
    }

    /** The IDFM shape of a line's badge, as on the departures widget */
    private fun badge(mode: String): Int = when (mode) {
        "metro" -> R.drawable.widget_badge_round
        "bus", "noctilien", "tram" -> R.drawable.widget_badge_bus
        else -> R.drawable.widget_badge_rail
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { render(context, appWidgetManager, it, widgetData) }
        afterRender(context, widgetData)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    /** The last one removed: the periodic fetch stops unless a departures widget still needs it */
    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetRefreshWorker.update(context)
    }

    private fun render(context: Context, appWidgetManager: AppWidgetManager, widgetId: Int, widgetData: SharedPreferences) {
        // Portrait height, which phones use; unknown (0) on some old launchers: as placed at first
        val height = appWidgetManager.getAppWidgetOptions(widgetId).getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        val rows = parse(widgetData.getString("traffic_rows", null))
        // Nothing written yet: the app has never run since the widget came
        val message = widgetData.getString("traffic_message", null)
            ?: context.getString(if (widgetData.contains("traffic_lines")) R.string.traffic_widget_loading else R.string.traffic_widget_open_app)
        val views = RemoteViews(context.packageName, R.layout.lines_traffic).apply {
            setTextViewText(R.id.tv_updated, widgetData.getString("traffic_updated", null).orEmpty())
            setOnClickPendingIntent(R.id.btn_refresh, refreshIntent(context))
            setOnClickPendingIntent(R.id.widget_root, open(context, "guillaumedamiens://traffic"))
            // The header takes about 52 dp, a row 34 (one line) to 46 (with a title)
            val fits = if (height <= 0) 3 else ((height - 52) / 42).coerceIn(1, 8)
            removeAllViews(R.id.rows)
            rows.take(fits).forEach { row -> addView(R.id.rows, row(context, row)) }
            setViewVisibility(R.id.rows, if (rows.isEmpty()) View.GONE else View.VISIBLE)
            setViewVisibility(R.id.tv_status_message, if (rows.isEmpty()) View.VISIBLE else View.GONE)
            setTextViewText(R.id.tv_status_message, message)
        }
        appWidgetManager.updateAppWidget(widgetId, views)
    }

    private fun row(context: Context, row: Row) = RemoteViews(context.packageName, R.layout.lines_traffic_row).apply {
        setImageViewResource(R.id.iv_badge, badge(row.mode))
        setInt(R.id.iv_badge, "setColorFilter", row.background)
        setTextViewText(R.id.tv_line, row.name)
        setTextColor(R.id.tv_line, row.foreground)
        val (text, color) = when (row.state) {
            'b' -> R.string.traffic_widget_interrupted to R.color.widget_cancelled
            'd' -> R.string.traffic_widget_disrupted to R.color.widget_late
            else -> R.string.traffic_widget_normal to R.color.widget_live
        }
        setTextViewText(R.id.tv_state, context.getString(text))
        setTextColor(R.id.tv_state, ContextCompat.getColor(context, color))
        setViewVisibility(R.id.tv_title, if (row.title.isEmpty()) View.GONE else View.VISIBLE)
        setTextViewText(R.id.tv_title, row.title)
        setContentDescription(R.id.row_root, "${row.name}, ${context.getString(text)}. ${row.title}".trim())
        setOnClickPendingIntent(R.id.row_root, open(context, "guillaumedamiens://line?id=${Uri.encode(row.id)}"))
    }

    /** Opens the app at [uri]: each link its own pending intent (they differ by their data) */
    private fun open(context: Context, uri: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri.toUri())

    /** After drawing: the periodic fetch, and the traffic again once the screen is back on if stale */
    private fun afterRender(context: Context, widgetData: SharedPreferences) {
        WidgetRefreshWorker.update(context)
        val now = System.currentTimeMillis()
        val fetchedAt = widgetData.getString(FETCHED_AT, null)?.toLongOrNull() ?: 0
        val askedAt = widgetData.getString(ASKED_AT, null)?.toLongOrNull() ?: 0
        val interactive = context.getSystemService(PowerManager::class.java).isInteractive
        if (interactive && widgetData.contains("traffic_lines") && now - fetchedAt > STALE_MS && now - askedAt > STALE_MS / 2) {
            requestRefresh(context)
        }
    }
}
