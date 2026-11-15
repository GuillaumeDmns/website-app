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
import 'package:website_app/features/go/go_glance.dart';
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
  final plan = journey([walk(now, 240), transit(now.add(const Duration(minutes: 6)), 480, via: [gareDeLyon])]);

  /// GO's providers on [store], with the notification [live]
  ProviderContainer app(MemoryStore store, {_LiveJourney? live}) {
    final container = testContainer(standardBackend(), store: store, overrides: [
      positionFeedProvider.overrideWithValue(PositionFeed(open: (_) => StreamController<Position>().stream)),
      liveJourneyProvider.overrideWithValue(live ?? _LiveJourney()),
      userLocationProvider.overrideWith((ref) => Stream.value(const LatLng(48.8584, 2.3470))),
    ]);
    // Shown, as the GO bar and page do
    container.listen(goControllerProvider, (_, _) {});
    return container;
  }

  /// A journey followed, kept on the device in [store]
  Future<void> follow(MemoryStore store) async {
    app(store).read(goControllerProvider.notifier).start(plan, const JourneyRequest());
    await pumpEventQueue();
  }

  test('the notification says how much its moment needs the user', () async {
    final live = _LiveJourney();
    final container = app(MemoryStore(), live: live);
    container.read(goControllerProvider.notifier).start(plan, const JourneyRequest());
    await pumpEventQueue();
    // As GO's own header: fine, to watch (orange) or to act now (red)
    final glance = goGlance(container.read(goControllerProvider)!, DateTime.now());
    expect(live.updates.last.tone, LiveJourneyTone.values[glance.tone.index]);
    expect(live.updates.last.title, glance.action);
    container.read(goControllerProvider.notifier).stop();
  });

  test('"Terminer" in the notification ends the session, and its copy on the device', () async {
    final live = _LiveJourney();
    final store = MemoryStore();
    final container = app(store, live: live);
    container.read(goControllerProvider.notifier).start(plan, const JourneyRequest());
    await pumpEventQueue();
    expect(store.values, contains('go_session'));

    live.tapStop();
    await pumpEventQueue();
    expect(container.read(goControllerProvider), isNull);
    expect(store.values, isNot(contains('go_session')));
  });

  test('"Terminer" tapped while the app was not running: the session is not taken up again at the next start', () async {
    // Without it, the next start goes on with the journey
    final kept = MemoryStore();
    await follow(kept);
    final resumed = app(kept);
    await pumpEventQueue();
    expect(resumed.read(goControllerProvider), isNotNull);
    resumed.read(goControllerProvider.notifier).stop();

    final finished = MemoryStore();
    await follow(finished);
    final next = app(finished, live: _LiveJourney(requested: true));
    await pumpEventQueue();
    expect(next.read(goControllerProvider), isNull);
    expect(finished.values, isNot(contains('go_session')));
  });
}

/// The notification of the tests: "Terminer" tapped on demand, or before the app started ([requested])
class _LiveJourney implements LiveJourney {
  @override
  Future<void> alert(String title, String? body) async {}

  _LiveJourney({this.requested = false});

  final bool requested;
  VoidCallback? _stop;

  void tapStop() => _stop?.call();

  @override
  Future<void> prepare() async {}

  final updates = <LiveJourneyUpdate>[];

  @override
  Future<void> update(LiveJourneyUpdate update) async => updates.add(update);

  @override
  Future<void> stop() async {}

  @override
  Future<void> keepScreenOn(bool on) async {}

  @override
  void onStop(VoidCallback stop) => _stop = stop;

  @override
  Future<bool> stopRequested() async => requested;
}
