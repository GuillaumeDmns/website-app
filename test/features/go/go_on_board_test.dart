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
}

/// No notification nor screen kept on in the tests
class _NoLiveJourney implements LiveJourney {
  @override
  bool get systemAlerts => false;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> update(LiveJourneyUpdate update) async {}

  @override
  Future<void> alert(String title, String body, {bool urgent = false, String kind = 'info'}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> keepScreenOn(bool on) async {}
}
