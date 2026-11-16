package com.guillaumedamiens.app

import android.content.Context
import android.os.PowerManager
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Fetches the widgets' data every 15 min (Android's shortest period), only while the screen is on: nobody sees them
 * otherwise, and the stop's departures count against the backend's PRIM quota. Scheduled while a departures widget
 * has a stop ([NextDepartures]) or a "Mes lignes" widget is placed ([LinesTraffic]), each fetched only when placed.
 */
class WidgetRefreshWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {

    override fun doWork(): Result {
        if (applicationContext.getSystemService(PowerManager::class.java).isInteractive) {
            if (NextDepartures.hasStops(applicationContext)) {
                NextDepartures.requestRefresh(applicationContext)
            }
            if (LinesTraffic.ids(applicationContext).isNotEmpty()) {
                LinesTraffic.requestRefresh(applicationContext)
            }
        }
        return Result.success()
    }

    companion object {
        private const val NAME = "widget_refresh"

        /** Scheduled while a widget needs it, cancelled otherwise */
        fun update(context: Context) {
            if (NextDepartures.hasStops(context) || LinesTraffic.ids(context).isNotEmpty()) schedule(context) else cancel(context)
        }

        private fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        private fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(NAME)
        }
    }
}
