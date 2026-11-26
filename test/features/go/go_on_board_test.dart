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

import '../../support/fake_backend.dart';
import '../../support/samples.dart';
import '../../support/standard_backend.dart';
import '../../support/test_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useLocale(const Locale('fr'));

  test('on board, GO follows the train the user is on, guessed without a word: a direct one runs through the stations', () async {
    final now = DateTime.now().toUtc();
    Ride train(String number, DateTime departs, List<StopAreaSummary> stops) => ride(departs, trainNumber: number).copyWith(stops: [
          for (final (index, stop) in stops.indexed)
            JourneyStop(name: stop.name, lat: stop.lat, lon: stop.lon, time: departs.add(Duration(minutes: 3 * index))),
        ]);
    // The RER A planned through Gare de Lyon to Nation, leaving now; an express straight to Nation leaves 30 s later
    final plan = journey([transit(now, 480, line: rerA, via: [gareDeLyon])]);
    final backend = standardBackend();
    backend.on('GET', '/api/v2/lines/*/rides', (_) => FakeResponse([
          train('1', now, [chatelet, gareDeLyon, nation]).toJson(),
          train('2', now.add(const Duration(seconds: 30)), [chatelet, nation]).toJson(),
        ]));
    final fixes = StreamController<Position>.broadcast();
    addTearDown(fixes.close);
    final container = testContainer(backend, overrides: [
      positionFeedProvider.overrideWithValue(PositionFeed(open: (_) => fixes.stream)),
      liveJourneyProvider.overrideWithValue(_NoLiveJourney()),
      userLocationProvider.overrideWith((ref) => Stream.value(LatLng(chatelet.lat, chatelet.lon))),
    ]);
    container.listen(goControllerProvider, (_, _) {});
    final controller = container.read(goControllerProvider.notifier);

    // Waiting at Châtelet: the departures seen
    controller.start(plan, const JourneyRequest());
    await pumpEventQueue();
    final step = container.read(goControllerProvider)!.tracker.steps.single;
    final lyon = step.stopAlongs[1];
    Position fix(double along, DateTime time) {
      final point = step.line.pointAt(along);
      return Position(
        latitude: point.latitude,
        longitude: point.longitude,
        timestamp: time,
        accuracy: 8,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 15,
        speedAccuracy: 0.5,
      );
    }

    // Seen leaving about when both did: the one followed for now
    var time = DateTime.now();
    fixes.add(fix(150, time));
    await pumpEventQueue();
    expect(container.read(goControllerProvider)!.progress.phase, GoPhase.onBoard);
    expect(container.read(goControllerProvider)!.journey.rides.single.stops, hasLength(3));

    // Through Gare de Lyon at 15 m/s: the express, not the train stopping there
    for (var along = lyon - 600; along < lyon + 600; along += 45) {
      time = time.add(const Duration(seconds: 3));
      fixes.add(fix(along, time));
      await pumpEventQueue();
    }
    await pumpEventQueue();

    final state = container.read(goControllerProvider)!;
    expect(state.journey.rides.single.stops.map((stop) => stop.name), ['Châtelet', 'Nation']);
    expect(state.progress.phase, GoPhase.onBoard);
    expect(state.tracker.stopsLeft(state.progress), 1);
    // Nothing said about it
    expect(state.progress.issue, isNull);
    expect(state.retained, isNull);

    controller.stop();
  });

  test('walking to the stop, GO aims at the departure the user can catch arriving first, without a word', () async {
    final now = DateTime.now().toUtc();
    DateTime at(int minutes) => now.add(Duration(minutes: minutes));
    Ride train(String number, int leaves, int arrives) =>
        ride(at(leaves), trainNumber: number, ride: Duration(minutes: arrives - leaves));
    // 4 min of walk planned to Châtelet, then the train of +4 min; the user, at their door, is more than 7 min away at
    // a usual pace: the train of +9 arriving at +17 can be caught, and the direct of +11 arriving at +16
    final plan = journey([walk(now, 240), transit(at(4), 480, line: rerA, via: [gareDeLyon])]);
    final backend = standardBackend();
    backend.on('GET', '/api/v2/lines/*/rides', (_) => FakeResponse([
          train('1', 4, 12).toJson(),
          train('2', 9, 17).toJson(),
          train('3', 11, 16).toJson(),
        ]));
    final fixes = StreamController<Position>.broadcast();
    addTearDown(fixes.close);
    var time = now;
    final container = testContainer(backend, overrides: [
      positionFeedProvider.overrideWithValue(PositionFeed(open: (_) => fixes.stream)),
      liveJourneyProvider.overrideWithValue(_NoLiveJourney()),
      userLocationProvider.overrideWith((ref) => Stream.value(LatLng(address.lat, address.lon))),
      goClockProvider.overrideWithValue(() => time),
    ]);
    container.listen(goControllerProvider, (_, _) {});
    final controller = container.read(goControllerProvider.notifier);

    controller.start(plan, const JourneyRequest());
    await pumpEventQueue();
    // At the door for half a minute: the same departure to aim at for 20 s before it is aimed at
    for (var second = 0; second <= 30; second += 5) {
      time = now.add(Duration(seconds: second));
      fixes.add(Position(
        latitude: address.lat + second * 1e-6,
        longitude: address.lon,
        timestamp: time,
        accuracy: 8,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0.5,
      ));
      await pumpEventQueue();
      if (second == 10) {
        expect(container.read(goControllerProvider)!.journey.rides.single.departure, at(4));
      }
    }
    for (var k = 0; k < 5; k++) {
      await pumpEventQueue();
    }

    final state = container.read(goControllerProvider)!;
    expect(state.progress.step, 0);
    expect(state.journey.rides.single.departure, at(11));
    expect(state.vehicle?.trainNumber, '3');
    // Nothing said about it
    expect(state.retained, isNull);
    expect(state.progress.issue, isNull);

    controller.stop();
  });

  test('seated early in a late train at a terminus, far down the platform: GO waits with it, never follows the one '
      'leaving on time meanwhile, nor gets the user off at that one\'s arrival', () async {
    final base = DateTime.now().toUtc();
    DateTime at(int minutes, [int seconds = 0]) => base.add(Duration(minutes: minutes, seconds: seconds));
    var time = at(4);
    Ride train(String number, DateTime aimed, DateTime departs, {bool atStop = false}) =>
        ride(departs, aimed: aimed, trainNumber: number).copyWith(
          departure: departure(departs, aimed: aimed, trainNumber: number).copyWith(atStop: atStop ? true : null),
          stops: [
            for (final (index, stop) in [chatelet, gareDeLyon, nation].indexed)
              JourneyStop(name: stop.name, lat: stop.lat, lon: stop.lon, time: aimed.add(Duration(minutes: 4 * index))),
          ],
        );
    // The train planned at 8:06 leaves at 8:12, standing at the platform meanwhile; another one leaves on time at 8:07
    final plan = journey([transit(at(6), 480, line: rerA, via: [gareDeLyon])]);
    final backend = standardBackend();
    backend.on('GET', '/api/v2/lines/*/rides', (_) => FakeResponse([
          train('A', at(6), at(12), atStop: true).toJson(),
          train('B', at(7), at(7)).toJson(),
        ]));
    final fixes = StreamController<Position>.broadcast();
    addTearDown(fixes.close);
    final container = testContainer(backend, overrides: [
      positionFeedProvider.overrideWithValue(PositionFeed(open: (_) => fixes.stream)),
      liveJourneyProvider.overrideWithValue(_NoLiveJourney()),
      userLocationProvider.overrideWith((ref) => Stream.value(LatLng(chatelet.lat, chatelet.lon))),
      goClockProvider.overrideWithValue(() => time),
    ]);
    container.listen(goControllerProvider, (_, _) {});
    final controller = container.read(goControllerProvider.notifier);
    controller.start(plan, const JourneyRequest());
    await pumpEventQueue();
    final step = container.read(goControllerProvider)!.tracker.steps.single;
    Position fix(double along, {double speed = 0}) {
      final point = step.line.pointAt(along);
      return Position(latitude: point.latitude, longitude: point.longitude, timestamp: time, accuracy: 8, altitude: 0,
          altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: speed, speedAccuracy: 0.5);
    }

    // Seated 420 m from the stop's point from 8:04 to 8:12
    while (time.isBefore(at(12))) {
      fixes.add(fix(420));
      await pumpEventQueue();
      final state = container.read(goControllerProvider)!;
      expect(state.progress.phase, GoPhase.waiting, reason: '$time');
      expect(state.progress.issue, isNull, reason: '$time');
      time = time.add(const Duration(seconds: 20));
    }

    // It leaves at 8:12
    for (var along = 430.0; along < 1100; along += 36) {
      fixes.add(fix(along, speed: 12));
      await pumpEventQueue();
      time = time.add(const Duration(seconds: 3));
    }
    var state = container.read(goControllerProvider)!;
    expect(state.progress.phase, GoPhase.onBoard);
    // On the times the API gives that train, six minutes late: the delay GO measures is little more than that
    expect(state.journey.rides.single.departure, at(12));
    expect(state.progress.shift.inSeconds, inInclusiveRange(-90, 60));

    // Into a tunnel: the GPS gives its last position again. Past the arrival of the one that left at 8:07 (8:15), still
    // on board; off about 8:19
    final last = fix(1100, speed: 12);
    while (time.isBefore(at(18, 30))) {
      time = time.add(const Duration(seconds: 30));
      fixes.add(Position(latitude: last.latitude, longitude: last.longitude, timestamp: time, accuracy: 8, altitude: 0,
          altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 12, speedAccuracy: 0.5));
      await pumpEventQueue();
      state = container.read(goControllerProvider)!;
      expect(state.progress.phase, GoPhase.onBoard, reason: '$time');
    }
    time = at(20, 30);
    fixes.add(Position(latitude: last.latitude, longitude: last.longitude, timestamp: time, accuracy: 8, altitude: 0,
        altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 12, speedAccuracy: 0.5));
    await pumpEventQueue();
    expect(container.read(goControllerProvider)!.progress.phase, GoPhase.arrived);

    controller.stop();
  });

  _sameMinuteTests();
}

/// No notification nor screen kept on in the tests
void _sameMinuteTests() {
  test('two trains leaving the same minute: the one chosen is the vehicle followed, its mission the header\'s', () async {
    final now = DateTime.now().toUtc();
    final leaves = now.add(const Duration(minutes: 5));
    Ride train(String mission, int minutes) => ride(leaves, ride: Duration(minutes: minutes))
        .copyWith(departure: departure(leaves, mission: mission));
    // Planned on the stopping one (10 min); a direct one leaves the same minute and arrives 4 min sooner
    final plan = journey([transit(leaves, 600, line: rerA)]);
    final backend = standardBackend();
    backend.on('GET', '/api/v2/lines/*/rides', (_) => FakeResponse([train('NOPE', 10).toJson(), train('SEBU', 6).toJson()]));
    final container = testContainer(backend, overrides: [
      positionFeedProvider.overrideWithValue(PositionFeed(open: (_) => const Stream.empty())),
      liveJourneyProvider.overrideWithValue(_NoLiveJourney()),
      userLocationProvider.overrideWith((ref) => Stream.value(LatLng(chatelet.lat, chatelet.lon))),
    ]);
    container.listen(goControllerProvider, (_, _) {});
    final controller = container.read(goControllerProvider.notifier);

    controller.start(plan, const JourneyRequest());
    await pumpEventQueue();
    expect(container.read(goControllerProvider)!.vehicle?.mission, 'NOPE');

    await controller.choose(0, train('SEBU', 6));
    await pumpEventQueue();
    expect(container.read(goControllerProvider)!.vehicle?.mission, 'SEBU');

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
