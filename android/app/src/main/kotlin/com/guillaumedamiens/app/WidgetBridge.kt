package com.guillaumedamiens.app

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.net.toUri
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The widget's side of the app (`com.guillaumedamiens.app/widget`):
 * - for `WidgetSetupScreen`, whether it can show the time left before a departure (it is then drawn every minute,
 *   which needs Android's exact alarms) and the system's page allowing them ("Alarmes et rappels", Android 12+);
 * - what a tap on a widget opens ([launched], `takeLaunch`): kept until the Dart side takes it, at start-up or when
 *   told (`launched`). home_widget's own stream loses a tap that reaches [MainActivity] (`onNewIntent`, its task
 *   already there) before the Dart side listens to it.
 * Answered by [MainActivity] (launches too) and [WidgetConfigureActivity].
 */
object WidgetBridge {
    private const val CHANNEL = "com.guillaumedamiens.app/widget"

    /** The channel of [MainActivity]'s engine, while it runs */
    private var launches: MethodChannel? = null

    /** The last widget tap not taken yet (`guillaumedamiens://stop?id=…`) */
    @Volatile
    private var pending: String? = null

    fun register(engine: FlutterEngine, activity: Activity, receivesLaunches: Boolean = false) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        if (receivesLaunches) {
            launches = channel
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "canShowTimeLeft" -> result.success(NextDepartures.canShowTimeLeft(activity))
                "askTimeLeft" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        activity.startActivity(
                            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, "package:${activity.packageName}".toUri())
                        )
                    }
                    result.success(null)
                }
                // Only the app's own screen opens what a tap asked for, not the widget's setup
                "takeLaunch" -> if (receivesLaunches) {
                    result.success(pending)
                    pending = null
                } else {
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun unregister() {
        launches = null
    }

    /** [MainActivity] started or brought back by [intent]: a widget's tap is kept, and the Dart side told */
    fun launched(intent: Intent?) {
        if (intent?.action != HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION) {
            return
        }
        pending = intent.data?.toString() ?: return
        launches?.invokeMethod("launched", null)
    }
}
