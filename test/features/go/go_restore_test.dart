import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/location/position_feed.dart';
import 'package:website_app/core/platform/live_journey.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/memory_store.dart';
import '../../support/samples.dart';
import '../../support/standard_backend.dart';
import '../../support/test_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useLocale(const Locale('fr'));
  final now = DateTime.now().toUtc();
  // A walk that should have ended 5 min ago (the user is slower, or the app was away), then the metro in 2 min
  final plan = journey([
    walk(now.subtract(const Duration(minutes: 9)), 240),
    transit(now.add(const Duration(minutes: 2)), 480, via: [gareDeLyon]),
  ]);

  /// GO's providers on [store], no fix coming yet (the GPS starting)
  ProviderContainer app(MemoryStore store) {
    final container = testContainer(standardBackend(), store: store, overrides: [
      positionFeedProvider.overrideWithValue(PositionFeed(open: (_) => StreamController<Position>().stream)),
      liveJourneyProvider.overrideWithValue(_NoLiveJourney()),
      userLocationProvider.overrideWith((ref) => const Stream<LatLng?>.empty()),
    ]);
    // Shown, as the GO bar and page do
    container.listen(goControllerProvider, (_, _) {});
    return container;
  }

  test('taken up again after a restart, GO waits for the GPS before the schedule skips a step', () async {
    // The session as the device kept it: on the walk
    final store = MemoryStore({
      'go_session': {
        'journey': plan.toJson(),
        'request': const JourneyRequest().toQuery(),
        'progress': const GoProgress(step: 0, phase: GoPhase.moving).toJson(),
        'startedAt': now.subtract(const Duration(minutes: 9)).toIso8601String(),
        'plannedArrival': plan.arrival.toIso8601String(),
      },
    });
    final container = app(store);
    await pumpEventQueue();

    // Still on the walk while the first fix comes, not at the stop by the clock
    final state = container.read(goControllerProvider)!;
    expect(state.progress.step, 0);
    expect(state.progress.phase, GoPhase.moving);
    expect(state.tracker.followsSchedule(state.progress, DateTime.now()), isFalse);
    // Without any fix for a minute, the schedule leads as on any session that lost the GPS
    final (later, _) = state.tracker.update(state.progress, GoInput(now: DateTime.now().add(const Duration(seconds: 61))));
    expect(later.step, 1);
    expect(later.phase, GoPhase.waiting);

    container.read(goControllerProvider.notifier).stop();
  });

  test('started from a journey looked at for a while, GO begins with its walk, not at the stop', () async {
    final container = app(MemoryStore());
    container.read(goControllerProvider.notifier).start(plan, const JourneyRequest());
    await pumpEventQueue();

    expect(container.read(goControllerProvider)!.progress.step, 0);
    expect(container.read(goControllerProvider)!.progress.phase, GoPhase.moving);

    container.read(goControllerProvider.notifier).stop();
  });
}

/// No notification nor screen kept on in the tests
class _NoLiveJourney implements LiveJourney {
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
