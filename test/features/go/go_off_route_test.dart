import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/location/position_feed.dart';
import 'package:website_app/core/platform/live_journey.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_glance.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/fake_live_journey.dart';
import '../../support/samples.dart';
import '../../support/standard_backend.dart';
import '../../support/test_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useLocale(const Locale('fr'));

  test('off the way: said, never replaced by another journey on its own; only the user recalculates', () async {
    final base = DateTime.now().toUtc();
    var time = base;
    final plan = journey([walk(base, 900)]);
    final backend = standardBackend();
    final fixes = StreamController<Position>.broadcast();
    addTearDown(fixes.close);
    final container = testContainer(backend, overrides: [
      positionFeedProvider.overrideWithValue(PositionFeed(open: (_) => fixes.stream, serviceEnabled: () => const Stream.empty())),
      liveJourneyProvider.overrideWithValue(FakeLiveJourney()),
      userLocationProvider.overrideWith((ref) => Stream.value(LatLng(chatelet.lat, chatelet.lon))),
      goClockProvider.overrideWithValue(() => time),
    ]);
    container.listen(goControllerProvider, (_, _) {});
    final controller = container.read(goControllerProvider.notifier);
    controller.start(plan, JourneyRequest(to: JourneyPlace.stopArea(name: chatelet.name, id: chatelet.id, lat: chatelet.lat, lon: chatelet.lon)));
    await pumpEventQueue();
    final step = container.read(goControllerProvider)!.tracker.steps.single;
    Future<void> at(LatLng point) async {
      fixes.add(Position(latitude: point.latitude, longitude: point.longitude, timestamp: time, accuracy: 8, altitude: 0,
          altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 1.3, speedAccuracy: 0.3));
      await pumpEventQueue();
      controller.tick();
      await pumpEventQueue();
    }

    // On the path, then 450 m away from it for two minutes
    await at(step.line.pointAt(60));
    for (var i = 0; i < 24; i++) {
      time = time.add(const Duration(seconds: 5));
      final beside = step.line.pointAt(100 + 6.0 * i);
      await at(LatLng(beside.latitude + 0.004, beside.longitude));
    }

    final state = container.read(goControllerProvider)!;
    expect(state.progress.issue, GoIssue.offRoute);
    expect(state.journey, same(plan));
    expect(backend.requestsTo('/api/v2/journeys'), isEmpty);
    expect(goGlance(state, time).place, isNull);

    // "Recalculer" tapped: then only
    await controller.recalculate();
    await pumpEventQueue();
    expect(backend.requestsTo('/api/v2/journeys'), hasLength(1));
    expect(container.read(goControllerProvider)!.journey, isNot(same(plan)));

    controller.stop();
    await pumpEventQueue();
  });
}
