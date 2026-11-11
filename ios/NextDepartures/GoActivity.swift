#if os(iOS)
import ActivityKit
import AppIntents
import Foundation

/// GO's Live Activity (lock screen and Dynamic Island, `GoLiveActivity.swift`): what Android's ongoing notification
/// shows (`LiveJourneyNotification.kt`), written by the app (`GoActivityController` in `AppBridge.swift`) from
/// `goLiveUpdate` (`lib/features/go/go_live.dart`).
@available(iOS 16.1, *)
struct GoActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// What to do now ("Marchez jusqu'à Châtelet")
    var title: String
    /// Where (the stop, the platform)
    var status: String
    /// The figure that counts ("3 min", "2 arrêts")
    var chip: String
    /// The arrival ("Arrivée 08:42")
    var info: String
    /// Icon of the step in progress: `metro`, `train`, `tram`, `bus`, `transfer` or `walk`
    var mode: String
    /// Seconds done along the segments
    var progress: Int
    var segments: [Segment]
  }

  /// A step of the journey in the progress bar
  public struct Segment: Codable, Hashable {
    var seconds: Int
    /// `#RRGGBB`: the line's color, grey for walks
    var color: String
  }
}

/// "Terminer" on the Live Activity: run by the system in the app's process (a `LiveActivityIntent`), even when the
/// app isn't running; the Live Activity goes at once and the app ends the session ([GoStop]).
@available(iOS 17.0, *)
struct GoStopIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Finish the journey"

  init() {}

  func perform() async throws -> some IntentResult {
    for activity in Activity<GoActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    await MainActor.run {
      GoStop.request()
    }
    return .result()
  }
}
#endif
