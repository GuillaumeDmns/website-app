#if os(iOS)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// GO's Live Activity, Citymapper-like: what to do now, the figure that counts, where, and the journey's progress in
/// the colors of its lines; "Terminer" ends the session (iOS 17). The app updates it as GO goes (`AppBridge.swift`).
struct GoLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: GoActivityAttributes.self) { context in
      GoLockScreenView(state: context.state)
        .padding(16)
        .activitySystemActionForegroundColor(GoColors.brand)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          ModeIcon(mode: context.state.mode, size: 36)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.chip)
            .font(.title3.weight(.semibold).monospacedDigit())
            .foregroundColor(GoColors.brand)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.title)
            .font(.headline)
            .lineLimit(2)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 8) {
            if !context.state.status.isEmpty {
              Text(context.state.status).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
            }
            SegmentsBar(state: context.state)
            HStack {
              Text(context.state.info).font(.caption).foregroundColor(.secondary)
              Spacer()
              StopButton()
            }
          }
        }
      } compactLeading: {
        Image(systemName: ModeIcon.symbol(context.state.mode))
          .foregroundColor(GoColors.brand)
      } compactTrailing: {
        Text(context.state.chip)
          .font(.caption.weight(.semibold).monospacedDigit())
          .foregroundColor(GoColors.brand)
          .lineLimit(1)
      } minimal: {
        Image(systemName: ModeIcon.symbol(context.state.mode))
          .foregroundColor(GoColors.brand)
      }
      .keylineTint(GoColors.brand)
    }
  }
}

enum GoColors {
  /// The app's green (`AppTheme.brand`)
  static let brand = Color(hex: "0A8F4E")!
}

/// The lock screen's banner
struct GoLockScreenView: View {
  let state: GoActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        ModeIcon(mode: state.mode, size: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(state.title)
            .font(.headline)
            .lineLimit(2)
          if !state.status.isEmpty {
            Text(state.status)
              .font(.subheadline)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 4)
        Text(state.chip)
          .font(.title3.weight(.semibold).monospacedDigit())
          .foregroundColor(GoColors.brand)
          .lineLimit(1)
      }
      SegmentsBar(state: state)
      HStack {
        Text(state.info).font(.caption).foregroundColor(.secondary)
        Spacer()
        StopButton()
      }
    }
  }
}

/// The step in progress, white on the app's green
struct ModeIcon: View {
  let mode: String
  let size: CGFloat

  static func symbol(_ mode: String) -> String {
    switch mode {
    case "metro": return "tram.fill.tunnel"
    case "train": return "train.side.front.car"
    case "tram": return "tram.fill"
    case "bus": return "bus.fill"
    case "transfer": return "arrow.triangle.swap"
    default: return "figure.walk"
    }
  }

  var body: some View {
    Image(systemName: Self.symbol(mode))
      .font(.system(size: size * 0.5, weight: .semibold))
      .foregroundColor(.white)
      .frame(width: size, height: size)
      .background(Circle().fill(GoColors.brand))
  }
}

/// The journey's steps in their lines' colors (walks grey), filled up to where the user is
struct SegmentsBar: View {
  let state: GoActivityAttributes.ContentState

  private struct Part: Identifiable {
    let id: Int
    let color: Color
    let share: CGFloat
    let done: CGFloat
  }

  private var parts: [Part] {
    let total = max(1, state.segments.reduce(0) { $0 + max($1.seconds, 0) })
    var start = 0
    return state.segments.enumerated().map { index, segment in
      let seconds = max(segment.seconds, 0)
      let done = seconds == 0 ? (state.progress >= start ? 1 : 0) : Double(state.progress - start) / Double(seconds)
      defer { start += seconds }
      return Part(
        id: index, color: Color(hex: segment.color) ?? .gray, share: CGFloat(seconds) / CGFloat(total),
        done: CGFloat(min(1, max(0, done))))
    }
  }

  var body: some View {
    GeometryReader { geometry in
      let parts = self.parts
      let gap: CGFloat = 2
      let width = max(0, geometry.size.width - gap * CGFloat(max(parts.count - 1, 0)))
      HStack(spacing: gap) {
        ForEach(parts) { part in
          ZStack(alignment: .leading) {
            Capsule().fill(part.color.opacity(0.3))
            Capsule().fill(part.color).frame(width: width * part.share * part.done)
          }
          .frame(width: width * part.share)
        }
      }
    }
    .frame(height: 6)
  }
}

/// "Terminer" (iOS 17: the button runs `GoStopIntent` in the app)
struct StopButton: View {
  var body: some View {
    if #available(iOS 17.0, *) {
      Button(intent: GoStopIntent()) {
        Text(AppTexts.finish)
          .font(.caption.weight(.semibold))
      }
      .buttonStyle(.bordered)
      .tint(GoColors.brand)
    }
  }
}
#endif
