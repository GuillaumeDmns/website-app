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
 * Fetches the widgets' departures every 15 min (Android's shortest period), only while the screen is on: nobody sees
 * them otherwise, and the stop's departures count against the backend's PRIM quota. Scheduled while a widget has a
 * stop ([NextDepartures]).
 */
class WidgetRefreshWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {

    override fun doWork(): Result {
        if (applicationContext.getSystemService(PowerManager::class.java).isInteractive) {
            NextDepartures.requestRefresh(applicationContext)
        }
        return Result.success()
    }

    companion object {
        private const val NAME = "widget_refresh"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(NAME)
        }
    }
}
