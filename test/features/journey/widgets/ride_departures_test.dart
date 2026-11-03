import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/theme.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/time_format.dart';
import 'package:website_app/features/journey/widgets/ride_departures.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));
  final now = DateTime.now().toUtc();
  DateTime inMinutes(int minutes) => now.add(Duration(minutes: minutes));

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('fr'),
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ));

  testWidgets('a bus listed twice at the same minute: one row raised, the other one can be chosen', (tester) async {
    // The 341 serves two stops of Charles de Gaulle - Étoile: the same bus arrives at each
    final first = ride(inMinutes(10), ride: const Duration(minutes: 6));
    final second = ride(inMinutes(10), ride: const Duration(minutes: 10));
    final later = ride(inMinutes(21));
    Ride? chosen;
    await pump(
      tester,
      RideDepartureList(rides: [first, second, later], now: now, selected: first, onSelect: (ride) => chosen = ride),
    );

    final raised = tester.widgetList<Material>(find.byType(Material)).where((material) {
      final shape = material.shape;
      return shape is RoundedRectangleBorder && shape.side.width == 1.5;
    });
    expect(raised, hasLength(1));

    // The other one, by its own arrival
    await tester.tap(find.text(formatClock(second.arrivalAt!)));
    expect(chosen, second);
  });

  testWidgets('late and early departures: the planned time struck through, the new one beside it, no sign to add up',
      (tester) async {
    final late = ride(inMinutes(13), aimed: inMinutes(10));
    final early = ride(inMinutes(30), aimed: inMinutes(32));
    await pump(tester, RideDepartureList(rides: [late, early], now: now, selected: late, onSelect: (_) {}));

    for (final (moved, planned, color) in [
      (late, inMinutes(10), AppColors.light.delayed),
      (early, inMinutes(32), AppTheme.lightTheme.colorScheme.secondary),
    ]) {
      expect(tester.widget<Text>(find.text(formatClock(planned))).style?.decoration, TextDecoration.lineThrough);
      expect(tester.widget<Text>(find.text(formatClock(moved.departure.time))).style?.color, color);
    }
    expect(find.textContaining('+'), findsNothing);
    expect(find.textContaining(RegExp(r'^-\d')), findsNothing);
  });

  testWidgets('if the departure taken is missed: the next vehicle, not the same one listed again', (tester) async {
    final first = ride(inMinutes(10), ride: const Duration(minutes: 6));
    final second = ride(inMinutes(10), ride: const Duration(minutes: 10));
    final later = ride(inMinutes(21));
    await pump(tester, IfMissedLine(rides: [first, second, later], taken: first));

    expect(find.text(currentL10n.goIfMissed(formatClock(later.departure.time), 11)), findsOneWidget);
  });
}

