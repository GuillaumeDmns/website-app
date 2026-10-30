import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/widgets/line_badge.dart';
import 'package:website_app/features/map_place/map_place_sheet.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// Browsing the network as a guest: home, search, stop, line, traffic, favorites
void main() {
  Finder badgeOf(String lineId) => find.byWidgetPredicate((widget) => widget is LineBadge && widget.line.id == lineId);

  testWidgets('from the nearby stop to its line, saved as a favorite', (tester) async {
    final backend = standardBackend();
    final store = await pumpApp(tester, backend);

    // The nearby stop card opens the stop
    await tapOn(tester, find.text('Châtelet'));
    expect(find.text(currentL10n.walkingConnections), findsOneWidget);
    expect(find.text('Les Halles'), findsOneWidget);
    // Elevator outages are grouped
    expect(find.textContaining('ascenseur en panne'), findsOneWidget);
    expect(backend.requestsTo('/api/v2/stops/IDFM:70001'), hasLength(1));
    // The bus 38 doesn't stop here now
    expect(find.text(currentL10n.notServedLines('Bus 38')), findsOneWidget);
    // The RER as a station's board: its mission, its platform
    expect(find.text('UPAC'), findsOneWidget);
    expect(find.text('Voie A'), findsOneWidget);

    // Today's service of its lines, from the schedule: the last metro soon; a direction unfolds its frequencies
    expect(find.text(currentL10n.serviceHoursTitle), findsOneWidget);
    expect(find.text(currentL10n.lastDepartureIn('40\u00a0min')), findsOneWidget);
    expect(find.text(currentL10n.frequencyNow(currentL10n.frequencyEvery('4\u2060–\u20606\u00a0min'))), findsOneWidget);
    await tapOn(tester, find.text(currentL10n.towards('Fontenay-sous-Bois')));
    expect(find.text(currentL10n.periodDaytime), findsOneWidget);

    // Its line
    await tapOn(tester, badgeOf('C01371'));
    expect(find.text('Gare de Lyon'), findsWidgets);
    expect(find.textContaining('trafic interrompu'), findsWidgets);
    expect(find.textContaining(currentL10n.betweenStops('Châtelet', 'Nation')), findsOneWidget);
    expect(backend.requestsTo('/api/v2/lines/C01371/vehicles'), isNotEmpty);
    // The direction shown's service, counted at its busiest stop
    expect(find.text('${currentL10n.serviceHoursTitle} ${currentL10n.serviceCountedAt('Châtelet')}'), findsOneWidget);
    expect(find.text(currentL10n.lastDepartureIn('40\u00a0min')), findsOneWidget);

    // Saved on the device (guest)
    await tapOn(tester, find.byTooltip(currentL10n.favoriteAdd));
    expect(find.byTooltip(currentL10n.favoriteRemove), findsOneWidget);
    expect(store.values['favorites'], contains('C01371'));
    expect(backend.requestsTo('/api/v2/me/favorites'), isEmpty);

    // Back home: the favorite line is there
    await tapOn(tester, find.byTooltip(currentL10n.back));
    await tapOn(tester, find.byTooltip(currentL10n.back));
    expect(find.text(currentL10n.homeNearby), findsOneWidget);
    expect(badgeOf('C01371'), findsWidgets);

    await closeApp(tester);
  });

  testWidgets('searching a stop opens it and remembers it', (tester) async {
    final backend = standardBackend();
    final store = await pumpApp(tester, backend);

    await tapOn(tester, find.text(currentL10n.homeSearchHint));
    await tester.enterText(find.byType(TextField), 'chat');
    await settle(tester);
    expect(backend.requestsTo('/api/v2/search').last.queryParameters['q'], 'chat');
    // Where the user is, about 100 m: close places first
    expect(backend.requestsTo('/api/v2/search').last.queryParameters['lat'], '48.858');
    expect(backend.requestsTo('/api/v2/search').last.queryParameters['lon'], '2.347');
    expect(find.text('10 Rue de Rivoli (Paris)'), findsOneWidget);

    await tapOn(tester, find.text('Châtelet (Paris)'));
    expect(find.text(currentL10n.walkingConnections), findsOneWidget);
    expect(store.values['recent_searches'], contains('IDFM:70001'));

    await closeApp(tester);
  });

  testWidgets('the traffic summary leads to the traffic of every line', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend);

    await tapOn(tester, find.text(currentL10n.trafficTitle));
    expect(find.textContaining('Métro 1 : trafic interrompu'), findsWidgets);
    // Bus lines are folded
    expect(find.textContaining('ligne de bus perturbée'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('without network, the last data stay with a notice', (tester) async {
    final backend = standardBackend();
    final store = await pumpApp(tester, backend);
    await closeApp(tester);

    backend.down = true;
    await pumpApp(tester, backend, store: store);

    expect(find.text('Nation'), findsWidgets);
    expect(find.textContaining(currentL10n.offlineSince('').split('{').first.trim()), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('the app speaks English when asked', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend);

    await tapOn(tester, find.byTooltip(currentL10n.account));
    await tapOn(tester, find.text(currentL10n.otherLanguage));

    expect(find.text('Nearby'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a long press on the map names the point and goes there', (tester) async {
    final backend = standardBackend();
    backend.get('/api/v2/places/reverse',
        const PlaceResult(type: PlaceType.address, id: 'address:1', name: '2 Rue Jean Lantier 75001 Paris', lat: 48.8584, lon: 2.347).toJson());
    await pumpApp(tester, backend);

    await tester.longPressAt(const Offset(206, 200));
    await settle(tester);

    expect(backend.requestsTo('/api/v2/places/reverse'), hasLength(1));
    final sheet = find.byType(MapPlaceSheet);
    expect(find.descendant(of: sheet, matching: find.text('2 Rue Jean Lantier 75001 Paris')), findsOneWidget);
    await tapOn(tester, find.descendant(of: sheet, matching: find.text(currentL10n.goThere)));

    // The journey there, from the user's position
    expect(find.byType(MapPlaceSheet), findsNothing);
    expect(find.text('2 Rue Jean Lantier 75001 Paris'), findsWidgets);
    expect(backend.requestsTo('/api/v2/journeys').last.queryParameters['to'], startsWith('48.'));

    await closeApp(tester);
  });

  testWidgets('a point of the map without address keeps a plain name', (tester) async {
    final backend = standardBackend();
    backend.get('/api/v2/places/reverse', {'status': 404, 'detail': 'Not found'}, status: 404);
    await pumpApp(tester, backend);

    await tester.longPressAt(const Offset(206, 200));
    await settle(tester);
    await tapOn(tester, find.descendant(of: find.byType(MapPlaceSheet), matching: find.text(currentL10n.departuresAround)));

    expect(find.text(currentL10n.pointOnMap), findsWidgets);
    expect(backend.requestsTo('/api/v2/nearby/departures'), isNotEmpty);

    await closeApp(tester);
  });
}
