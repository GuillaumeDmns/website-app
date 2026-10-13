// The device's heading in a browser: `deviceorientationabsolute` events (Chrome and Firefox on Android: alpha from
// north, counterclockwise), else Safari's `webkitCompassHeading`. Safari on iOS only sends them once the page asked
// for the permission after a tap, which the app doesn't do yet: no rotation there.
import 'dart:async';
import 'dart:js_interop';

@JS('window')
external _Window get _window;

extension type _Window._(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);

  external void removeEventListener(String type, JSFunction listener);

  external _Screen get screen;
}

extension type _Screen._(JSObject _) implements JSObject {
  external _ScreenOrientation? get orientation;
}

extension type _ScreenOrientation._(JSObject _) implements JSObject {
  external num get angle;
}

extension type _OrientationEvent._(JSObject _) implements JSObject {
  external num? get alpha;

  external num? get webkitCompassHeading;
}

Stream<double>? deviceHeadings() {
  late StreamController<double> controller;
  JSFunction? absolute;
  JSFunction? relative;

  void emit(double heading) {
    // The screen turned with the device (landscape): what is up on it
    final angle = _window.screen.orientation?.angle.toDouble() ?? 0;
    controller.add((heading + angle + 360) % 360);
  }

  controller = StreamController<double>(
    onListen: () {
      absolute = ((_OrientationEvent event) {
        final alpha = event.alpha;
        if (alpha != null) {
          emit(360 - alpha.toDouble());
        }
      }).toJS;
      relative = ((_OrientationEvent event) {
        final compass = event.webkitCompassHeading;
        if (compass != null) {
          emit(compass.toDouble());
        }
      }).toJS;
      _window.addEventListener('deviceorientationabsolute', absolute!);
      _window.addEventListener('deviceorientation', relative!);
    },
    onCancel: () {
      _window.removeEventListener('deviceorientationabsolute', absolute!);
      _window.removeEventListener('deviceorientation', relative!);
    },
  );
  return controller.stream;
}
