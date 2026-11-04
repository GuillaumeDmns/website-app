#if os(iOS)
import AppIntents
import Foundation
import home_widget

/// The widget's refresh button (iOS 17): home_widget runs `homeWidgetBackgroundCallback`
/// (`lib/features/home_widget/home_widget_sync.dart`) in a background Dart isolate of the app, which fetches the
/// stop's departures and writes them for the widget. Built in both the app and the extension: the extension names it
/// on its button, the app runs it.
@available(iOS 17, *)
public struct BackgroundIntent: AppIntent {
  static public var title: LocalizedStringResource = "Refresh the departures"

  @Parameter(title: "Widget URI")
  var url: URL?

  @Parameter(title: "AppGroup")
  var appGroup: String?

  public init() {}

  public init(url: URL?, appGroup: String?) {
    self.url = url
    self.appGroup = appGroup
  }

  public func perform() async throws -> some IntentResult {
    await HomeWidgetBackgroundWorker.run(url: url, appGroup: appGroup ?? AppGroup.id)
    return .result()
  }
}

/// In the app (not the extension): the intent runs in the app's process, started in the background if needed
@available(iOS 17, *)
@available(iOSApplicationExtension, unavailable)
extension BackgroundIntent: ForegroundContinuableIntent {}
#endif
