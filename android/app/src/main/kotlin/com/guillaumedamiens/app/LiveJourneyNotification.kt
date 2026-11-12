package com.guillaumedamiens.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.core.graphics.toColorInt

/**
 * GO mode notification (design 3A): what to do now as its title, the figure that counts and where under it, the
 * arrival in its header, the line of the ride as a badge, the progress along the steps in their lines' colors (Live
 * Update on Android 16, a progress bar before), through NotificationCompat from Android 7. Quiet: only what must be
 * done at once while the app isn't on screen rings, in a notification of its own ([alert], design 3B).
 */
object LiveJourneyNotification {
    const val NOTIFICATION_ID = 75415
    private const val ALERT_ID = 75416
    private const val JOURNEY_CHANNEL_ID = "live_journey_channel"
    private const val ALERTS_CHANNEL_ID = "journey_alerts"

    /** An alert goes once its moment has passed */
    private const val ALERT_TIMEOUT_MS = 2 * 60_000L

    /** The alerts' channels of earlier versions, removed from the system settings */
    private val OLD_CHANNEL_IDS = listOf("go_alerts", "go_alerts_prepare", "go_alerts_alight", "go_alerts_platform")

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
            NotificationChannel(ALERTS_CHANNEL_ID, context.getString(R.string.journey_alerts_channel), NotificationManager.IMPORTANCE_HIGH).apply {
                description = context.getString(R.string.journey_alerts_channel_description)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 400, 200, 400, 200, 400)
                setShowBadge(false)
            }
        )
        OLD_CHANNEL_IDS.forEach(manager::deleteNotificationChannel)
    }

    private fun brand(context: Context) = ContextCompat.getColor(context, R.color.widget_brand)

    fun placeholder(context: Context): Notification =
        NotificationCompat.Builder(context, JOURNEY_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_walk)
            .setColor(brand(context))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentTitle(context.getString(R.string.journey_preparing))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openApp(context))
            .build()

    /**
     * @param segments  one per step: `length` (seconds) and `color` (`#RRGGBB`)
     * @param progress  seconds done along the journey
     * @param line      the ride's line (`name`, `color`, `textColor` as `#RRGGBB`, `mode`), shown as a badge
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
        line: Map<String, String>? = null,
    ): Notification {
        val builder = NotificationCompat.Builder(context, JOURNEY_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_near_me)
            .setColor(brand(context))
            .setContentTitle(title)
            .setContentText(status)
            // Before Android 8 (no channels): quiet, but on the lock screen
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setShowWhen(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openApp(context))
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setRequestPromotedOngoing(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(0, context.getString(R.string.journey_finish), finishJourney(context))

        if (longInfo.isNotEmpty()) {
            builder.setSubText(longInfo)
        }
        line?.let { badge(context, it) }?.let(builder::setLargeIcon)

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
            segments.forEach { data ->
                val length = (data["length"] as? Int) ?: 0
                val segment = NotificationCompat.ProgressStyle.Segment(maxOf(length, 1))
                try {
                    segment.setColor(((data["color"] as? String) ?: "#808080").toColorInt())
                } catch (e: Exception) {
                    segment.setColor(Color.GRAY)
                }
                style.addProgressSegment(segment)
                total += maxOf(length, 1)
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

    fun cancelJourney(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(NOTIFICATION_ID)
        manager.cancel(ALERT_ID)
    }

    /** What must be done now (get off, a platform changed, a vehicle missed): rings and vibrates, gone after a while */
    fun alert(context: Context, title: String, body: String?): Notification =
        NotificationCompat.Builder(context, ALERTS_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_near_me)
            .setColor(brand(context))
            .setContentTitle(title)
            .setContentText(body)
            // Before Android 8 (no channels): heads-up, sound and vibration
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setTimeoutAfter(ALERT_TIMEOUT_MS)
            .setContentIntent(openApp(context))
            .build()

    fun showAlert(context: Context, title: String, body: String?) {
        context.getSystemService(NotificationManager::class.java).notify(ALERT_ID, alert(context, title, body))
    }

    /** The line's badge in its IDFM shape (round metro, rounded train, square bus and tram), for the large icon */
    private fun badge(context: Context, line: Map<String, String>): Bitmap? {
        val name = line["name"]?.takeIf { it.isNotEmpty() } ?: return null
        val size = (48 * context.resources.displayMetrics.density).toInt()
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = runCatching { (line["color"] ?: "").toColorInt() }.getOrDefault(Color.DKGRAY)
        }
        val box = RectF(0f, 0f, size.toFloat(), size.toFloat())
        when (line["mode"]) {
            "metro" -> canvas.drawOval(box, fill)
            "bus", "noctilien", "tram" -> canvas.drawRoundRect(box, size * 0.12f, size * 0.12f, fill)
            else -> canvas.drawRoundRect(box, size * 0.25f, size * 0.25f, fill)
        }
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = runCatching { (line["textColor"] ?: "").toColorInt() }.getOrDefault(Color.WHITE)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            textAlign = Paint.Align.CENTER
            textSize = size * if (name.length > 3) 0.3f else 0.46f
        }
        canvas.drawText(name, size / 2f, size / 2f - (text.descent() + text.ascent()) / 2, text)
        return bitmap
    }

    /** "Terminer": GO stops without opening the app ([GoStopReceiver]) */
    private fun finishJourney(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        1,
        Intent(context, GoStopReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun openApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }
}
