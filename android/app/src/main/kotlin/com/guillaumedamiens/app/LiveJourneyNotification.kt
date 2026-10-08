package com.guillaumedamiens.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.core.graphics.toColorInt

/** GO mode notifications: the ongoing journey progress (Live Update on Android 16) and the alerts. */
object LiveJourneyNotification {
    const val NOTIFICATION_ID = 75415
    private const val ALERT_ID = 75416
    private const val JOURNEY_CHANNEL_ID = "live_journey_channel"
    private const val ALERT_CHANNEL_ID = "go_alerts"

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(JOURNEY_CHANNEL_ID, context.getString(R.string.journey_channel), NotificationManager.IMPORTANCE_LOW).apply {
                description = context.getString(R.string.journey_channel_description)
                setShowBadge(false)
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(ALERT_CHANNEL_ID, context.getString(R.string.alert_channel), NotificationManager.IMPORTANCE_HIGH).apply {
                description = context.getString(R.string.alert_channel_description)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 400, 200, 400)
            }
        )
    }

    fun placeholder(context: Context): Notification =
        NotificationCompat.Builder(context, JOURNEY_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_walk)
            .setContentTitle(context.getString(R.string.journey_channel))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openApp(context))
            .build()

    /**
     * @param segments  one per step: `length` (seconds) and `color` (`#RRGGBB`)
     * @param progress  seconds done along the journey
     */
    fun journey(
        context: Context,
        title: String,
        status: String,
        progress: Int,
        currentMode: String,
        chipText: String,
        longInfo: String,
        segments: List<Map<String, Any>>,
    ): Notification {
        val builder = NotificationCompat.Builder(context, JOURNEY_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(status)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openApp(context))
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setRequestPromotedOngoing(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        if (longInfo.isNotEmpty()) {
            builder.setSubText(longInfo)
        }

        val trackerIcon = IconCompat.createWithResource(context, when (currentMode) {
            "train" -> R.drawable.ic_train
            "metro" -> R.drawable.ic_subway
            "tram" -> R.drawable.ic_tram
            "bus" -> R.drawable.ic_bus
            "transfer" -> R.drawable.ic_transfer_within_a_station
            else -> R.drawable.ic_walk
        })

        if (Build.VERSION.SDK_INT >= 36) {
            if (chipText.isNotEmpty()) {
                builder.setShortCriticalText(chipText)
            }
            val style = NotificationCompat.ProgressStyle()
            var total = 0
            segments.forEachIndexed { index, data ->
                val length = (data["length"] as? Int) ?: 0
                val segment = NotificationCompat.ProgressStyle.Segment(maxOf(length, 1))
                try {
                    segment.setColor(((data["color"] as? String) ?: "#808080").toColorInt())
                } catch (e: Exception) {
                    segment.setColor(Color.GRAY)
                }
                style.addProgressSegment(segment)
                total += maxOf(length, 1)
                if (index < segments.size - 1) {
                    val point = NotificationCompat.ProgressStyle.Point(total)
                    point.setColor(Color.BLACK)
                    style.addProgressPoint(point)
                }
            }
            style.setProgressTrackerIcon(trackerIcon)
            style.setProgress(progress.coerceIn(0, maxOf(total, 1)))
            builder.setStyle(style)
            builder.setSmallIcon(trackerIcon)
        } else {
            val total = segments.sumOf { maxOf((it["length"] as? Int) ?: 0, 1) }
            builder.setProgress(maxOf(total, 1), progress.coerceIn(0, maxOf(total, 1)), false)
            builder.setSmallIcon(trackerIcon)
        }
        return builder.build()
    }

    fun alert(context: Context, title: String, body: String, urgent: Boolean) {
        val notification = NotificationCompat.Builder(context, ALERT_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(if (urgent) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setVibrate(longArrayOf(0, 400, 200, 400))
            .setAutoCancel(true)
            .setTimeoutAfter(3 * 60 * 1000L)
            .setContentIntent(openApp(context))
            .build()
        context.getSystemService(NotificationManager::class.java).notify(ALERT_ID, notification)
    }

    /** The journey notification only: the last alert (e.g. "Vous êtes arrivé") stays until it times out */
    fun cancelJourney(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private fun openApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }
}
