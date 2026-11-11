import CoreLocation
import Flutter
import UIKit

/// Where the phone points, in degrees clockwise from north, for GO's map on foot and by bike (like Android's
/// `DeviceHeading.kt`): Core Location's compass, the top of the screen as the interface turns. Only while Dart listens
/// (GO following the user, the app on screen); at most 20 headings a second, smoothed on the Dart side.
final class DeviceHeading: NSObject, FlutterStreamHandler, CLLocationManagerDelegate {
  static let channelName = "com.guillaumedamiens.app/heading"
  private static let minInterval: TimeInterval = 0.05

  private var manager: CLLocationManager?
  private var events: FlutterEventSink?
  private var lastSent: TimeInterval = 0
  private var orientationObserver: NSObjectProtocol?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard CLLocationManager.headingAvailable() else {
      // No compass: the map keeps the direction of the way
      events(FlutterEndOfEventStream)
      return nil
    }
    self.events = events
    let manager = CLLocationManager()
    manager.delegate = self
    manager.headingFilter = 1
    self.manager = manager
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    orientationObserver = NotificationCenter.default.addObserver(
      forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.followOrientation()
    }
    followOrientation()
    manager.startUpdatingHeading()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager?.stopUpdatingHeading()
    manager?.delegate = nil
    manager = nil
    events = nil
    if let orientationObserver {
      NotificationCenter.default.removeObserver(orientationObserver)
      UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    orientationObserver = nil
    return nil
  }

  /// The heading is the direction of the top of the screen: it turns with the interface (flat or unknown, the last
  /// one holds)
  private func followOrientation() {
    switch UIDevice.current.orientation {
    case .portrait:
      manager?.headingOrientation = .portrait
    case .portraitUpsideDown:
      manager?.headingOrientation = .portraitUpsideDown
    case .landscapeLeft:
      manager?.headingOrientation = .landscapeLeft
    case .landscapeRight:
      manager?.headingOrientation = .landscapeRight
    default:
      break
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    guard let events, newHeading.headingAccuracy >= 0 else {
      return
    }
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastSent >= Self.minInterval else {
      return
    }
    lastSent = now
    // True north when the position is known, magnetic otherwise
    events(newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading)
  }

  func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
    false
  }
}
