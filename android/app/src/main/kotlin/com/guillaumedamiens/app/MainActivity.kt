package com.guillaumedamiens.app

import android.Manifest
import android.app.Activity
import android.app.LocaleManager
import android.app.Notification
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.LocaleList
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.LocationSettingsRequest
import com.google.android.gms.location.Priority
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import java.io.File
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.guillaumedamiens.live_notification/bridge"
    private val NOTIFICATION_PERMISSION_REQUEST = 7541

    /** The notification of a departure followed without a journey, posted again when the app is back on screen */
    private var followed: Notification? = null

    private var locationSettingsResult: MethodChannel.Result? = null

    private val locationSettingsLauncher: ActivityResultLauncher<IntentSenderRequest> =
        registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
            val pending = locationSettingsResult
            locationSettingsResult = null
            pending?.success(result.resultCode == Activity.RESULT_OK)
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LiveJourneyNotification.createChannels(this)
        WidgetBridge.register(flutterEngine, this, receivesLaunches = true)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, DeviceHeading.CHANNEL).setStreamHandler(DeviceHeading(this))

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        bridge = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateJourney" -> {
                    followed = null
                    val notification = LiveJourneyNotification.journey(
                        this,
                        title = call.argument<String>("title") ?: getString(R.string.journey_channel),
                        status = call.argument<String>("status") ?: "",
                        progress = call.argument<Int>("progress") ?: 0,
                        currentMode = call.argument<String>("currentMode") ?: "walk",
                        chipText = call.argument<String>("chipText") ?: "",
                        longInfo = call.argument<String>("longInfo") ?: "",
                        segments = call.argument<List<Map<String, Any>>>("segments") ?: emptyList(),
                        line = call.argument<Map<String, String>>("line"),
                        tone = call.argument<String>("tone") ?: "fine",
                    )
                    val locationGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    if (GoService.latest == null && locationGranted) {
                        // First update: the foreground service keeps GO running with the screen off (a location
                        // service can't start without the location permission)
                        GoService.start(this, notification)
                    } else {
                        GoService.latest = notification
                        // Swiped away: not back before the app is (onResume)
                        if (!LiveJourneyNotification.dismissedByUser) {
                            getSystemService(NotificationManager::class.java)
                                .notify(LiveJourneyNotification.NOTIFICATION_ID, notification)
                        }
                    }
                    result.success(null)
                }
                "followDeparture" -> {
                    val notification = LiveJourneyNotification.departure(
                        this,
                        title = call.argument<String>("title") ?: "",
                        status = call.argument<String>("status") ?: "",
                        departureAt = call.argument<Number>("departureAt")?.toLong() ?: System.currentTimeMillis(),
                        currentMode = call.argument<String>("currentMode") ?: "bus",
                        cancelled = call.argument<Boolean>("cancelled") == true,
                        line = call.argument<Map<String, String>>("line"),
                        tone = call.argument<String>("tone") ?: "fine",
                    )
                    // No service: the system counts the time left and takes the notification away by itself
                    GoService.stop(this)
                    followed = notification
                    if (!LiveJourneyNotification.dismissedByUser) {
                        getSystemService(NotificationManager::class.java)
                            .notify(LiveJourneyNotification.NOTIFICATION_ID, notification)
                    }
                    result.success(null)
                }
                "alertJourney" -> {
                    LiveJourneyNotification.showAlert(this, call.argument<String>("title") ?: "", call.argument<String>("body"))
                    result.success(null)
                }
                "stopNotification" -> {
                    GoService.stop(this)
                    followed = null
                    LiveJourneyNotification.cancelJourney(this)
                    result.success(null)
                }
                "takeStopRequest" -> {
                    result.success(GoStopReceiver.take(this))
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
                    }
                    result.success(null)
                }
                "notificationStatus" -> {
                    // "off": no notification at all; "liveOff": allowed, but not as a Live Update (Android 16, a
                    // setting per app); "ok"
                    val manager = getSystemService(NotificationManager::class.java)
                    result.success(when {
                        !NotificationManagerCompat.from(this).areNotificationsEnabled() -> "off"
                        Build.VERSION.SDK_INT >= 36 && !manager.canPostPromotedNotifications() -> "liveOff"
                        else -> "ok"
                    })
                }
                "openNotificationSettings" -> {
                    val live = call.argument<Boolean>("live") == true && Build.VERSION.SDK_INT >= 36
                    val settings = Intent(if (live) Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS else Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    try {
                        startActivity(settings)
                    } catch (e: Exception) {
                        // No such page on this device: the app's notification settings
                        try {
                            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        } catch (e: Exception) {
                            // Nothing to open
                        }
                    }
                    result.success(null)
                }
                "share" -> {
                    val title = call.argument<String>("title")
                    val text = call.argument<String>("text") ?: ""
                    val fileName = call.argument<String>("fileName")
                    val send = Intent(Intent.ACTION_SEND).apply {
                        putExtra(Intent.EXTRA_SUBJECT, title)
                        if (fileName == null) {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        } else {
                            // An export, as a file: a text over 1 MB in the intent makes the system refuse it
                            // (TransactionTooLargeException), and the clipboard as well
                            val dir = File(cacheDir, "exports").apply { mkdirs() }
                            val file = File(dir, File(fileName).name)
                            file.writeText(text)
                            val uri = FileProvider.getUriForFile(this@MainActivity, "$packageName.exports", file)
                            type = if (fileName.endsWith(".json")) "application/json" else "text/plain"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            clipData = ClipData.newRawUri(fileName, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                    }
                    startActivity(Intent.createChooser(send, title))
                    result.success(null)
                }
                "openStore" -> {
                    // The app's page in the store (a required update), its web page without a store app
                    val page = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName"))
                    try {
                        startActivity(page)
                    } catch (e: ActivityNotFoundException) {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$packageName")))
                        } catch (e: ActivityNotFoundException) {
                            // No browser either
                        }
                    }
                    result.success(null)
                }
                "appLanguage" -> {
                    // Android 13+: the system keeps the app's language (its page in the settings lists those of
                    // res/xml/locales_config.xml), and the choice made in the app is given to it. True when it does
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        call.argument<String>("language")?.let {
                            getSystemService(LocaleManager::class.java).applicationLocales = LocaleList.forLanguageTags(it)
                        }
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "keepScreenOn" -> {
                    // GO mode option: the screen stays on while the journey is followed
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "requestLocationService" -> {
                    requestLocationService(result)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Opened from a home screen widget: its stop
        WidgetBridge.launched(intent)
    }

    /** Back on screen: GO's notification, if the user had swiped it away, is posted again with the journey's progress */
    override fun onResume() {
        super.onResume()
        if (LiveJourneyNotification.dismissedByUser) {
            LiveJourneyNotification.dismissedByUser = false
            (GoService.latest ?: followed)?.let {
                getSystemService(NotificationManager::class.java).notify(LiveJourneyNotification.NOTIFICATION_ID, it)
            }
        }
    }

    /** A widget tapped while the app's task is there (singleTop): its stop, once the Dart side takes it */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        WidgetBridge.launched(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridge = null
        WidgetBridge.unregister()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    companion object {
        /** The channel to the Dart side while its engine runs: GO's notification's "Terminer" goes through it */
        @Volatile
        var bridge: MethodChannel? = null
    }

    private fun requestLocationService(result: MethodChannel.Result) {
        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY, 10000
        ).build()

        val settingsRequest = LocationSettingsRequest.Builder()
            .addLocationRequest(locationRequest)
            .setAlwaysShow(true)
            .build()

        LocationServices.getSettingsClient(this)
            .checkLocationSettings(settingsRequest)
            .addOnSuccessListener {
                result.success(true)
            }
            .addOnFailureListener { exception ->
                if (exception is ResolvableApiException) {
                    try {
                        locationSettingsResult = result
                        val intentSenderRequest = IntentSenderRequest.Builder(
                            exception.resolution.intentSender
                        ).build()
                        locationSettingsLauncher.launch(intentSenderRequest)
                    } catch (e: IntentSender.SendIntentException) {
                        locationSettingsResult = null
                        result.success(false)
                    }
                } else {
                    result.success(false)
                }
            }
    }
}