import Cocoa
import FlutterMacOS
import IOKit.pwr_mgt
import UserNotifications
import WidgetKit

/// The app's native side on macOS, on the same channel as Android's `MainActivity.kt` and iOS's `AppBridge.swift`:
/// GO's journey as a quiet notification replaced in place (with "Terminer"), the share picker, the display kept on, and
/// the widget's data (home_widget has no macOS side: `home_widget_sync.dart` sends it here).
final class AppBridge: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
  static let channelName = "com.guillaumedamiens.live_notification/bridge"
  private static let notificationId = "go_journey"
  private static let categoryId = "GO_JOURNEY"
  private static let finishActionId = "GO_FINISH"

  private let channel: FlutterMethodChannel
  private var stopObserver: NSObjectProtocol?
  private var displayAssertion: IOPMAssertionID = 0
  private var shown: [String] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger)
    let bridge = AppBridge(channel: channel)
    registrar.addMethodCallDelegate(bridge, channel: channel)
    let center = UNUserNotificationCenter.current()
    center.delegate = bridge
    let finish = UNNotificationAction(identifier: finishActionId, title: AppTexts.finish, options: [])
    center.setNotificationCategories([
      UNNotificationCategory(identifier: categoryId, actions: [finish], intentIdentifiers: [], options: [])
    ])
  }

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    // "Terminer" in the notification: the Dart side ends the session, or at its next start if it doesn't answer yet
    stopObserver = NotificationCenter.default.addObserver(forName: GoStop.requested, object: nil, queue: .main) {
      [weak self] _ in
      self?.channel.invokeMethod("stopRequested", arguments: nil) { reply in
        if let object = reply as? NSObject, object === FlutterMethodNotImplemented {
          return
        }
        if reply is FlutterError {
          return
        }
        _ = GoStop.take()
      }
    }
  }

  deinit {
    if let stopObserver {
      NotificationCenter.default.removeObserver(stopObserver)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "updateJourney":
      showJourney(arguments)
      result(nil)
    case "stopNotification":
      removeJourney()
      result(nil)
    case "takeStopRequest":
      result(GoStop.take())
    case "requestNotificationPermission":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
      result(nil)
    case "share":
      share(text: arguments["text"] as? String ?? "")
      result(nil)
    case "keepScreenOn":
      keepDisplayOn(arguments["on"] as? Bool ?? false)
      result(nil)
    case "saveWidget":
      saveWidget(arguments)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: GO's notification

  /// What to do now, where and the figure that counts; posted again only when they change, without a banner nor a
  /// sound (passive: in the notification center)
  private func showJourney(_ arguments: [String: Any]) {
    let title = arguments["title"] as? String ?? AppTexts.journey
    let body = [arguments["status"] as? String ?? "", arguments["chipText"] as? String ?? ""]
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
    let info = arguments["longInfo"] as? String ?? ""
    if shown == [title, body, info] {
      return
    }
    shown = [title, body, info]
    let content = UNMutableNotificationContent()
    content.title = title
    content.subtitle = info
    content.body = body
    content.categoryIdentifier = Self.categoryId
    content.threadIdentifier = Self.notificationId
    if #available(macOS 12.0, *) {
      content.interruptionLevel = .passive
    }
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: nil))
  }

  private func removeJourney() {
    shown = []
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
    center.removeDeliveredNotifications(withIdentifiers: [Self.notificationId])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.actionIdentifier == Self.finishActionId {
      removeJourney()
      GoStop.request()
    }
    completionHandler()
  }

  /// The app in front: in the notification center only
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.list])
  }

  // MARK: Sharing, display

  private func share(text: String) {
    guard let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else {
      return
    }
    let picker = NSSharingServicePicker(items: [text])
    picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), of: view, preferredEdge: .minY)
  }

  private func keepDisplayOn(_ on: Bool) {
    if on && displayAssertion == 0 {
      var assertion: IOPMAssertionID = 0
      let created = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "GO" as CFString, &assertion)
      if created == kIOReturnSuccess {
        displayAssertion = assertion
      }
    } else if !on && displayAssertion != 0 {
      IOPMAssertionRelease(displayAssertion)
      displayAssertion = 0
    }
  }

  // MARK: Widget

  /// The keys home_widget writes on Android and iOS, into the App Group (a null value removes the key), then the
  /// widget is drawn again
  private func saveWidget(_ data: [String: Any]) {
    guard let defaults = AppGroup.defaults else {
      return
    }
    for (key, value) in data {
      if let text = value as? String {
        defaults.set(text, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
    }
    WidgetCenter.shared.reloadTimelines(ofKind: "NextDepartures")
  }
}
