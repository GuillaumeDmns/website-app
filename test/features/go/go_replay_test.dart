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
import 'package:website_app/features/go/go_trace.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/fake_backend.dart';
import '../../support/fake_live_journey.dart';
import '../../support/go_replay.dart';
import '../../support/memory_store.dart';
import '../../support/samples.dart';
import '../../support/standard_backend.dart';
import '../../support/test_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useLocale(const Locale('fr'));

  test('a session traced in a development build plays again the same: the late train seated in early is followed', () async {
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
    final plan = journey([transit(at(6), 480, line: rerA, via: [gareDeLyon])]);
    final backend = standardBackend();
    backend.on('GET', '/api/v2/lines/*/rides', (_) => FakeResponse([
          train('A', at(6), at(12), atStop: true).toJson(),
          train('B', at(7), at(7)).toJson(),
        ]));
    final store = MemoryStore();
    final fixes = StreamController<Position>.broadcast();
    addTearDown(fixes.close);
    final container = testContainer(backend, store: store, overrides: [
      positionFeedProvider.overrideWithValue(PositionFeed(open: (_) => fixes.stream, serviceEnabled: () => const Stream.empty())),
      liveJourneyProvider.overrideWithValue(FakeLiveJourney()),
      userLocationProvider.overrideWith((ref) => Stream.value(LatLng(chatelet.lat, chatelet.lon))),
      goClockProvider.overrideWithValue(() => time),
      goTraceProvider.overrideWith((ref) => GoTrace(store)),
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

    // Seated 420 m down the platform until 8:12, then off with the train
    for (; time.isBefore(at(12)); time = time.add(const Duration(seconds: 20))) {
      fixes.add(fix(420));
      await pumpEventQueue();
    }
    for (var along = 430.0; along < 1100; along += 36, time = time.add(const Duration(seconds: 3))) {
      fixes.add(fix(along, speed: 12));
      await pumpEventQueue();
    }
    expect(container.read(goControllerProvider)!.progress.phase, GoPhase.onBoard);
    controller.stop();
    await pumpEventQueue();

    // What the development build kept
    final sessions = await GoTrace.read(store);
    expect(sessions, hasLength(1));
    final events = sessions.single['events'] as List;
    expect(events.first, containsPair('kind', 'start'));
    expect(events.where((event) => (event as Map)['kind'] == 'fix'), hasLength(greaterThan(40)));
    expect(events.where((event) => (event as Map)['kind'] == 'rides'), isNotEmpty);
    expect(events.last, containsPair('kind', 'stop'));
    // Exported as text, read back
    expect(await GoTrace.export(store), contains('"kind": "fix"'));

    // Played again: waiting until it leaves, then on board that train, six minutes late
    final replayed = await replayGoTrace(sessions.single);
    for (final (:at, :state) in replayed) {
      if (at.isBefore(base.add(const Duration(minutes: 12)))) {
        expect(state.progress.phase, GoPhase.waiting, reason: '$at');
      }
    }
    final last = replayed.last.state;
    expect(last.progress.phase, GoPhase.onBoard);
    expect(last.journey.rides.single.departure, at(6));
    expect(last.progress.shift.inMinutes, inInclusiveRange(4, 6));
  });
}
