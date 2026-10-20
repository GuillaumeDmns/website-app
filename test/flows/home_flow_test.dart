import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/widgets/line_badge.dart';
import 'package:website_app/features/daily_trips/daily_trips.dart';
import 'package:website_app/features/favorites/favorite_widgets.dart';
import 'package:website_app/features/home/nearby_departures.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/memory_store.dart';
import '../support/samples.dart';
import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// The whole app, tapped through like a user (the backend is faked)
void main() {
  testWidgets('a new guest sees the departures around them', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend);

    expect(find.text(currentL10n.homeNearby), findsOneWidget);
    expect(find.text('Châtelet'), findsWidgets);
    expect(find.text('Nation'), findsWidgets);
    expect(backend.requestsTo('/api/auth/guest'), hasLength(1));
    expect(backend.requestsTo('/api/v2/nearby/departures').first.headers['Authorization'], 'Bearer guest-token');

    await closeApp(tester);
  });

  testWidgets('the nearby departures are filtered by kind, Vélib included', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend);
    // In the nearby cards (the traffic card shows disrupted lines too)
    Finder badgeOf(String lineId) => find.descendant(
          of: find.byType(NearbyDeparturesList),
          matching: find.byWidgetPredicate((widget) => widget is LineBadge && widget.line.id == lineId),
        );

    expect(badgeOf('C02000'), findsWidgets);
    expect(badgeOf('C01371'), findsWidgets);

    await tapOn(tester, find.text(currentL10n.filterBus));
    expect(badgeOf('C02000'), findsOneWidget);
    expect(badgeOf('C01371'), findsNothing);

    await tapOn(tester, find.text('Vélib'));
    expect(find.byType(NearbyDeparturesList), findsNothing);
    expect(find.text('Châtelet - Rivoli'), findsOneWidget);

    await tapOn(tester, find.text(currentL10n.filterAll));
    expect(badgeOf('C01371'), findsWidgets);

    await closeApp(tester);
  });

  testWidgets('a long press on a stop around saves it', (tester) async {
    final store = await pumpApp(tester, standardBackend());

    await tester.longPress(find.descendant(of: find.byType(NearbyDeparturesList), matching: find.text('Châtelet')).first);
    await settle(tester);

    expect(find.text(currentL10n.favoriteSaved('Châtelet')), findsOneWidget);
    expect(store.values['favorites'], contains('IDFM:70001'));

    await closeApp(tester);
  });

  final work = Favorite(id: -1, kind: FavoriteKind.work, label: 'Bureau', lat: nation.lat, lon: nation.lon);

  testWidgets('the work tile tells when to leave, from the trip saved there', (tester) async {
    final saved = DateTime.utc(2026, 10, 7, 7);
    final trip = DailyTrip.of(
      journey([walk(saved, 300), transit(saved.add(const Duration(minutes: 5)), 480)]),
      const JourneyRequest(
        from: JourneyPlace.point(name: '10 Rue de Rivoli', lat: 48.86, lon: 2.34),
        to: JourneyPlace.point(name: 'Bureau', lat: 48.8484, lon: 2.3959),
      ),
      now: saved,
    );
    final backend = standardBackend();
    await pumpApp(tester, backend, store: MemoryStore({'favorites': [work.toJson()], DailyTrips.key: [trip.toJson()]}));

    // The métro in 7 min, 5 min on foot: leave in 2 min
    final tile = find.descendant(of: find.byType(FavoriteShortcuts), matching: find.textContaining(currentL10n.leaveIn('2\u00a0min')));
    expect(tile, findsOneWidget);

    // Its detail, without a search
    await tapOn(tester, tile);
    expect(find.widgetWithText(FilledButton, currentL10n.go), findsOneWidget);
    expect(backend.requestsTo('/api/v2/journeys'), isEmpty);

    await closeApp(tester);
  });

  testWidgets('in the morning, going to work is offered in one tap', (tester) async {
    final morning = DateTime.now().copyWith(hour: 8, minute: 0);
    final backend = standardBackend();
    await pumpApp(tester, backend,
        store: MemoryStore({'favorites': [work.toJson()]}), overrides: [nowProvider.overrideWith((ref) => Stream.value(morning))]);

    await tapOn(tester, find.widgetWithText(ActionChip, currentL10n.homeSuggestWork));
    expect(backend.requestsTo('/api/v2/journeys').single.queryParameters['to'], '${nation.lat},${nation.lon}');

    await closeApp(tester);
  });
}
