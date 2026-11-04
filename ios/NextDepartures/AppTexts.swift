import Foundation

/// The few texts of the native side (the widget gallery, GO's Live Activity and macOS notification), in the device's
/// language like Android's resources (`values/`, `values-fr/`); the app writes everything else in its own.
enum AppTexts {
  private static let french = Locale.preferredLanguages.first?.lowercased().hasPrefix("fr") ?? false

  static var widgetName: String { french ? "Prochains départs" : "Next departures" }
  static var widgetDescription: String {
    french ? "Prochains départs de transport en commun en temps réel" : "Real-time next public transport departures"
  }
  static var noStop: String { french ? "Aucune station" : "No stop" }
  static var openApp: String { french ? "Ouvrez l'app pour choisir un arrêt" : "Open the app to choose a stop" }
  static var noDeparture: String { french ? "Aucun départ" : "No departure" }
  static var refresh: String { french ? "Actualiser" : "Refresh" }
  static var journey: String { french ? "Trajet en cours" : "Journey in progress" }
  static var finish: String { french ? "Terminer" : "Finish" }
}
