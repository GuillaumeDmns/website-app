import Flutter
import UIKit
import home_widget

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // The app's own native side: GO's Live Activity, sharing, the screen kept on, the compass, the widget's data
    let registrar: FlutterPluginRegistrar? = self.registrar(forPlugin: "AppBridge")
    if let registrar {
      AppBridge.register(with: registrar)
    }
    // The widget's refresh button runs Dart in a background engine, which needs the plugins too
    if #available(iOS 17, *) {
      HomeWidgetBackgroundWorker.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
