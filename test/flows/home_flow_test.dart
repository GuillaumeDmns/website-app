import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/widgets/line_badge.dart';
import 'package:website_app/features/home/nearby_departures.dart';
import 'package:website_app/l10n/l10n.dart';

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
}
