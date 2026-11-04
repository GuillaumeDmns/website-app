import ActivityKit
import Flutter
import UIKit

/// The app's native side on iOS, on the same channels as Android's `MainActivity.kt` (`LiveJourney`, `shareLink`,
/// `exportText` on the Dart side): GO's Live Activity instead of Android's ongoing notification, the share sheet, the
/// screen kept on, and the compass (`DeviceHeading.swift`).
final class AppBridge: NSObject, FlutterPlugin {
  static let channelName = "com.guillaumedamiens.live_notification/bridge"

  private let channel: FlutterMethodChannel
  private var stopObserver: NSObjectProtocol?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let bridge = AppBridge(channel: channel)
    registrar.addMethodCallDelegate(bridge, channel: channel)
    FlutterEventChannel(name: DeviceHeading.channelName, binaryMessenger: registrar.messenger())
      .setStreamHandler(DeviceHeading())
  }

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    // "Terminer" on the Live Activity, run in this process: the Dart side ends the session; the request stays for its
    // next start if it doesn't answer yet (the app launched in the background for it)
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
      if #available(iOS 16.2, *) {
        GoActivityController.update(GoActivityController.state(from: arguments))
      }
      result(nil)
    case "stopNotification":
      if #available(iOS 16.2, *) {
        GoActivityController.end()
      }
      result(nil)
    case "takeStopRequest":
      result(GoStop.take())
    case "requestNotificationPermission":
      // A Live Activity needs no permission (the user can turn them off in the settings)
      result(nil)
    case "share":
      share(text: arguments["text"] as? String ?? "")
      result(nil)
    case "keepScreenOn":
      UIApplication.shared.isIdleTimerDisabled = arguments["on"] as? Bool ?? false
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func share(text: String) {
    guard let presenter = Self.topController() else {
      return
    }
    let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    // iPad: a popover, from the bottom of the screen
    if let popover = controller.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    presenter.present(controller, animated: true)
  }

  private static func topController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

/// GO's Live Activity, started at the first update (the app is on screen then: GO starts there) and updated as GO goes
@available(iOS 16.2, *)
enum GoActivityController {
  private static var last: GoActivityAttributes.ContentState?
  private static var lastSent = Date.distantPast

  /// The progress alone moves every second: sent every 15 s at most, anything else at once
  private static let progressInterval: TimeInterval = 15

  static func state(from arguments: [String: Any]) -> GoActivityAttributes.ContentState {
    let segments = (arguments["segments"] as? [[String: Any]] ?? []).map { segment in
      GoActivityAttributes.Segment(
        seconds: (segment["length"] as? NSNumber)?.intValue ?? 0,
        color: segment["color"] as? String ?? "#9E9E9E")
    }
    return GoActivityAttributes.ContentState(
      title: arguments["title"] as? String ?? AppTexts.journey,
      status: arguments["status"] as? String ?? "",
      chip: arguments["chipText"] as? String ?? "",
      info: arguments["longInfo"] as? String ?? "",
      mode: arguments["currentMode"] as? String ?? "walk",
      progress: (arguments["progress"] as? NSNumber)?.intValue ?? 0,
      segments: segments)
  }

  private static var current: Activity<GoActivityAttributes>? {
    Activity<GoActivityAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale }
  }

  static func update(_ state: GoActivityAttributes.ContentState) {
    if state == last {
      return
    }
    if var previous = last {
      previous.progress = state.progress
      if previous == state && Date().timeIntervalSince(lastSent) < progressInterval {
        return
      }
    }
    last = state
    lastSent = Date()
    // Shown as outdated when the app stops updating it (killed)
    let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(20 * 60))
    if let activity = current {
      Task {
        await activity.update(content)
      }
    } else if ActivityAuthorizationInfo().areActivitiesEnabled {
      do {
        _ = try Activity.request(attributes: GoActivityAttributes(), content: content, pushType: nil)
      } catch {
        // In the background, or turned off: tried again at the next update
        NSLog("GO Live Activity not started: \(error)")
        last = nil
      }
    }
  }

  static func end() {
    last = nil
    for activity in Activity<GoActivityAttributes>.activities {
      Task {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
  }
}
