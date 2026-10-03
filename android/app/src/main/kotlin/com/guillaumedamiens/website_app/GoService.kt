package com.guillaumedamiens.website_app

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service (type location) running while a journey is followed in GO mode: it keeps the process, and so
 * the Flutter engine and its position stream, alive with the screen off. It carries the live journey notification,
 * which the Dart side updates through [MainActivity].
 */
class GoService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = latest ?: LiveJourneyNotification.placeholder(this)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0
        try {
            ServiceCompat.startForeground(this, LiveJourneyNotification.NOTIFICATION_ID, notification, type)
        } catch (e: Exception) {
            // Location permission missing or app in the background: GO keeps working while the app is open
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    companion object {
        /** Last journey notification, shown when the service starts */
        @Volatile
        var latest: Notification? = null

        fun start(context: Context, notification: Notification) {
            latest = notification
            ContextCompat.startForegroundService(context, Intent(context, GoService::class.java))
        }

        fun stop(context: Context) {
            latest = null
            context.stopService(Intent(context, GoService::class.java))
        }
    }
}
