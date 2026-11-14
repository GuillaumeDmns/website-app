import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/traffic/traffic_screen.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/app/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/map/map_view.dart';
import 'package:website_app/core/widgets/line_badge.dart';
import 'package:website_app/features/daily_trips/daily_trip_widgets.dart';
import 'package:website_app/features/daily_trips/daily_trips.dart';
import 'package:website_app/features/favorites/favorite_widgets.dart';
import 'package:website_app/features/home/map_stops.dart';
import 'package:website_app/features/home/nearby_departures.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/features/stops/widgets/stop_departures_card.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/fake_backend.dart';
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

  testWidgets('the work pill opens the next departure of the trip saved there, without a search', (tester) async {
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

    final pill = find.descendant(of: find.byType(FavoriteShortcuts), matching: find.text(currentL10n.work));
    expect(pill, findsOneWidget);

    // Its detail, without a search
    await tapOn(tester, pill);
    expect(find.widgetWithText(FilledButton, currentL10n.go), findsOneWidget);
    expect(backend.requestsTo('/api/v2/journeys'), isEmpty);

    await closeApp(tester);
  });

  testWidgets('in the morning, the trip to work is the first card: when to leave and GO', (tester) async {
    final morning = DateTime.now().copyWith(hour: 8, minute: 0);
    final saved = DateTime.utc(2026, 10, 7, 7);
    final trip = DailyTrip.of(
      journey([walk(saved, 300), transit(saved.add(const Duration(minutes: 5)), 480)]),
      const JourneyRequest(
        from: JourneyPlace.point(name: '10 Rue de Rivoli', lat: 48.86, lon: 2.34),
        to: JourneyPlace.point(name: 'Bureau', lat: 48.8484, lon: 2.3959),
      ),
      now: saved,
    );
    await pumpApp(tester, standardBackend(),
        store: MemoryStore({'favorites': [work.toJson()], DailyTrips.key: [trip.toJson()]}),
        overrides: [nowProvider.overrideWith((ref) => Stream.value(morning))]);

    // The suggestion and the trip are one card; not repeated under "Mes trajets"
    final card = find.ancestor(of: find.text(currentL10n.homeSuggestWork), matching: find.byType(DailyTripCard));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.widgetWithText(FilledButton, currentL10n.go)), findsOneWidget);
    expect(find.byType(DailyTripCard), findsOneWidget);
    expect(find.text(currentL10n.dailyTripsTitle), findsNothing);

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

  testWidgets('my lines tell their traffic: normal in green, the disruption otherwise', (tester) async {
    await pumpApp(tester, standardBackend(), store: MemoryStore({
      'favorites': [
        Favorite(id: -5, kind: FavoriteKind.line, line: metro1).toJson(),
        Favorite(id: -6, kind: FavoriteKind.line, line: rerA).toJson(),
      ],
    }));

    await tester.dragUntilVisible(find.text(currentL10n.myLines), find.byType(CustomScrollView), const Offset(0, -200));
    await settle(tester);
    // The métro 1 is interrupted in the standard backend's traffic, the RER A runs normally
    expect(find.text(currentL10n.trafficInterrupted), findsOneWidget);
    expect(find.text(currentL10n.trafficNormal), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('the kinds of departures are chosen under "À proximité", Vélib undone in one tap', (tester) async {
    await pumpApp(tester, standardBackend());

    // Right under the search and the places: the departures around, no scroll needed
    expect(find.byType(NearbyFilterChips), findsOneWidget);
    expect(find.byType(StopDeparturesCard), findsWidgets);
    final velib = find.descendant(of: find.byType(NearbyFilterChips), matching: find.text('Vélib'));
    await tapOn(tester, velib);
    expect(find.byType(StopDeparturesCard), findsNothing);
    await tapOn(tester, velib);
    expect(find.byType(StopDeparturesCard), findsWidgets);

    await closeApp(tester);
  });

  testWidgets('what the user saved comes first, the traffic then the departures around last', (tester) async {
    final store = MemoryStore({
      'favorites': [
        Favorite(id: -1, kind: FavoriteKind.stop, label: 'Nation', stopAreaId: nation.id, stop: nation).toJson(),
      ],
    });
    await pumpApp(tester, standardBackend(), store: store);

    double top(Finder finder) => tester.getTopLeft(finder.first).dy;
    expect(top(find.text(currentL10n.myStops)), lessThan(top(find.byType(TrafficSummaryCard))));
    await scrollTo(tester, find.text(currentL10n.homeNearby));
    expect(top(find.byType(TrafficSummaryCard, skipOffstage: false)), lessThan(top(find.text(currentL10n.homeNearby))));
    expect(top(find.text(currentL10n.homeNearby)), lessThan(top(find.byType(NearbyFilterChips))));

    await closeApp(tester);
  });

  testWidgets("a stop opened keeps its marker with its lines, and the stops around theirs", (tester) async {
    final backend = standardBackend();
    const hotelDeVille = StopAreaSummary(id: 'IDFM:70010', name: 'Hôtel de Ville', lat: 48.8592, lon: 2.3486, lines: [bus38]);
    backend.on('GET', '/api/v2/nearby', (_) => FakeResponse([chatelet.toJson(), hotelDeVille.toJson()]));
    backend.get('/api/v2/stops/IDFM:70010', StopAreaDetail(id: hotelDeVille.id, name: hotelDeVille.name, lat: hotelDeVille.lat, lon: hotelDeVille.lon, lines: const [bus38]).toJson());
    await pumpApp(tester, backend);

    await tapOn(tester, find.text('Châtelet'));
    expect(find.text(currentL10n.walkingConnections), findsOneWidget);
    // The marker with its lines, not a plain pin; its own opens nothing
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    List<MapPin> pins() => container.read(mapOverlaysProvider)[container.read(routerLocationProvider)]!.pins;
    final own = pins().singleWhere((pin) => pin.child is StopMarker && pin.label == 'Châtelet');
    expect((own.child! as StopMarker).lines, [rerA, metro1, bus38]);
    expect(own.onTap, isNull);
    expect(pins().where((pin) => pin.icon == Icons.directions_transit), isEmpty);

    // Another stop's marker: its page instead of this one, going back leaves the stops
    pins().singleWhere((pin) => pin.child is StopMarker && pin.label == 'Hôtel de Ville').onTap!();
    await settle(tester);
    expect(container.read(routerLocationProvider), Routes.stop(hotelDeVille.id));
    await tapOn(tester, find.byTooltip(currentL10n.back));
    expect(container.read(routerLocationProvider), Routes.home);

    await closeApp(tester);
  });

  testWidgets('close enough, the stops of the part of the map shown have their markers; a tap opens one', (tester) async {
    final backend = standardBackend();
    // A stop the map shows, further than the departures listed around
    const hotelDeVille = StopAreaSummary(id: 'IDFM:70010', name: 'Hôtel de Ville', lat: 48.8592, lon: 2.3486, lines: [bus38]);
    backend.on('GET', '/api/v2/nearby', (_) => FakeResponse([chatelet.toJson(), hotelDeVille.toJson()]));
    await pumpApp(tester, backend);

    // Asked around the middle of the map, as far as its corners, from the GTFS
    final request = backend.requestsTo('/api/v2/nearby').last.queryParameters;
    expect(request['lat'], closeTo(48.858, 0.005));
    expect(request['radius'], inInclusiveRange(500, 2000));
    // One marker per stop with its lines: Châtelet once, though listed around too
    StopMarker marker(Element element) => element.widget as StopMarker;
    expect([for (final element in find.byType(StopMarker).evaluate()) marker(element).lines.length]..sort(), [1, 3]);

    // Further out, only the stops around the user are left
    final container = ProviderScope.containerOf(tester.element(find.byType(StopMarker).first));
    container.read(mapViewProvider.notifier).update(mapViewOf(const LatLng(48.8584, 2.347), 12, const Size(412, 915), tileSize: 256));
    await settle(tester);
    expect([for (final element in find.byType(StopMarker).evaluate()) marker(element).lines], [
      [rerA, metro1, bus38],
    ]);

    // A tap: the stop's page
    await tester.tap(find.byType(StopMarker));
    await settle(tester);
    expect(find.text(currentL10n.walkingConnections), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a kind of departures chosen: the stops of that kind only on the map, with those lines', (tester) async {
    await pumpApp(tester, standardBackend());

    await tapOn(tester, find.descendant(of: find.byType(NearbyFilterChips), matching: find.text(currentL10n.filterBus)));
    expect([for (final element in find.byType(StopMarker).evaluate()) (element.widget as StopMarker).lines], [
      [bus38],
    ]);

    await closeApp(tester);
  });
}
