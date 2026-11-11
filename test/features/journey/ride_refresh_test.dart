import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/journey/journey_providers.dart';
import 'package:website_app/features/journey/journey_retime.dart';

import '../../support/fake_backend.dart';
import '../../support/samples.dart';
import '../../support/test_container.dart';

void main() {
  final now = DateTime.utc(2026, 10, 28, 8);

  test("departures are asked again every 30 s, every 2 min while they are a quarter of an hour away or more", () {
    expect(rideRefreshPeriod(null, now), const Duration(seconds: 30));
    expect(rideRefreshPeriod(now.add(const Duration(minutes: 10)), now), const Duration(seconds: 30));
    expect(rideRefreshPeriod(now.add(const Duration(minutes: 15)), now), const Duration(seconds: 30));
    // A connection at the end of a long ride, a journey for later
    expect(rideRefreshPeriod(now.add(const Duration(minutes: 40)), now), const Duration(minutes: 2));
  });

  group('departures of a ride no longer shown', () {
    const RideKey key = (lineId: 'C01371', from: 'IDFM:70001', to: 'IDFM:70003', after: null);

    /// Departures followed by a listener, their first answer arrived
    Future<(ProviderSubscription<AsyncValue<List<Ride>>>, FakeBackend, ProviderContainer)> followed(WidgetTester tester) async {
      final backend = FakeBackend()
        ..on('GET', '/api/v2/lines/*/rides', (_) => FakeResponse([ride(DateTime.utc(2030)).toJson()]));
      final container = testContainer(backend);
      final subscription = container.listen(rideOptionsProvider(key), (_, _) {});
      await answered(tester);
      expect(subscription.read().value, hasLength(1));
      return (subscription, backend, container);
    }

    testWidgets('past their period are reloaded when shown again: nothing to show until the new ones come', (tester) async {
      final (subscription, backend, container) = await followed(tester);

      subscription.pause();
      await tester.pump(const Duration(seconds: 31));
      // Paused: nothing asked while nothing shows them
      expect(backend.requestsTo('/api/v2/lines/C01371/rides'), hasLength(1));

      subscription.resume();
      expect(subscription.read().isReloading, isTrue);
      expect(currentRides(subscription.read()), isEmpty);

      await answered(tester);
      expect(currentRides(subscription.read()), hasLength(1));
      expect(backend.requestsTo('/api/v2/lines/C01371/rides'), hasLength(2));
      container.dispose();
    });

    testWidgets('within their period are kept as they are', (tester) async {
      final (subscription, backend, container) = await followed(tester);

      subscription.pause();
      await tester.pump(const Duration(seconds: 10));
      subscription.resume();

      expect(subscription.read().isLoading, isFalse);
      expect(currentRides(subscription.read()), hasLength(1));
      expect(backend.requestsTo('/api/v2/lines/C01371/rides'), hasLength(1));
      container.dispose();
    });

    testWidgets('shown all along stay on screen while they are asked again', (tester) async {
      final (subscription, backend, container) = await followed(tester);
      final seen = <bool>[];
      container.listen(rideOptionsProvider(key), (_, next) => seen.add(currentRides(next).isNotEmpty));

      await tester.pump(const Duration(seconds: 31));
      await answered(tester);

      expect(backend.requestsTo('/api/v2/lines/C01371/rides'), hasLength(2));
      expect(seen, isNotEmpty);
      expect(seen, everyElement(isTrue));
      container.dispose();
    });
  });
}

/// Lets the fake backend answer
Future<void> answered(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpWidget(const SizedBox());
}
