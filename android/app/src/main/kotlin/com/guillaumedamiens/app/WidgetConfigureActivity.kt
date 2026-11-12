package com.guillaumedamiens.app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Opened by the launcher as the widget is placed or reconfigured: the app's `WidgetSetupScreen` alone (home_widget
 * gives the widget's id to `main.dart`, and ends the setup when its stop is saved; leaving without one removes a
 * widget being placed). An activity of its own, in its own task, so that the app's own screen stays as it was.
 */
class WidgetConfigureActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        WidgetBridge.register(flutterEngine, this)
    }
}
