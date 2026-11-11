import SwiftUI
import WidgetKit

/// Home screen widget (design 2k1, like Android's `NextDepartures.kt`): the next departures of a stop, one row per
/// line and direction, written by the app (`lib/features/home_widget/home_widget_sync.dart`) into the App Group. The
/// app writes clock times; the widget moves to the following departure on its own as they pass (one timeline entry
/// per departure). Built for iOS (home screen, lock screen) and macOS.
struct NextDeparturesWidget: Widget {
  /// The kind the app names when it asks for a reload (`_appleName`)
  static let kind = "NextDepartures"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: DeparturesProvider()) { entry in
      NextDeparturesView(entry: entry)
    }
    .configurationDisplayName(AppTexts.widgetName)
    .description(AppTexts.widgetDescription)
    .supportedFamilies(Self.families)
  }

  private static var families: [WidgetFamily] {
    #if os(iOS)
    return [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline]
    #else
    return [.systemSmall, .systemMedium, .systemLarge]
    #endif
  }
}

/// One line and direction, as the app writes it, one per line of text: `line|background|text color|time|destination|
/// mode|state|next` (colors in hex without `#`, `state` = `live`, `late` or empty, `next` the following departure or
/// empty)
struct DepartureRow: Hashable {
  var line: String
  var background: String
  var foreground: String
  var time: String
  var destination: String
  var mode: String
  var state: String
  var next: String

  static func parse(_ data: String) -> [DepartureRow] {
    let rows = data.contains("\n") ? data.components(separatedBy: "\n") : data.components(separatedBy: "||")
    return rows.compactMap { row in
      let parts = row.components(separatedBy: "|")
      guard !row.trimmingCharacters(in: .whitespaces).isEmpty, parts.count >= 5 else {
        return nil
      }
      func part(_ index: Int) -> String { index < parts.count ? parts[index] : "" }
      return DepartureRow(
        line: parts[0], background: parts[1], foreground: parts[2], time: parts[3], destination: parts[4],
        mode: part(5), state: part(6), next: part(7))
    }
  }
}

/// What the app last wrote
struct StoredDepartures {
  var stopName: String?
  var rows: [DepartureRow]
  /// Why nothing is shown, in the app's language
  var message: String?
  /// "Mis à jour : 08:05", in the app's language
  var updated: String?
  /// When the rows were written: their clock times are the next ones after it
  var writtenAt: Date?
  /// Whether a stop was ever chosen
  var known: Bool

  static func load() -> StoredDepartures {
    let defaults = AppGroup.defaults
    let stopName = defaults?.string(forKey: "stop_name")
    let data = defaults?.string(forKey: "departures_json")
    return StoredDepartures(
      stopName: stopName,
      rows: data.map(DepartureRow.parse) ?? [],
      message: defaults?.string(forKey: "departures_list"),
      updated: defaults?.string(forKey: "last_updated"),
      writtenAt: defaults?.string(forKey: "updated_at").flatMap { ISO8601DateFormatter.lenient($0) },
      known: defaults?.string(forKey: "stop_id") != nil || data != nil)
  }

  /// The date of a clock time ("08:12") written at [reference]: the next one after it, a departure a little before it
  /// being one just gone
  static func date(of clock: String, after reference: Date) -> Date? {
    let parts = clock.split(separator: ":")
    guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
      return nil
    }
    let calendar = Calendar.current
    guard let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: reference) else {
      return nil
    }
    // 00:10 written at 23:55 is tomorrow's
    if date < reference.addingTimeInterval(-30 * 60) {
      return calendar.date(byAdding: .day, value: 1, to: date)
    }
    return date
  }

  /// The rows at [date]: a departure gone (a minute after its time) gives its place to the following one, a row with
  /// none left goes
  func rows(at date: Date) -> [DepartureRow] {
    guard let reference = writtenAt else {
      return rows
    }
    return rows.compactMap { row in
      guard let first = Self.date(of: row.time, after: reference), first.addingTimeInterval(60) <= date else {
        return row
      }
      guard !row.next.isEmpty, let next = Self.date(of: row.next, after: reference), next.addingTimeInterval(60) > date
      else {
        return nil
      }
      var moved = row
      moved.time = row.next
      moved.next = ""
      // The real-time signal was the first departure's
      moved.state = ""
      return moved
    }
  }

  /// When the rows change: a minute after each departure
  func changes(after now: Date) -> [Date] {
    guard let reference = writtenAt else {
      return []
    }
    let dates = rows.flatMap { [$0.time, $0.next] }
      .filter { !$0.isEmpty }
      .compactMap { Self.date(of: $0, after: reference)?.addingTimeInterval(60) }
      .filter { $0 > now }
    return Array(Set(dates)).sorted().prefix(16).map { $0 }
  }
}

extension ISO8601DateFormatter {
  /// Dart's `toIso8601String()`: with fractional seconds (microseconds), else without
  static func lenient(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) {
      return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
  }
}

struct DeparturesEntry: TimelineEntry {
  let date: Date
  let stored: StoredDepartures
  let rows: [DepartureRow]
}

struct DeparturesProvider: TimelineProvider {
  func placeholder(in context: Context) -> DeparturesEntry {
    let sample = DepartureRow(
      line: "1", background: "FFCD00", foreground: "000000", time: "08:12", destination: "La Défense", mode: "metro",
      state: "live", next: "08:15")
    let stored = StoredDepartures(
      stopName: "Châtelet", rows: [sample], message: nil, updated: nil, writtenAt: nil, known: true)
    return DeparturesEntry(date: Date(), stored: stored, rows: stored.rows)
  }

  func getSnapshot(in context: Context, completion: @escaping (DeparturesEntry) -> Void) {
    let stored = StoredDepartures.load()
    if context.isPreview && stored.rows.isEmpty {
      completion(placeholder(in: context))
    } else {
      completion(DeparturesEntry(date: Date(), stored: stored, rows: stored.rows(at: Date())))
    }
  }

  /// One entry now and one a minute after each departure; then nothing until the app writes again (it asks for a
  /// reload)
  func getTimeline(in context: Context, completion: @escaping (Timeline<DeparturesEntry>) -> Void) {
    let stored = StoredDepartures.load()
    let now = Date()
    let entries = ([now] + stored.changes(after: now)).map { date in
      DeparturesEntry(date: date, stored: stored, rows: stored.rows(at: date))
    }
    completion(Timeline(entries: entries, policy: .never))
  }
}

struct NextDeparturesView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var colorScheme

  let entry: DeparturesEntry

  var body: some View {
    content.widgetBackground()
  }

  @ViewBuilder private var content: some View {
    switch family {
    #if os(iOS)
    case .accessoryInline:
      inline
    case .accessoryRectangular:
      rectangular
    #endif
    case .systemSmall:
      small
    default:
      list(maxRows: family == .systemLarge ? 8 : 4)
    }
  }

  private var live: Color { colorScheme == .dark ? Color(hex: "3DD68C")! : Color(hex: "0A8F4E")! }
  private var late: Color { colorScheme == .dark ? Color(hex: "FB923C")! : Color(hex: "C2410C")! }

  private func timeColor(_ row: DepartureRow) -> Color {
    switch row.state {
    case "live": return live
    case "late": return late
    default: return .primary
    }
  }

  /// Why there is nothing to show: what the app said, else what to do
  private var message: String {
    if entry.stored.rows.isEmpty, let message = entry.stored.message {
      return message
    }
    if !entry.stored.known {
      return AppTexts.openApp
    }
    return AppTexts.noDeparture
  }

  private var header: some View {
    HStack(spacing: 6) {
      Text(entry.stored.stopName ?? AppTexts.noStop)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
      Spacer(minLength: 4)
      RefreshButton()
    }
  }

  private func list(maxRows: Int) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      header
      if entry.rows.isEmpty {
        Spacer(minLength: 0)
        Text(message).font(.footnote).foregroundColor(.secondary)
        Spacer(minLength: 0)
      } else {
        ForEach(Array(entry.rows.prefix(maxRows).enumerated()), id: \.offset) { _, row in
          HStack(spacing: 8) {
            LineBadge(row: row)
            Text(row.destination)
              .font(.footnote)
              .lineLimit(1)
            Spacer(minLength: 4)
            if !row.next.isEmpty {
              Text(row.next).font(.caption).foregroundColor(.secondary)
            }
            Text(row.time)
              .font(.footnote.weight(.semibold).monospacedDigit())
              .foregroundColor(timeColor(row))
          }
        }
        Spacer(minLength: 0)
      }
      if let updated = entry.stored.updated {
        Text(updated).font(.caption2).foregroundColor(.secondary).lineLimit(1)
      }
    }
  }

  /// The stop and its next departure
  private var small: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(entry.stored.stopName ?? "")
        .font(.subheadline.weight(.semibold))
        .lineLimit(2)
      Spacer(minLength: 0)
      if let row = entry.rows.first {
        HStack(spacing: 6) {
          LineBadge(row: row)
          Text(row.destination).font(.caption).lineLimit(1)
        }
        Text(row.time)
          .font(.title2.weight(.semibold).monospacedDigit())
          .foregroundColor(timeColor(row))
      } else {
        Text(message).font(.footnote).foregroundColor(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  #if os(iOS)
  /// Lock screen: the stop and its two next departures, in the system's tint
  private var rectangular: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(entry.stored.stopName ?? AppTexts.noStop)
        .font(.headline)
        .lineLimit(1)
      if entry.rows.isEmpty {
        Text(message).font(.caption).lineLimit(2)
      }
      ForEach(Array(entry.rows.prefix(2).enumerated()), id: \.offset) { _, row in
        HStack(spacing: 4) {
          Text(row.line).font(.caption.weight(.semibold))
          Text(row.destination).font(.caption).lineLimit(1)
          Spacer(minLength: 2)
          Text(row.time).font(.caption.weight(.semibold).monospacedDigit())
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Lock screen, above the clock: the next departure
  private var inline: some View {
    if let row = entry.rows.first {
      return Text("\(row.line) \(row.time) → \(row.destination)")
    }
    return Text(entry.stored.stopName ?? AppTexts.widgetName)
  }
  #endif
}

/// The line's badge in its IDFM shape: round metro, square bus and tram, rounded RER and train
struct LineBadge: View {
  let row: DepartureRow

  var body: some View {
    let background = Color(hex: row.background) ?? .gray
    let label = Text(row.line)
      .font(.caption2.weight(.semibold))
      .foregroundColor(Color(hex: row.foreground) ?? .white)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
    switch row.mode {
    case "metro":
      label.frame(width: 20, height: 20).background(Circle().fill(background))
    case "bus", "noctilien", "tram":
      label.padding(.horizontal, 4).frame(minWidth: 26, minHeight: 18)
        .background(RoundedRectangle(cornerRadius: 2).fill(background))
    default:
      label.padding(.horizontal, 4).frame(minWidth: 22, minHeight: 20)
        .background(RoundedRectangle(cornerRadius: 5).fill(background))
    }
  }
}

/// iOS 17: fetches the departures again in the background (`RefreshIntent.swift`); nothing elsewhere (macOS: the app
/// writes them when it shows them)
struct RefreshButton: View {
  var body: some View {
    #if os(iOS)
    if #available(iOS 17.0, *) {
      Button(intent: BackgroundIntent(url: URL(string: "guillaumedamiens://refreshdepartures"), appGroup: AppGroup.id)) {
        Image(systemName: "arrow.clockwise")
          .font(.caption.weight(.semibold))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(AppTexts.refresh)
    }
    #else
    EmptyView()
    #endif
  }
}

extension View {
  /// The system's background, with the content margins of iOS 17 and macOS 14 (a padding before)
  @ViewBuilder
  func widgetBackground() -> some View {
    if #available(iOS 17.0, macOS 14.0, *) {
      containerBackground(.background, for: .widget)
    } else {
      padding()
    }
  }
}

extension Color {
  /// `RRGGBB` or `#RRGGBB`
  init?(hex: String) {
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
      return nil
    }
    self.init(
      red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255)
  }
}
