import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    // The app's own native side: GO's notification, sharing, the display kept on, the widget's data
    AppBridge.register(with: flutterViewController.registrar(forPlugin: "AppBridge"))

    super.awakeFromNib()
  }
}
