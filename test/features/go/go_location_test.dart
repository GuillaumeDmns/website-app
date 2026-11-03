import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/location/position_feed.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/core/platform/live_journey.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_state.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';
import '../../support/standard_backend.dart';
import '../../support/test_container.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  useLocale(const Locale('fr'));
  final now = DateTime.now().toUtc();
  DateTime inMinutes(int minutes) => now.add(Duration(minutes: minutes));
  // Walk to Châtelet, metro 1 to Nation, walk
  final plan = journey([
    walk(inMinutes(0), 240),
    transit(inMinutes(6), 480, via: [gareDeLyon]),
    walk(inMinutes(14), 180, from: point(nation)),
  ]);
  final tracker = GoTracker(plan);
  GoState at(GoPhase phase, {int step = 0}) => GoState(
        tracker: tracker,
        request: const JourneyRequest(),
        progress: GoProgress(step: step, phase: phase),
        startedAt: now,
        plannedArrival: plan.arrival,
      );

  test('a fix a second on foot on screen, every two in the background, fewer waiting and on board, none once arrived', () {
    expect(goLocationNeed(at(GoPhase.moving), shown: true), const LocationNeed(Duration(seconds: 1)));
    expect(goLocationNeed(at(GoPhase.moving), shown: false), const LocationNeed(Duration(seconds: 2)));
    expect(goLocationNeed(at(GoPhase.waiting, step: 1), shown: true), const LocationNeed(Duration(seconds: 5)));
    expect(goLocationNeed(at(GoPhase.onBoard, step: 1), shown: false), const LocationNeed(Duration(seconds: 3)));
    expect(goLocationNeed(at(GoPhase.arrived, step: 3), shown: true), isNull);
    expect(goLocationNeed(null, shown: true), isNull);
  });

  test('a speed counts for what its accuracy leaves of it: a phone lying indoors is still', () {
    Position fix(double speed, double accuracy) => Position(
          latitude: 48.8584,
          longitude: 2.3470,
          timestamp: DateTime.now(),
          accuracy: 10,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: speed,
          speedAccuracy: accuracy,
        );

    expect(sureSpeed(fix(2.49, 2.14)), closeTo(0.35, 1e-9));
    expect(sureSpeed(fix(1.4, 0.3)), closeTo(1.1, 1e-9));
    expect(sureSpeed(fix(0.5, 1)), 0);
    expect(sureSpeed(fix(1.4, 0)), 1.4);
    expect(sureSpeed(fix(-1, 0)), isNull);
  });

  test('the same position given again (underground, the system gives its last one) is as old as when first given', () {
    final first = DateTime.utc(2026, 10, 31, 8, 0);
    Position fix(double latitude, DateTime time) => Position(
          latitude: latitude,
          longitude: 2.3470,
          timestamp: time,
          accuracy: 8,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
    final platform = fix(48.8584, first);

    expect(positionSince(platform, null, null), first);
    expect(positionSince(fix(48.8584, first.add(const Duration(minutes: 3))), platform, first), first);
    // A GPS standing still still wanders a little: each fix new
    final later = first.add(const Duration(seconds: 5));
    expect(positionSince(fix(48.85841, later), platform, first), later);
  });

  test("GO asks the app's feed for what each moment needs, and gives it back when it stops", () async {
    final opened = <LocationSettings>[];
    final feed = PositionFeed(open: (settings) {
      opened.add(settings);
      return StreamController<Position>().stream;
    });
    final container = testContainer(standardBackend(), overrides: [
      positionFeedProvider.overrideWithValue(feed),
      liveJourneyProvider.overrideWithValue(_NoLiveJourney()),
      userLocationProvider.overrideWith((ref) => Stream.value(const LatLng(48.8584, 2.3470))),
    ]);
    // The app on screen
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // Shown, as the GO bar and page do (Riverpod pauses a provider nobody listens to)
    container.listen(goControllerProvider, (_, _) {});
    final controller = container.read(goControllerProvider.notifier);

    controller.start(plan, const JourneyRequest());
    await pumpEventQueue();
    expect(feed.need, const LocationNeed(Duration(seconds: 1)));
    expect((opened.last as AndroidSettings).intervalDuration, const Duration(seconds: 1));

    // Screen off, then back
    for (final lifecycle in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      binding.handleAppLifecycleStateChanged(lifecycle);
    }
    expect(feed.need, const LocationNeed(Duration(seconds: 2)));
    for (final lifecycle in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      binding.handleAppLifecycleStateChanged(lifecycle);
    }
    expect(feed.need, const LocationNeed(Duration(seconds: 1)));

    // At the stop, then on board
    controller.jumpTo(1);
    expect(feed.need, const LocationNeed(Duration(seconds: 5)));
    controller.next();
    expect(container.read(goControllerProvider)!.progress.phase, GoPhase.onBoard);
    expect(feed.need, const LocationNeed(Duration(seconds: 3)));

    controller.stop();
    expect(feed.need, isNull);
    await pumpEventQueue();
    // Nobody else listens here: closed
    expect(feed.opened, isNull);
  });

  test("GO's dot comes with how sure its fix is, for the circle around it", () async {
    final fixes = StreamController<Position>.broadcast();
    addTearDown(fixes.close);
    final container = testContainer(standardBackend(), overrides: [
      positionFeedProvider.overrideWithValue(PositionFeed(open: (_) => fixes.stream)),
      liveJourneyProvider.overrideWithValue(_NoLiveJourney()),
      userLocationProvider.overrideWith((ref) => Stream.value(const LatLng(48.8584, 2.3470))),
    ]);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    container.listen(goControllerProvider, (_, _) {});
    final controller = container.read(goControllerProvider.notifier);

    controller.start(plan, const JourneyRequest());
    await pumpEventQueue();
    fixes.add(Position(
      latitude: 48.8585,
      longitude: 2.3471,
      timestamp: DateTime.now(),
      accuracy: 12,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    ));
    await pumpEventQueue();
    expect(container.read(preciseUserPositionProvider)?.accuracy, 12);

    controller.stop();
    await pumpEventQueue();
    expect(container.read(preciseUserPositionProvider), isNull);
  });
}

/// No notification nor screen kept on in the tests
class _NoLiveJourney implements LiveJourney {
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
