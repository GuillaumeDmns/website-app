package com.guillaumedamiens.website_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider
import androidx.core.net.toUri

class NextDepartures : HomeWidgetProvider() {

    companion object {
        // Row IDs for departure slots (1 to 4)
        private val ROW_IDS = intArrayOf(
            R.id.departure_row_1,
            R.id.departure_row_2,
            R.id.departure_row_3,
            R.id.departure_row_4
        )
        private val TIME_IDS = intArrayOf(
            R.id.tv_time_1,
            R.id.tv_time_2,
            R.id.tv_time_3,
            R.id.tv_time_4
        )
        private val DEST_IDS = intArrayOf(
            R.id.tv_dest_1,
            R.id.tv_dest_2,
            R.id.tv_dest_3,
            R.id.tv_dest_4
        )
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.next_departures).apply {
                val stationName = widgetData.getString("stop_name", "Aucune station")
                val departuresJson = widgetData.getString("departures_json", null)
                val statusMessage = widgetData.getString("departures_list", "Appuyez pour charger")
                val lastUpdated = widgetData.getString("last_updated", null)

                // Set station name
                setTextViewText(R.id.tv_stop_name, stationName)

                // Set last updated
                if (lastUpdated != null) {
                    setTextViewText(R.id.tv_last_updated, "Mis à jour : $lastUpdated")
                } else {
                    setTextViewText(R.id.tv_last_updated, "")
                }

                // Parse structured departures if available
                if (departuresJson != null) {
                    val lines = departuresJson.split("||")
                    val departures = lines.mapNotNull { line ->
                        val parts = line.split("|")
                        if (parts.size >= 2) Pair(parts[0], parts[1]) else null
                    }

                    if (departures.isNotEmpty()) {
                        // Hide status message, show rows
                        setViewVisibility(R.id.tv_status_message, View.GONE)

                        for (i in 0 until 4) {
                            if (i < departures.size) {
                                setViewVisibility(ROW_IDS[i], View.VISIBLE)
                                setTextViewText(TIME_IDS[i], departures[i].first)
                                setTextViewText(DEST_IDS[i], departures[i].second)
                            } else {
                                setViewVisibility(ROW_IDS[i], View.GONE)
                            }
                        }
                    } else {
                        showStatusMessage(this, statusMessage ?: "Aucun départ")
                    }
                } else {
                    showStatusMessage(this, statusMessage ?: "Appuyez pour charger")
                }

                // PendingIntent.FLAG_IMMUTABLE est OBLIGATOIRE sur Android 12+ sinon ça crash
                val backgroundIntent = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    "guillaumedamiens://refreshdepartures".toUri()
                )
                setOnClickPendingIntent(R.id.btn_refresh, backgroundIntent)

                // Open app intent
                val openAppIntent = context.packageManager
                    .getLaunchIntentForPackage(context.packageName)
                if (openAppIntent != null) {
                    openAppIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    val openAppPendingIntent = PendingIntent.getActivity(
                        context,
                        0,
                        openAppIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    setOnClickPendingIntent(R.id.btn_open_app, openAppPendingIntent)
                }
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun showStatusMessage(views: RemoteViews, message: String) {
        views.setViewVisibility(R.id.tv_status_message, View.VISIBLE)
        views.setTextViewText(R.id.tv_status_message, message)
        for (rowId in ROW_IDS) {
            views.setViewVisibility(rowId, View.GONE)
        }
    }
}