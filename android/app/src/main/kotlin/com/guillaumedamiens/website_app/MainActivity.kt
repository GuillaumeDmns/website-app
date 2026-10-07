package com.guillaumedamiens.website_app

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.LocationSettingsRequest
import com.google.android.gms.location.Priority
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.guillaumedamiens.live_notification/bridge"
    private val NOTIFICATION_PERMISSION_REQUEST = 7541

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateJourney" -> {
                    val notification = LiveJourneyNotification.journey(
                        this,
                        title = call.argument<String>("title") ?: getString(R.string.journey_channel),
                        status = call.argument<String>("status") ?: "",
                        progress = call.argument<Int>("progress") ?: 0,
                        currentMode = call.argument<String>("currentMode") ?: "walk",
                        chipText = call.argument<String>("chipText") ?: "",
                        longInfo = call.argument<String>("longInfo") ?: "",
                        segments = call.argument<List<Map<String, Any>>>("segments") ?: emptyList(),
                    )
                    val locationGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    if (GoService.latest == null && locationGranted) {
                        // First update: the foreground service keeps GO running with the screen off (a location
                        // service can't start without the location permission)
                        GoService.start(this, notification)
                    } else {
                        GoService.latest = notification
                        getSystemService(NotificationManager::class.java)
                            .notify(LiveJourneyNotification.NOTIFICATION_ID, notification)
                    }
                    result.success(null)
                }
                "alert" -> {
                    LiveJourneyNotification.alert(
                        this,
                        title = call.argument<String>("title") ?: "",
                        body = call.argument<String>("body") ?: "",
                        urgent = call.argument<Boolean>("urgent") ?: false,
                    )
                    result.success(null)
                }
                "stopNotification" -> {
                    GoService.stop(this)
                    LiveJourneyNotification.cancelJourney(this)
                    result.success(null)
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
                    }
                    result.success(null)
                }
                "share" -> {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_SUBJECT, call.argument<String>("title"))
                        putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                    }
                    startActivity(Intent.createChooser(send, call.argument<String>("title")))
                    result.success(null)
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