import Foundation

/// The App Group the app shares with its widget extension: `AppGroupId` of each Info.plist, from `APP_GROUP_ID` of the
/// flavor (`ios/Flutter/Flavor-*.xcconfig`, `macos/Runner/Configs/Flavor-*.xcconfig`). The widget's data lives there
/// (written by home_widget on iOS, by `AppBridge.swift` on macOS), and "Terminer" tapped while the app wasn't running.
enum AppGroup {
  static let id: String = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String ?? ""

  static var defaults: UserDefaults? {
    id.isEmpty ? nil : UserDefaults(suiteName: id)
  }
}

/// "Terminer" on GO's Live Activity (iOS) or notification (macOS): the session ends. The running app hears it at once
/// (`AppBridge`, which tells the Dart side, `stopRequested`); otherwise it is kept for the next start
/// (`takeStopRequest`), like Android's `GoStopReceiver`.
enum GoStop {
  static let requested = Notification.Name("com.guillaumedamiens.app.goStopRequested")
  private static let key = "go_stop_requested"

  static func request() {
    AppGroup.defaults?.set(true, forKey: key)
    NotificationCenter.default.post(name: requested, object: nil)
  }

  /// Whether "Terminer" was tapped and not handled yet, forgotten once asked
  static func take() -> Bool {
    guard let defaults = AppGroup.defaults, defaults.bool(forKey: key) else {
      return false
    }
    defaults.removeObject(forKey: key)
    return true
  }
}
