import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/location/device_heading.dart';
import 'package:website_app/core/map/map_overlay.dart';

void main() {
  test('smooths headings as directions, across north', () {
    final smoother = HeadingSmoother(weight: 0.5);

    expect(smoother.add(350), closeTo(350, 0.01));
    // Halfway between 350° and 10°: north, not 180°
    expect(smoother.add(10), closeTo(0, 0.01));
    expect(smoother.add(10), closeTo(5, 0.1));
  });

  test('a single jump only moves part of the way', () {
    final smoother = HeadingSmoother(weight: 0.3);
    smoother.add(90);

    final heading = smoother.add(180);

    expect(heading, greaterThan(90));
    expect(heading, lessThan(135));
  });

  test('turns the short way', () {
    expect(headingDelta(350, 10), closeTo(20, 1e-9));
    expect(headingDelta(10, 350), closeTo(-20, 1e-9));
    expect(headingDelta(90, 270).abs(), closeTo(180, 1e-9));
  });

  test("the follow camera takes the device's heading when it asks for it", () {
    const follow = MapFollow(position: LatLng(48.85, 2.35), bearing: 90, compass: true);
    final heading = FollowHeading();

    expect(heading.apply(follow).bearing, 90);
    heading.device = 200;
    expect(heading.apply(follow).bearing, 200);
    expect(heading.apply(const MapFollow(position: LatLng(48.85, 2.35), bearing: 90)).bearing, 90);
  });

  testWidgets('turns at most 20 times a second, always to the last heading', (tester) async {
    final heading = FollowHeading();
    addTearDown(heading.dispose);
    final turns = <double>[];
    void turn() => turns.add(heading.device!);

    heading.update(10, turn);
    heading.update(20, turn);
    heading.update(30, turn);
    expect(turns, [10]);
    // The last one at the end of the interval, though nothing new came
    await tester.pump(FollowHeading.turnInterval);
    expect(turns, [10, 30]);
    await tester.pump(FollowHeading.turnInterval);
    expect(turns, [10, 30]);
  });

  testWidgets('a phone held still never turns the map; a real turn is followed closely', (tester) async {
    final heading = FollowHeading();
    addTearDown(heading.dispose);
    final turns = <double>[];
    void turn() => turns.add(heading.device!);
    Future<void> headings(List<double> values) async {
      for (final value in values) {
        heading.update(value, turn);
        await tester.pump(FollowHeading.turnInterval);
      }
    }

    // Lying on a table: the smoothed heading wanders a few degrees, a degree at a time
    await headings([90, 91, 92.2, 93, 92, 91, 89.8, 88.5, 89.5, 90.5]);
    expect(turns, [90]);
    // Turned by hand: every heading on the way, across north too
    await headings([92.5, 96, 100]);
    await headings([358, 357.5]);
    expect(turns, [90, 92.5, 96, 100, 358]);
    // Drifting slowly: once far enough from what is shown
    await headings([358.5, 359.5, 0.5, 1.5, 2.5, 3.5, 4.5]);
    expect(turns, [90, 92.5, 96, 100, 358, 4.5]);
  });

  test('a view less than half a degree away needs no move', () {
    const shown = MapFollow(position: LatLng(48.85, 2.35), bearing: 359.8);

    expect(shown.sameView(shown.withBearing(0.1)), isTrue);
    expect(shown.sameView(shown.withBearing(1)), isFalse);
  });
}
