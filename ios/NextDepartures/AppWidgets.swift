import SwiftUI
import WidgetKit

/// The widget extension: the next departures (iOS, macOS) and GO's Live Activity (iOS)
@main
struct AppWidgets: WidgetBundle {
  var body: some Widget {
    NextDeparturesWidget()
    #if os(iOS)
    GoLiveActivityWidget()
    #endif
  }
}
