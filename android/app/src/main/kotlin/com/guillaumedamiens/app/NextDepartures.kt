package com.guillaumedamiens.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.text.format.DateFormat
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.core.net.toUri
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Date

/**
 * Home screen widget (designs 1A and 1C): the next departures of the stop its user chose for it
 * ([WidgetConfigureActivity], the app's `WidgetSetupScreen`), one row per line and direction. Each widget has its own
 * stop: the app writes its departures under `w<id>_…` keys (`android_widgets.dart`), with their times, and the widget
 * makes what it shows of them each time it is drawn: the departures that left are dropped, and within the hour it
 * says how long until them ("4 min") when it can be drawn again every minute ([canShowTimeLeft]), the clock time
 * otherwise. It is drawn again by an alarm that doesn't wake the device ([scheduleRedraw]); the departures are fetched
 * again by the app, its refresh button, [WidgetRefreshWorker] and, once the screen is back on, by that alarm.
 *
 * Plain RemoteViews and size options, so that it looks the same from Android 7 (the app's minimum) to the latest.
 */
class NextDepartures : HomeWidgetProvider() {

    /** A line and direction as the app writes it: `line|background|text color|mode|destination|times` */
    private data class Row(
        val line: String,
        val background: Int,
        val foreground: Int,
        val mode: String,
        val destination: String,
        val departures: List<Departure>,
    )

    /** `seconds:state` (`l` real time, `d` late, `s` scheduled) */
    private data class Departure(val at: Long, val state: Char)

    companion object {
        private const val ACTION_REDRAW = "com.guillaumedamiens.app.widget.REDRAW"

        /** Narrower than this (dp, the launcher's minimum width in portrait): the small layout, one departure */
        private const val SMALL_WIDTH = 200

        /** Fetched longer ago, the widget asks for its departures again as the screen comes back on */
        private const val STALE_MS = 10 * 60_000L

        /** When the app last fetched the widgets' departures (ms since the epoch, written by the app) */
        private const val FETCHED_AT = "widgets_fetched_at"

        /** When the widget last asked for them, so that a failure doesn't ask again at every redraw */
        private const val ASKED_AT = "widgets_asked_at"

        private fun key(widgetId: Int, name: String) = "w${widgetId}_$name"

        private fun ids(context: Context): IntArray =
            AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, NextDepartures::class.java))

        /** Whether the widget can be drawn every minute on time (exact alarms), so as to show the time left */
        fun canShowTimeLeft(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()

        /** Draws every widget again, from what the app last wrote */
        fun redrawAll(context: Context) {
            val ids = ids(context)
            if (ids.isNotEmpty()) {
                context.sendBroadcast(Intent(context, NextDepartures::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                })
            }
        }

        /** The app fetches the departures of every widget's stop in the background (`homeWidgetBackgroundCallback`) */
        fun requestRefresh(context: Context) {
            HomeWidgetPlugin.getData(context).edit { putString(ASKED_AT, System.currentTimeMillis().toString()) }
            HomeWidgetBackgroundIntent.getBroadcast(context, "guillaumedamiens://refreshdepartures".toUri()).send()
        }
    }

    private fun color(hex: String?, fallback: Int): Int =
        try {
            if (hex.isNullOrEmpty()) fallback else Color.parseColor("#$hex")
        } catch (e: IllegalArgumentException) {
            fallback
        }

    private fun parse(data: String?): List<Row> = data.orEmpty().split('\n').mapNotNull { line ->
        val parts = line.split('|')
        if (parts.size < 6) return@mapNotNull null
        Row(
            line = parts[0],
            background = color(parts[1], Color.DKGRAY),
            foreground = color(parts[2], Color.WHITE),
            mode = parts[3],
            destination = parts[4],
            departures = parts[5].split(',').mapNotNull { departure ->
                val at = departure.substringBefore(':').toLongOrNull() ?: return@mapNotNull null
                Departure(at * 1000, departure.substringAfter(':', "s").firstOrNull() ?: 's')
            },
        )
    }

    /** The rows still to come at [now]: their departures that left dropped, the soonest first */
    private fun upcoming(rows: List<Row>, now: Long): List<Row> = rows
        .map { row -> row.copy(departures = row.departures.filter { it.at > now }) }
        .filter { it.departures.isNotEmpty() }
        .sortedBy { it.departures.first().at }

    /** The IDFM shape of a line's badge: round metro, rounded RER and train, square bus and tram */
    private fun badge(mode: String): Int = when (mode) {
        "metro" -> R.drawable.widget_badge_round
        "bus", "noctilien", "tram" -> R.drawable.widget_badge_bus
        else -> R.drawable.widget_badge_rail
    }

    /** "4 min" within the hour when the widget is drawn every minute, else the clock time in the device's format */
    private fun label(context: Context, departure: Departure, now: Long, timeLeft: Boolean): String {
        val minutes = (departure.at - now) / 60_000
        return when {
            timeLeft && minutes < 1 -> context.getString(R.string.widget_soon)
            timeLeft && minutes < 60 -> context.getString(R.string.widget_minutes, minutes)
            else -> DateFormat.getTimeFormat(context).format(Date(departure.at))
        }
    }

    private fun stateColor(context: Context, departure: Departure): Int = ContextCompat.getColor(context, when (departure.state) {
        'l' -> R.color.widget_live
        'd' -> R.color.widget_late
        else -> R.color.widget_text
    })

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_REDRAW, AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> {
                val manager = AppWidgetManager.getInstance(context)
                onUpdate(context, manager, ids(context), HomeWidgetPlugin.getData(context))
            }
            else -> super.onReceive(context, intent)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val now = System.currentTimeMillis()
        appWidgetIds.forEach { widgetId -> render(context, appWidgetManager, widgetId, widgetData, now) }
        afterRender(context, widgetData, now)
    }

    /** Resized: the layout and the rows it holds may change (on every launcher, since Android 4.1) */
    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context), System.currentTimeMillis())
    }

    /** A widget removed: its stop and departures are forgotten */
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        HomeWidgetPlugin.getData(context).edit {
            for (id in appWidgetIds) {
                listOf("stop_id", "stop_name", "filter", "rows", "message", "updated").forEach { remove(key(id, it)) }
            }
        }
    }

    /** The last widget removed: nothing left to draw nor fetch */
    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        context.getSystemService(AlarmManager::class.java).cancel(redrawIntent(context))
        WidgetRefreshWorker.cancel(context)
    }

    private fun render(context: Context, appWidgetManager: AppWidgetManager, widgetId: Int, widgetData: SharedPreferences, now: Long) {
        val stopId = widgetData.getString(key(widgetId, "stop_id"), null)
        val views = if (stopId == null) {
            choose(context, widgetId)
        } else {
            val options = appWidgetManager.getAppWidgetOptions(widgetId)
            val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            // Portrait height, which phones use; unknown (0) on some old launchers: as placed at first
            val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
            val rows = upcoming(parse(widgetData.getString(key(widgetId, "rows"), null)), now)
            val message = widgetData.getString(key(widgetId, "message"), null) ?: context.getString(R.string.widget_no_departure)
            val stopName = widgetData.getString(key(widgetId, "stop_name"), null).orEmpty()
            val timeLeft = canShowTimeLeft(context)
            val small = width in 1 until SMALL_WIDTH
            (if (small) small(context, stopName, rows, message, now, timeLeft) else list(context, widgetData, widgetId, height, stopName, rows, message, now, timeLeft)).apply {
                setContentDescription(R.id.widget_root, context.getString(R.string.widget_departures_of, stopName))
                setOnClickPendingIntent(R.id.widget_root, open(context, "guillaumedamiens://stop?id=${Uri.encode(stopId)}"))
            }
        }
        appWidgetManager.updateAppWidget(widgetId, views)
    }

    /** No stop yet: tapping it opens the choice of its stop in the app */
    private fun choose(context: Context, widgetId: Int) = RemoteViews(context.packageName, R.layout.next_departures_choose).apply {
        setOnClickPendingIntent(R.id.widget_root, open(context, "guillaumedamiens://widget?id=$widgetId"))
    }

    private fun list(
        context: Context, widgetData: SharedPreferences, widgetId: Int, height: Int, stopName: String, rows: List<Row>,
        message: String, now: Long, timeLeft: Boolean,
    ) = RemoteViews(context.packageName, R.layout.next_departures).apply {
        setTextViewText(R.id.tv_stop_name, stopName)
        setTextViewText(R.id.tv_updated, widgetData.getString(key(widgetId, "updated"), null).orEmpty())
        setOnClickPendingIntent(
            R.id.btn_refresh,
            HomeWidgetBackgroundIntent.getBroadcast(context, "guillaumedamiens://refreshdepartures".toUri()),
        )
        // The header takes about 52 dp, each row 30
        val fits = if (height <= 0) 3 else ((height - 52) / 30).coerceIn(1, 8)
        removeAllViews(R.id.rows)
        rows.take(fits).forEach { row ->
            val first = row.departures.first()
            val following = row.departures.getOrNull(1)
            addView(R.id.rows, RemoteViews(context.packageName, R.layout.next_departures_row).apply {
                setImageViewResource(R.id.iv_badge, badge(row.mode))
                setInt(R.id.iv_badge, "setColorFilter", row.background)
                setTextViewText(R.id.tv_line, row.line)
                setTextColor(R.id.tv_line, row.foreground)
                setTextViewText(R.id.tv_destination, row.destination)
                setTextViewText(R.id.tv_time, label(context, first, now, timeLeft))
                setTextColor(R.id.tv_time, stateColor(context, first))
                setViewVisibility(R.id.tv_next, if (following == null) View.GONE else View.VISIBLE)
                if (following != null) {
                    setTextViewText(R.id.tv_next, label(context, following, now, timeLeft))
                }
            })
        }
        setViewVisibility(R.id.rows, if (rows.isEmpty()) View.GONE else View.VISIBLE)
        setViewVisibility(R.id.tv_status_message, if (rows.isEmpty()) View.VISIBLE else View.GONE)
        setTextViewText(R.id.tv_status_message, message)
    }

    private fun small(context: Context, stopName: String, rows: List<Row>, message: String, now: Long, timeLeft: Boolean) =
        RemoteViews(context.packageName, R.layout.next_departures_small).apply {
            setTextViewText(R.id.tv_stop_name, stopName)
            val row = rows.firstOrNull()
            setViewVisibility(R.id.departure, if (row == null) View.GONE else View.VISIBLE)
            setViewVisibility(R.id.tv_next, if (row?.departures?.getOrNull(1) == null) View.GONE else View.VISIBLE)
            setViewVisibility(R.id.tv_status_message, if (row == null) View.VISIBLE else View.GONE)
            setTextViewText(R.id.tv_status_message, message)
            if (row != null) {
                val first = row.departures.first()
                setImageViewResource(R.id.iv_badge, badge(row.mode))
                setInt(R.id.iv_badge, "setColorFilter", row.background)
                setTextViewText(R.id.tv_line, row.line)
                setTextColor(R.id.tv_line, row.foreground)
                setTextViewText(R.id.tv_time, label(context, first, now, timeLeft))
                setTextColor(R.id.tv_time, stateColor(context, first))
                row.departures.getOrNull(1)?.let { following ->
                    setTextViewText(R.id.tv_next, context.getString(R.string.widget_then, label(context, following, now, timeLeft)))
                }
            }
        }

    /** Opens the app at [uri] (its stop, or the choice of its stop) */
    private fun open(context: Context, uri: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri.toUri())

    /** After drawing: the next redraw, the periodic fetch, and new departures once the screen is back on if stale */
    private fun afterRender(context: Context, widgetData: SharedPreferences, now: Long) {
        val configured = ids(context).filter { widgetData.contains(key(it, "stop_id")) }
        if (configured.isEmpty()) {
            WidgetRefreshWorker.cancel(context)
            return
        }
        WidgetRefreshWorker.schedule(context)
        scheduleRedraw(context, configured.flatMap { parse(widgetData.getString(key(it, "rows"), null)) }, now)

        val fetchedAt = widgetData.getString(FETCHED_AT, null)?.toLongOrNull() ?: 0
        val askedAt = widgetData.getString(ASKED_AT, null)?.toLongOrNull() ?: 0
        val interactive = context.getSystemService(PowerManager::class.java).isInteractive
        if (interactive && now - fetchedAt > STALE_MS && now - askedAt > STALE_MS / 2) {
            requestRefresh(context)
        }
    }

    /**
     * The next time a widget changes by itself: a departure leaves, comes within the hour, or its minutes left change
     * (when shown). An alarm that doesn't wake the device: while the screen is off it waits, and comes as it is on
     * again, so the widget is up to date when seen. Exact when Android allows it, so that the minutes are on time.
     */
    private fun scheduleRedraw(context: Context, rows: List<Row>, now: Long) {
        val timeLeft = canShowTimeLeft(context)
        val next = rows.flatMap { it.departures }.filter { it.at > now }.flatMap { departure ->
            val left = departure.at - now
            buildList {
                add(departure.at + 1000)
                if (timeLeft) {
                    if (left >= 3_600_000) add(departure.at - 3_600_000 + 500)
                    // The minutes shown go down when the time left goes under a whole number of minutes
                    else add(departure.at - (left / 60_000) * 60_000 + 500)
                }
            }
        }.filter { it > now }.minOrNull()
        val alarms = context.getSystemService(AlarmManager::class.java)
        val intent = redrawIntent(context)
        when {
            next == null -> alarms.cancel(intent)
            timeLeft -> alarms.setExact(AlarmManager.RTC, next, intent)
            else -> alarms.set(AlarmManager.RTC, next, intent)
        }
    }

    private fun redrawIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, NextDepartures::class.java).setAction(ACTION_REDRAW),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}
