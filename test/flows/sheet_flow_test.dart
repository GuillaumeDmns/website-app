import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// The bottom sheet and the map behind it, like Citymapper: each page opens at its own height, going back finds the
/// page below as it was left, and the map keeps what it shows in the middle of the part left above the sheet
void main() {
  /// Where the sheet starts on the 915 px high screen
  double sheetTop(WidgetTester tester) => tester
      .getTopLeft(find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Material)).first)
      .dy;

  Offset onScreen(WidgetTester tester) =>
      MapCamera.of(tester.element(find.byType(MarkerLayer).first)).latLngToScreenOffset(userPosition);

  testWidgets('a stop opened from the raised home page opens at its own height; back, home as it was left',
      (tester) async {
    await pumpApp(tester, standardBackend());
    expect(sheetTop(tester), closeTo(915 * 0.5, 2));

    // Raised by its list, to see the nearby departures
    await tester.drag(find.text(currentL10n.homeSearchHint), const Offset(0, -600));
    await settle(tester);
    final raised = sheetTop(tester);
    expect(raised, lessThan(200));

    // The nearby stop: at its middle, the map showing it above
    await tapOn(tester, find.text('Châtelet'));
    expect(find.text(currentL10n.walkingConnections), findsOneWidget);
    expect(sheetTop(tester), closeTo(915 * (1 - 0.62), 2));

    // Back: home raised again
    await tapOn(tester, find.byTooltip(currentL10n.back));
    expect(find.text(currentL10n.homeSearchHint), findsOneWidget);
    expect(sheetTop(tester), closeTo(raised, 2));

    await closeApp(tester);
  });

  testWidgets('lowered by its handle with its list scrolled: the page shows its top, and a swipe on it raises the sheet',
      (tester) async {
    // A lower screen, where a stop's page is longer than the highest sheet
    await pumpApp(tester, standardBackend(), size: const Size(412, 600));
    await tapOn(tester, find.text('Châtelet'));

    // Raised, then its list scrolled down: its header out of sight
    await tester.dragFrom(Offset(206, sheetTop(tester) + 60), const Offset(0, -500));
    await settle(tester);
    await tester.dragFrom(const Offset(206, 400), const Offset(0, -300));
    await settle(tester);
    expect(find.byTooltip(currentL10n.back).hitTestable(), findsNothing);

    // Lowered by its handle, at the top of the sheet: as low as it goes, the page's header showing
    await tester.dragFrom(Offset(206, sheetTop(tester) + 11), const Offset(0, 900));
    await settle(tester);
    final lowest = sheetTop(tester);
    expect(lowest, closeTo(600 - 110, 2));
    expect(find.byTooltip(currentL10n.back).hitTestable(), findsOneWidget);

    // Swiped up on the page, not its handle: the sheet comes up (a list left scrolled took the swipe)
    await tester.dragFrom(Offset(206, lowest + 60), const Offset(0, -300));
    await settle(tester);
    expect(sheetTop(tester), lessThan(lowest - 200));

    await closeApp(tester);
  });

  testWidgets('the user stays in the middle of the part of the map above the sheet as it moves', (tester) async {
    await pumpApp(tester, standardBackend());

    // Not behind the sheet's edge: in the middle of the half above it
    expect(onScreen(tester).dy, closeTo(915 * 0.5 / 2, 4));
    expect(onScreen(tester).dx, closeTo(412 / 2, 4));

    // Lowered by its list: the map shows more, the user still in the middle of it
    await tester.drag(find.text(currentL10n.homeSearchHint), const Offset(0, 300));
    await settle(tester);
    final top = sheetTop(tester);
    expect(top, greaterThan(915 * 0.6));
    expect(onScreen(tester).dy, closeTo(top / 2, 4));

    await closeApp(tester);
  });
}
