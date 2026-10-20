import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/daily_trips/daily_trips.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_screen.dart';
import 'package:website_app/features/go/go_state.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/features/journey/widgets/journey_card.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/fake_backend.dart';
import '../support/memory_store.dart';
import '../support/samples.dart';
import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// Daily trips: saved from a journey, then on the home page with their next departures and the last metro
void main() {
  final work = Favorite(id: -1, kind: FavoriteKind.work, label: 'Bureau', lat: nation.lat, lon: nation.lon);

  testWidgets('a daily trip shows when to leave, its next departures and the last metro', (tester) async {
    final backend = standardBackend();
    final saved = DateTime.utc(2026, 10, 7, 7);
    final trip = DailyTrip.of(
      journey([walk(saved, 300), transit(saved.add(const Duration(minutes: 5)), 480)]),
      const JourneyRequest(
        from: JourneyPlace.point(name: '10 Rue de Rivoli', lat: 48.86, lon: 2.34),
        to: JourneyPlace.point(name: 'Bureau', lat: 48.8484, lon: 2.3959),
      ),
      now: saved,
    );
    final store = MemoryStore({
      'favorites': [work.toJson()],
      DailyTrips.key: [trip.toJson()],
    });
    await pumpApp(tester, backend, store: store);

    // Named after the saved places, timed from the métro's departures (the next one in 7 min, 5 min on foot)
    expect(find.text(currentL10n.dailyTripsTitle), findsOneWidget);
    expect(find.text(currentL10n.dailyTripName('10 Rue de Rivoli', currentL10n.work)), findsOneWidget);
    expect(find.text(currentL10n.leaveIn('2 min')), findsOneWidget);
    expect(backend.requestsTo('/api/v2/lines/C01371/rides').first.queryParameters, containsPair('to', 'IDFM:70003'));
    expect(backend.requestsTo('/api/v2/journeys'), isEmpty);
    // The last métro in 40 min, 5 min from the start
    final last = backend.requestsTo('/api/v2/lines/C01371/rides/span');
    expect(last.first.queryParameters, containsPair('from', 'IDFM:70001'));
    expect(find.textContaining(currentL10n.lastRideOf(currentL10n.modeNounMetro, '1', '')), findsOneWidget);

    // The way back, on the same line
    await tapOn(tester, find.byTooltip(currentL10n.dailyTripReverse));
    expect(find.text(currentL10n.dailyTripName(currentL10n.work, '10 Rue de Rivoli')), findsOneWidget);
    expect(backend.requestsTo('/api/v2/lines/C01371/rides').last.queryParameters, containsPair('from', 'IDFM:70003'));

    // Opened, it is the detail of its next departure, already saved: taken out of the trips
    await tapOn(tester, find.text(currentL10n.dailyTripName(currentL10n.work, '10 Rue de Rivoli')));
    await tapOn(tester, find.byTooltip(currentL10n.dailyTripRemove));
    expect(find.text(currentL10n.dailyTripRemoved), findsOneWidget);
    expect(store.values[DailyTrips.key], '[]');

    await closeApp(tester);
  });

  testWidgets('GO starts on the next departure of a daily trip, without a search', (tester) async {
    final saved = DateTime.utc(2026, 10, 7, 7);
    final trip = DailyTrip.of(
      journey([walk(saved, 300), transit(saved.add(const Duration(minutes: 5)), 480)]),
      const JourneyRequest(
        from: JourneyPlace.point(name: '10 Rue de Rivoli', lat: 48.86, lon: 2.34),
        to: JourneyPlace.point(name: 'Bureau', lat: 48.8484, lon: 2.3959),
      ),
      now: saved,
    );
    final go = _StartedGo();
    final backend = standardBackend();
    await pumpApp(tester, backend, store: MemoryStore({DailyTrips.key: [trip.toJson()]}), overrides: [
      goControllerProvider.overrideWith(() => go),
    ]);

    await tapOn(tester, find.widgetWithText(FilledButton, currentL10n.go));

    // The métro in 7 min, not the one saved a few days ago
    expect(go.started?.rides.single.departure.isAfter(DateTime.now().toUtc()), isTrue);
    expect(find.byType(GoScreen), findsOneWidget);
    expect(backend.requestsTo('/api/v2/journeys'), isEmpty);

    await closeApp(tester);
  });

  testWidgets('home and work saved: the commute is chosen once, then followed', (tester) async {
    final backend = standardBackend();
    final home = Favorite(id: -2, kind: FavoriteKind.home, label: '10 Rue de Rivoli', lat: 48.86, lon: 2.34);
    final store = MemoryStore({
      'favorites': [home.toJson(), work.toJson()],
    });
    await pumpApp(tester, backend, store: store);

    await tapOn(tester, find.text(currentL10n.dailyTripChoose));
    expect(backend.requestsTo('/api/v2/journeys').single.queryParameters, containsPair('from', '48.86,2.34'));
    await tapOn(tester, find.byType(JourneyCard));
    await tapOn(tester, find.byTooltip(currentL10n.dailyTripSave));
    expect(find.text(currentL10n.dailyTripSaved), findsOneWidget);
    expect(store.values[DailyTrips.key], contains('C01371'));

    // Back home: the trip instead of the invitation, without searching again
    await tapOn(tester, find.byTooltip(currentL10n.back));
    await tapOn(tester, find.byTooltip(currentL10n.back));
    expect(find.text(currentL10n.dailyTripChoose), findsNothing);
    expect(find.textContaining(' → '), findsWidgets);
    expect(backend.requestsTo('/api/v2/journeys'), hasLength(1));

    await closeApp(tester);
  });

  testWidgets('a ride among the last ones of the night says so in the journey detail', (tester) async {
    final backend = standardBackend();
    DateTime inMinutes(int minutes) => DateTime.now().toUtc().add(Duration(minutes: minutes));
    backend.on('GET', '/api/v2/lines/*/rides/span', (_) => FakeResponse(RideSpan(
          last: ScheduledRide(departure: inMinutes(15), arrival: inMinutes(23)),
          next: ScheduledRide(departure: inMinutes(300), arrival: inMinutes(308)),
        ).toJson()));
    await pumpApp(tester, backend);

    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));
    await tapOn(tester, find.byType(JourneyCard));

    expect(find.textContaining(currentL10n.lastRideOf(currentL10n.modeNounMetro, '1', '')), findsOneWidget);

    await closeApp(tester);
  });
}

/// GO without its system side (GPS, notification): records the journey started
class _StartedGo extends GoController {
  JourneyOption? started;

  @override
  GoState? build() => null;

  @override
  void start(JourneyOption journey, JourneyRequest? request) => started = journey;
}
