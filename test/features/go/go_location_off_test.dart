import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/location/position_feed.dart';
import 'package:website_app/core/platform/live_journey.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';
import '../../support/standard_backend.dart';
import '../../support/test_container.dart';

/// The location turned off and on again during a journey: the schedule leads meanwhile, then the first good fix may be
/// anywhere on the journey
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => useLocale(const Locale('fr')));

  final start = DateTime.utc(2026, 10, 10, 8, 0);
  DateTime at(int minutes, [int seconds = 0]) => start.add(Duration(minutes: minutes, seconds: seconds));

  // Walk 4 min to Châtelet, metro 1 at 8:06 to Nation through Gare de Lyon (8 min), walk 3 min
  const office = JourneyPoint(name: 'Cours de Vincennes', lat: 48.8475, lon: 2.4000);
  final plan = journey([
    walk(at(0), 240),
    transit(at(6), 480, via: [gareDeLyon]),
    walk(at(14), 180, from: point(nation), to: office),
  ]);
  final tracker = GoTracker(plan);
  final ride = tracker.steps[1];
  final lastWalk = tracker.steps[2];

  GoInput back(DateTime now, LatLng position, {double accuracy = 10, double speed = 0}) =>
      GoInput(now: now, position: position, accuracy: accuracy, speed: speed, fixAt: now, relocate: true);

  group('the first fix once the location is back', () {
    test('on the last walk, two steps further: there', () {
      final onBoard = tracker.next(tracker.jumpTo(tracker.initial(), 1));
      final (progress, alerts) = tracker.update(onBoard, back(at(15), lastWalk.line.pointAt(lastWalk.line.length / 2)));
      expect(progress.step, 2);
      expect(progress.phase, GoPhase.moving);
      expect(progress.along, closeTo(lastWalk.line.length / 2, 5));
      expect(alerts.where((alert) => alert.id.startsWith('offroute')), isEmpty);
    });

    test('on the ride the clock got the user off: back on board, past the stops gone by', () {
      final offByClock = tracker.update(tracker.next(tracker.jumpTo(tracker.initial(), 1)), GoInput(now: at(14, 1))).$1;
      expect(offByClock.step, 2);
      expect(offByClock.byClock, isTrue);

      // A rough fix on the line: no precise one to say it, but the location is back
      final (progress, _) = tracker.update(offByClock, back(at(14, 30), ride.line.pointAt(ride.stopAlongs[1] + 300), accuracy: 60));
      expect(progress.step, 1);
      expect(progress.phase, GoPhase.onBoard);
      expect(progress.stopIndex, 1);
    });

    test('never back on a step the GPS saw done', () {
      final walking = tracker.update(
          tracker.next(tracker.jumpTo(tracker.initial(), 1)), GoInput(now: at(13, 50), position: ride.line.pointAt(ride.stopAlongs[2] - 20), accuracy: 10, speed: 3, fixAt: at(13, 50))).$1;
      expect(walking.step, 2);
      expect(walking.byClock, isFalse);

      // Then a fix back on the line, out of the station: the walk goes on, off its path for now
      final (progress, _) = tracker.update(walking, back(at(14, 30), ride.line.pointAt(ride.stopAlongs[1] + 300)));
      expect(progress.step, 2);
    });

    test('still on the step in progress: nothing moves', () {
      final onBoard = tracker.next(tracker.jumpTo(tracker.initial(), 1));
      final (progress, _) = tracker.update(onBoard, back(at(8), ride.line.pointAt(ride.stopAlongs[1] - 300), speed: 10));
      expect(progress.step, 1);
      expect(progress.phase, GoPhase.onBoard);
    });

    test('nowhere near the journey: off the way', () {
      final onBoard = tracker.next(tracker.jumpTo(tracker.initial(), 1));
      final (progress, alerts) = tracker.update(onBoard, back(at(10), const LatLng(48.8900, 2.2500)));
      expect(progress.issue, GoIssue.offRoute);
      expect(alerts.map((alert) => alert.id), ['offroute-1']);
    });

    test('at the stop of a later ride, standing: waiting for it', () {
      // Walk, metro 1 to Gare de Lyon, then the RER A from there
      final twoRides = GoTracker(journey([
        walk(at(0), 240),
        transit(at(6), 240, to: gareDeLyon),
        transit(at(12), 240, line: rerA, from: gareDeLyon, to: nation),
      ]));
      final (progress, _) = twoRides.update(twoRides.initial(), back(at(11), LatLng(gareDeLyon.lat, gareDeLyon.lon)));
      expect(progress.step, 2);
      expect(progress.phase, GoPhase.waiting);
    });
  });

  test('the controller: off, the schedule leads and the card says so; back on, the feed opens again and the next good '
      'fix places the user', () async {
    final base = DateTime.now().toUtc();
    DateTime when(int minutes, [int seconds = 0]) => base.add(Duration(minutes: minutes, seconds: seconds));
    var time = when(7);
    final live = journey([
      walk(when(0), 240),
      transit(when(6), 480, via: [gareDeLyon]),
      walk(when(14), 180, from: point(nation), to: office),
    ]);
    final fixes = StreamController<Position>.broadcast();
    final service = StreamController<bool>.broadcast();
    addTearDown(fixes.close);
    addTearDown(service.close);
    var opened = 0;
    final container = testContainer(standardBackend(), overrides: [
      positionFeedProvider.overrideWithValue(PositionFeed(
        open: (_) {
          opened++;
          return fixes.stream;
        },
        serviceEnabled: () => service.stream,
      )),
      liveJourneyProvider.overrideWithValue(_NoLiveJourney()),
      userLocationProvider.overrideWith((ref) => Stream.value(LatLng(chatelet.lat, chatelet.lon))),
      goClockProvider.overrideWithValue(() => time),
    ]);
    container.listen(goControllerProvider, (_, _) {});
    final controller = container.read(goControllerProvider.notifier);
    controller.start(live, const JourneyRequest());
    await pumpEventQueue();
    final steps = container.read(goControllerProvider)!.tracker.steps;
    Position fix(LatLng point, {double accuracy = 8, double speed = 0}) => Position(latitude: point.latitude, longitude: point.longitude,
        timestamp: time, accuracy: accuracy, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: speed, speedAccuracy: 0.5);

    // On board the metro
    fixes.add(fix(steps[1].line.pointAt(300), speed: 10));
    await pumpEventQueue();
    expect(container.read(goControllerProvider)!.progress.phase, GoPhase.onBoard);
    final openedBefore = opened;

    // Turned off
    service.add(false);
    await pumpEventQueue();
    expect(container.read(goControllerProvider)!.locationOff, isTrue);

    // Back on at 8:16, on the last walk: the device's stream opened again
    time = when(16);
    service.add(true);
    await pumpEventQueue();
    expect(container.read(goControllerProvider)!.locationOff, isFalse);
    expect(opened, greaterThan(openedBefore));

    // Meanwhile the clock got the user off the metro (8:14)
    expect(container.read(goControllerProvider)!.progress.step, 2);
    expect(container.read(goControllerProvider)!.progress.byClock, isTrue);

    // The system's last position given again first, on the metro's line: not where the user is, nothing goes back
    final walkPoint = steps[2].line.pointAt(steps[2].line.length / 2);
    fixes.add(fix(steps[1].line.pointAt(300)));
    await pumpEventQueue();
    expect(container.read(goControllerProvider)!.progress.step, 2);

    // Then a precise one on the walk
    time = time.add(const Duration(seconds: 3));
    fixes.add(fix(walkPoint, speed: 1.3));
    await pumpEventQueue();
    final state = container.read(goControllerProvider)!;
    expect(state.progress.step, 2);
    expect(state.progress.phase, GoPhase.moving);
    expect(state.progress.along, closeTo(steps[2].line.length / 2, 10));

    controller.stop();
  });
}

class _NoLiveJourney implements LiveJourney {
  @override
  Future<void> followDeparture(LiveDeparture departure) async {}

  @override
  Future<void> alert(String title, String? body) async {}

  @override
  Future<void> prepare() async {}

  @override
  Future<void> update(LiveJourneyUpdate update) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> keepScreenOn(bool on) async {}

  @override
  void onStop(VoidCallback stop) {}

  @override
  Future<bool> stopRequested() async => false;
}
