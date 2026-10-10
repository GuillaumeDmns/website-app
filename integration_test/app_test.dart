import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:website_app/core/widgets/line_badge.dart';
import 'package:website_app/features/journey/widgets/journey_card.dart';
import 'package:website_app/l10n/l10n.dart';

import '../test/support/standard_backend.dart';
import '../test/support/test_app.dart';

/// The real app on a real engine (Linux desktop in the CI, under a virtual screen), with the backend faked like in
/// the widget tests: `flutter test integration_test -d linux`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a guest finds a stop, its line and a journey', (tester) async {
    final backend = standardBackend();
    // Phone layout (bottom sheet over the map)
    await pumpApp(tester, backend, size: const Size(412, 915));

    expect(find.text(currentL10n.homeNearby), findsOneWidget);

    // Search
    await tapOn(tester, find.text(currentL10n.homeSearchHint));
    await tester.enterText(find.byType(TextField), 'chat');
    await settle(tester);
    await tapOn(tester, find.text('Châtelet (Paris)'));
    expect(find.text(currentL10n.walkingConnections), findsOneWidget);

    // Line
    await tapOn(tester, find.byWidgetPredicate((widget) => widget is LineBadge && widget.line.id == 'C01371'));
    expect(find.text('Gare de Lyon'), findsWidgets);
    await tapOn(tester, find.byTooltip(currentL10n.back));

    // Journey
    await tapOn(tester, find.text(currentL10n.goThere));
    expect(find.byType(JourneyCard), findsWidgets);
    await tapOn(tester, find.byType(JourneyCard));
    expect(backend.requestsTo('/api/v2/lines/C01371/rides'), isNotEmpty);

    await closeApp(tester);
  });

  testWidgets('the wide layout shows the page next to the map', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend, size: const Size(1280, 800));

    expect(find.text(currentL10n.homeNearby), findsOneWidget);
    await tapOn(tester, find.text(currentL10n.trafficTitle));
    expect(find.textContaining('Métro 1 : trafic interrompu'), findsWidgets);

    await closeApp(tester);
  });
}
