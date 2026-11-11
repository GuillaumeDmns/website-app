import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/location/position_feed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('location off, the position looked for again while the device answers: the issue said once, no error',
      () async {
    // A desktop with location off: the app comes back on screen (looking for the position again) before the device
    // said whether location is on
    final answer = Completer<bool>();
    const geolocator = MethodChannel('flutter.baseflow.com/geolocator');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(geolocator, (call) async => switch (call.method) {
          'isLocationServiceEnabled' => await answer.future,
          _ => null,
        });
    addTearDown(() => messenger.setMockMethodCallHandler(geolocator, null));
    final positions = PositionFeed(open: (_) => const Stream.empty());
    addTearDown(positions.dispose);
    final container = ProviderContainer(overrides: [positionFeedProvider.overrideWithValue(positions)]);
    addTearDown(container.dispose);
    container.listen(userLocationProvider, (_, _) {});
    await pumpEventQueue();

    container.invalidate(userLocationProvider);
    container.read(userLocationProvider);
    answer.complete(false);
    await pumpEventQueue();

    expect(container.read(userLocationProvider).value, isNull);
    expect(container.read(locationIssueProvider), LocationIssue.serviceDisabled);
  });
}
