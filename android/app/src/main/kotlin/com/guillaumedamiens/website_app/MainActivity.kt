package com.guillaumedamiens.website_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Color
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.graphics.toColorInt

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.guillaumedamiens.live_notification/bridge"
    private val NOTIFICATION_CHANNEL_ID = "live_journey_channel"
    private val NOTIFICATION_ID = 75415

    private val notificationManager: NotificationManager by lazy {
        getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateJourney" -> {
                    val title = call.argument<String>("title")?: "Journey"
                    val status = call.argument<String>("status")?: "In progress"
                    val currentProgress = call.argument<Int>("progress")?: 0
                    val currentMode = call.argument<String>("currentMode")?: "default"
                    val remainingTime = call.argument<String>("remainingTime")?: ""

                    val chipText = call.argument<String>("chipText")?: ""
                    val longInfo = call.argument<String>("longInfo")?: remainingTime

                    val segmentsData = call.argument<List<Map<String, Any>>>("segments")?: emptyList()

                    updateJourneyNotification(title, status, currentProgress, currentMode, chipText, longInfo, segmentsData)
                    result.success(null)
                }
                "stopNotification" -> {
                    notificationManager.cancel(NOTIFICATION_ID)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun updateJourneyNotification(
        title: String,
        status: String,
        currentProgress: Int,
        currentMode: String,
        chipText: String,
        longInfo: String,
        segmentsData: List<Map<String, Any>>
    ) {
        val pendingIntent = getPendingIntent()

        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(status)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setRequestPromotedOngoing(true)

        if (Build.VERSION.SDK_INT >= 36) {

            if (chipText.isNotEmpty()) {
                builder.setShortCriticalText(chipText)
            }

            if (longInfo.isNotEmpty()) {
                builder.setSubText(longInfo)
            }

            val style = NotificationCompat.ProgressStyle()

            var totalLength = 0

            segmentsData.forEachIndexed { index, data ->
                val length = (data["length"] as? Int)?: 0
                val colorString = (data["color"] as? String)?: "#808080"

                val segment = NotificationCompat.ProgressStyle.Segment(length)
                try {
                    segment.setColor(colorString.toColorInt())
                } catch (e: Exception) {
                    segment.setColor(Color.GRAY)
                }
                style.addProgressSegment(segment)
                totalLength += length

                if (index < segmentsData.size - 1) {
                    val transferPoint = NotificationCompat.ProgressStyle.Point(totalLength)
                    transferPoint.setColor(Color.BLACK)
                    style.addProgressPoint(transferPoint)
                }
            }

            val endPoint = NotificationCompat.ProgressStyle.Point(totalLength)
            endPoint.setColor(Color.BLACK)
            style.addProgressPoint(endPoint)

            val trackerIconRes = when (currentMode) {
                "RER", "Train Transilien", "TER" -> R.drawable.ic_train
                "Métro" -> R.drawable.ic_subway
                "Tramway" -> R.drawable.ic_tram
                "Bus", "public_transport", "vehicle" -> R.drawable.ic_bus
                "transfer" -> R.drawable.ic_transfer_within_a_station
                else -> R.drawable.ic_walk
            }
            val trackerIcon = IconCompat.createWithResource(this, trackerIconRes)
            style.setProgressTrackerIcon(trackerIcon)

            style.setProgress(currentProgress)
            builder.setStyle(style)
            builder.setSmallIcon(trackerIcon)
        } else {
            val totalDuration = segmentsData.sumOf { (it["length"] as? Int)?: 0 }
            val max = if (totalDuration > 0) totalDuration else 100

            if (longInfo.isNotEmpty()) {
                builder.setSubText(longInfo)
            }
            builder.setProgress(max, currentProgress, false)
        }

        notificationManager.notify(NOTIFICATION_ID, builder.build())
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Live Journey Updates",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows live journey progress"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun getPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        return PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }
}