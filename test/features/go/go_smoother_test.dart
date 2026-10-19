import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:website_app/core/location/device_heading.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/core/utils/geo.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_smoother.dart';

void main() {
  const start = LatLng(48.8584, 2.3470);
  // A way going east, 400 m long
  final way = MeasuredPolyline([start, const LatLng(48.8584, 2.3470 + 400 / 73300)]);
  LatLng east(double meters, {double north = 0}) =>
      LatLng(start.latitude + north / 111200, start.longitude + meters / 73300);
  final t0 = DateTime.utc(2026, 10, 18, 9, 0);
  DateTime after(int milliseconds) => t0.add(Duration(milliseconds: milliseconds));

  test('shows the first fix at once, then glides to the next one instead of jumping', () {
    final smoother = GoSmoother()..fix(start, t0);
    expect(smoother.at(t0), start);
    expect(smoother.moving(after(1000)), isFalse);

    smoother.fix(east(10), after(1000));
    // Halfway through the glide, eased out: three quarters of the way
    expect(metersBetween(smoother.at(after(1450))!, start), closeTo(7.5, 0.3));
    expect(metersBetween(smoother.at(after(2000))!, east(10)), lessThan(0.1));
    expect(smoother.moving(after(2000)), isFalse);
  });

  test('goes on along the way at the walking speed until the next fix, a few meters at most', () {
    final smoother = GoSmoother()..fix(east(50), t0, speed: 1.5, accuracy: 5, path: way);

    // 2 s later: 3 m further along the way
    expect(metersBetween(smoother.at(after(2000))!, east(53)), lessThan(0.2));
    expect(smoother.moving(after(2000)), isTrue);
    // Never more than 12 m ahead of the fix, then it stops moving
    expect(metersBetween(smoother.at(after(20000))!, east(50 + GoSmoother.maxAhead)), lessThan(0.2));
    expect(smoother.moving(after(20000)), isFalse);
  });

  test('keeps a fix beside the way beside it', () {
    final smoother = GoSmoother()..fix(east(50, north: 6), t0, speed: 1.5, accuracy: 5, path: way);

    expect(metersBetween(smoother.at(after(2000))!, east(53, north: 6)), lessThan(0.2));
  });

  test('stays at the fix when standing, inaccurate, or away from the way', () {
    for (final (speed, accuracy, north) in [(0.2, 5.0, 0.0), (1.5, 60.0, 0.0), (1.5, 5.0, 40.0)]) {
      final smoother = GoSmoother()..fix(east(50, north: north), t0, speed: speed, accuracy: accuracy, path: way);

      expect(metersBetween(smoother.at(after(3000))!, east(50, north: north)), lessThan(0.1));
      expect(smoother.moving(after(3000)), isFalse);
    }
  });

  test('forgets the fixes for a new session', () {
    final smoother = GoSmoother()..fix(start, t0);
    smoother.reset();

    expect(smoother.at(t0), isNull);
    smoother.fix(east(100), after(1000));
    // Shown at once: nothing to glide from
    expect(smoother.at(after(1000)), east(100));
  });

  test('a small step of the followed position moves the camera at once', () {
    const follow = MapFollow(position: start, bearing: 90);

    expect(follow.closeTo(follow.withPosition(east(1)).withBearing(100)), isTrue);
    expect(follow.closeTo(follow.withPosition(east(30))), isTrue);
    expect(follow.closeTo(follow.withPosition(east(80))), isFalse);
    expect(follow.closeTo(follow.withBearing(180)), isFalse);
  });

  test('the follow camera glides to the view asked, frame by frame, the short way round', () {
    const camera = MapFollow(position: start, bearing: 350);
    final target = camera.withBearing(20).withPosition(east(2));

    // A 60 Hz frame: part of the way, through north
    final frame = camera.glideTo(target, 1 / 60);
    expect(headingDelta(350, frame.bearing), inExclusiveRange(0, 30));
    expect(metersBetween(frame.position, start), inExclusiveRange(0, 2));
    // A longer frame goes further
    expect(headingDelta(350, camera.glideTo(target, 1 / 30).bearing), greaterThan(headingDelta(350, frame.bearing)));
    // Then there
    var view = camera;
    for (var i = 0; i < 120 && view != target; i++) {
      view = view.glideTo(target, 1 / 60);
    }
    expect(view, same(target));
  });

  test('counts the time between fixes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final stats = container.read(goFixStatsProvider.notifier);

    stats.record(t0, 12);
    expect(container.read(goFixStatsProvider)!.interval, isNull);
    stats
      ..record(after(1000), 8)
      ..record(after(3000), 6);
    expect(container.read(goFixStatsProvider)!.interval, const Duration(milliseconds: 1500));
    expect(container.read(goFixStatsProvider)!.accuracy, 6);
  });
}
