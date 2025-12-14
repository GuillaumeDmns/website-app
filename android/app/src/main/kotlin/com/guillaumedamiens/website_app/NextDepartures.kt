package com.guillaumedamiens.website_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider
import androidx.core.net.toUri

class NextDepartures : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.next_departures).apply {
                val stationName = widgetData.getString("stop_name", "Aucune station")
                val departures = widgetData.getString("departures_list", "Pas de départs")

                setTextViewText(R.id.tv_stop_name, stationName)
                setTextViewText(R.id.tv_departures, departures)

                // PendingIntent.FLAG_IMMUTABLE est OBLIGATOIRE sur Android 12+ sinon ça crash
                val backgroundIntent = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    "guillaumedamiens://refreshdepartures".toUri()
                )

                setOnClickPendingIntent(R.id.btn_refresh, backgroundIntent)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}