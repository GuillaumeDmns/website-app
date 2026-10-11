import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/widgets/line_badge.dart';
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

    // Its line
    await tapOn(tester, badgeOf('C01371'));
    expect(find.text('Gare de Lyon'), findsWidgets);
    expect(find.textContaining('trafic interrompu'), findsWidgets);
    expect(find.textContaining(currentL10n.betweenStops('Châtelet', 'Nation')), findsOneWidget);
    expect(backend.requestsTo('/api/v2/lines/C01371/vehicles'), isNotEmpty);

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
}
