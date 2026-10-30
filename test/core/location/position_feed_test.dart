import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/location/position_feed.dart';

/// A fix [north] meters north of Châtelet
Position fixAt(double north) => Position(
      latitude: 48.8584 + north / 111200,
      longitude: 2.3470,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 1.4,
      speedAccuracy: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The device's streams opened by the feed, with their settings
  late List<(LocationSettings, StreamController<Position>)> opened;
  PositionFeed feed() => PositionFeed(open: (settings) {
        final controller = StreamController<Position>();
        opened.add((settings, controller));
        return controller.stream;
      });
  setUp(() => opened = []);

  test("the regular stream while listened to, GO's while a journey is followed, the regular one again after", () async {
    final positions = feed();
    addTearDown(positions.dispose);
    await pumpEventQueue();
    expect(opened, isEmpty);

    final received = <Position>[];
    final subscription = positions.fixes.listen(received.add);
    await pumpEventQueue();
    expect(opened.single.$1.distanceFilter, regularDistanceFilter);

    positions.need = const LocationNeed(Duration(seconds: 1));
    await pumpEventQueue();
    expect(opened, hasLength(2));
    // Closed before the next one is opened: Geolocator would hand the first one out again
    expect(opened.first.$2.hasListener, isFalse);
    final go = opened.last.$1 as AndroidSettings;
    expect((go.intervalDuration, go.distanceFilter), (const Duration(seconds: 1), 0));
    opened.last.$2.add(fixAt(0));
    await pumpEventQueue();
    expect(received, hasLength(1));

    // The same need again changes nothing; a slower one opens it again
    positions.need = const LocationNeed(Duration(seconds: 1));
    await pumpEventQueue();
    expect(opened, hasLength(2));
    positions.need = const LocationNeed(Duration(seconds: 5));
    await pumpEventQueue();
    expect((opened.last.$1 as AndroidSettings).intervalDuration, const Duration(seconds: 5));

    positions.need = null;
    await pumpEventQueue();
    expect(opened, hasLength(4));
    expect(opened.last.$1.distanceFilter, regularDistanceFilter);
    expect(opened.where((stream) => stream.$2.hasListener), hasLength(1));

    await subscription.cancel();
    await pumpEventQueue();
    expect(opened.where((stream) => stream.$2.hasListener), isEmpty);
  });

  test('off screen, closed unless GO needs it', () async {
    final positions = feed();
    addTearDown(positions.dispose);
    final subscription = positions.fixes.listen((_) {});
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    positions.shown = false;
    await pumpEventQueue();
    expect(positions.opened, isNull);
    expect(opened.single.$2.hasListener, isFalse);

    // GO in the background: its foreground service follows the journey
    positions.need = const LocationNeed(Duration(seconds: 2));
    await pumpEventQueue();
    expect(positions.opened, (need: const LocationNeed(Duration(seconds: 2))));
    expect(opened.last.$2.hasListener, isTrue);

    positions
      ..need = null
      ..shown = true;
    await pumpEventQueue();
    expect(opened.last.$1.distanceFilter, regularDistanceFilter);
    expect(opened.where((stream) => stream.$2.hasListener), hasLength(1));
  });

  test('changes coming fast: only the last one is opened', () async {
    final positions = feed();
    addTearDown(positions.dispose);
    final subscription = positions.fixes.listen((_) {});
    addTearDown(subscription.cancel);

    positions
      ..need = const LocationNeed(Duration(seconds: 1))
      ..need = const LocationNeed(Duration(seconds: 3))
      ..need = const LocationNeed(Duration(seconds: 5));
    await pumpEventQueue();

    expect(opened, hasLength(1));
    expect((opened.single.$1 as AndroidSettings).intervalDuration, const Duration(seconds: 5));
  });

  test("the user's position moves every 25 m, even when GO asks a fix a second", () async {
    const geolocator = MethodChannel('flutter.baseflow.com/geolocator');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(geolocator, (call) async => switch (call.method) {
          'isLocationServiceEnabled' => true,
          'checkPermission' => LocationPermission.whileInUse.index,
          _ => null,
        });
    addTearDown(() => messenger.setMockMethodCallHandler(geolocator, null));
    final positions = feed();
    final container = ProviderContainer(overrides: [positionFeedProvider.overrideWithValue(positions)]);
    addTearDown(container.dispose);
    final shown = <LatLng?>[];
    container.listen(userLocationProvider, (_, next) => shown.add(next.value), fireImmediately: true);
    positions.need = const LocationNeed(Duration(seconds: 1));
    await pumpEventQueue();

    for (final north in const [0, 5, 12, 20, 30, 40, 70]) {
      opened.last.$2.add(fixAt(north.toDouble()));
      await pumpEventQueue();
    }

    final moves = [for (final position in shown.nonNulls) ((position.latitude - 48.8584) * 111200).round()];
    expect(moves, [0, 30, 70]);
  });
}
