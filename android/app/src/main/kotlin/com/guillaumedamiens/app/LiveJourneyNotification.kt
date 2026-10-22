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
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.core.graphics.toColorInt

/**
 * GO mode notifications: the ongoing journey progress (Live Update on Android 16, a progress bar before) and the
 * alerts. Through NotificationCompat, from Android 7: channels from Android 8, the priority and vibration of each
 * notification before.
 */
object LiveJourneyNotification {
    const val NOTIFICATION_ID = 75415

    /** Alerts stack (design 2k2): each its own notification, ids from here, reused after [ALERT_SLOTS] */
    private const val ALERT_ID = 75416
    private const val ALERT_SLOTS = 12
    private const val SUMMARY_ID = 75400
    private const val ALERT_GROUP = "com.guillaumedamiens.app.GO_ALERTS"
    private var nextAlert = 0

    /** How long an alert stays in the shade: the journey's moments, not the day's */
    private const val ALERT_TIMEOUT = 30 * 60 * 1000L
    private const val JOURNEY_CHANNEL_ID = "live_journey_channel"
    private const val ALERT_CHANNEL_ID = "go_alerts"

    /** Alerts felt apart (each channel has its vibration: Android takes the channel's, not the notification's) */
    private const val PREPARE_CHANNEL_ID = "go_alerts_prepare"
    private const val ALIGHT_CHANNEL_ID = "go_alerts_alight"
    private const val PLATFORM_CHANNEL_ID = "go_alerts_platform"
    private val PREPARE_PATTERN = longArrayOf(0, 120, 100, 120)
    private val ALIGHT_PATTERN = longArrayOf(0, 500, 200, 500, 200, 500)
    private val PLATFORM_PATTERN = longArrayOf(0, 80)
    private val ALERT_PATTERN = longArrayOf(0, 400, 200, 400)

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
        fun alertChannel(id: String, name: Int, description: Int, pattern: LongArray) =
            NotificationChannel(id, context.getString(name), NotificationManager.IMPORTANCE_HIGH).apply {
                this.description = context.getString(description)
                enableVibration(true)
                vibrationPattern = pattern
            }
        manager.createNotificationChannel(alertChannel(ALERT_CHANNEL_ID, R.string.alert_channel, R.string.alert_channel_description, ALERT_PATTERN))
        manager.createNotificationChannel(
            alertChannel(PREPARE_CHANNEL_ID, R.string.prepare_channel, R.string.prepare_channel_description, PREPARE_PATTERN)
        )
        manager.createNotificationChannel(
            alertChannel(ALIGHT_CHANNEL_ID, R.string.alight_channel, R.string.alight_channel_description, ALIGHT_PATTERN)
        )
        manager.createNotificationChannel(
            alertChannel(PLATFORM_CHANNEL_ID, R.string.platform_channel, R.string.platform_channel_description, PLATFORM_PATTERN)
        )
    }

    private fun brand(context: Context) = ContextCompat.getColor(context, R.color.widget_brand)

    fun placeholder(context: Context): Notification =
        NotificationCompat.Builder(context, JOURNEY_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_walk)
            .setColor(brand(context))
            .setPriority(NotificationCompat.PRIORITY_LOW)
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
            .setSmallIcon(R.drawable.ic_near_me)
            .setColor(brand(context))
            .setContentTitle(title)
            .setContentText(status)
            // Before Android 8 (no channels): quiet, but on the lock screen like the alerts
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setShowWhen(false)
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

    /**
     * An alert of GO (design 2k2): a title that says what to do, the detail under it (whole when expanded), on the lock
     * screen. Each alert is its own notification, grouped, so that the last ones stay in the shade in order.
     *
     * @param kind how it is felt: `prepare` (two short), `alight` (long, repeated), `platform` (one short), else the usual
     */
    fun alert(context: Context, title: String, body: String, urgent: Boolean, kind: String) {
        val (channel, pattern) = when (kind) {
            "prepare" -> PREPARE_CHANNEL_ID to PREPARE_PATTERN
            "alight" -> ALIGHT_CHANNEL_ID to ALIGHT_PATTERN
            "platform" -> PLATFORM_CHANNEL_ID to PLATFORM_PATTERN
            else -> ALERT_CHANNEL_ID to ALERT_PATTERN
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        val notification = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_near_me)
            .setColor(brand(context))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(if (urgent) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            // Not DEFAULT_ALL: before Android 8 its default vibration would replace the alert's own pattern
            .setDefaults(NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_LIGHTS)
            .setVibrate(pattern)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setGroup(ALERT_GROUP)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
            .setAutoCancel(true)
            .setTimeoutAfter(ALERT_TIMEOUT)
            .setContentIntent(openApp(context))
            .build()
        manager.notify(ALERT_ID + nextAlert, notification)
        nextAlert = (nextAlert + 1) % ALERT_SLOTS

        // The group's summary (Android 7 and later bundle them under it), silent
        val summary = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_near_me)
            .setColor(brand(context))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.InboxStyle().addLine(title).setSummaryText(context.getString(R.string.alert_channel)))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setGroup(ALERT_GROUP)
            .setGroupSummary(true)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setTimeoutAfter(ALERT_TIMEOUT)
            .setContentIntent(openApp(context))
            .build()
        manager.notify(SUMMARY_ID, summary)
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
