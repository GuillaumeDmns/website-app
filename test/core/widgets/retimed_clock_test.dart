import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/theme.dart';
import 'package:website_app/core/utils/time_format.dart';
import 'package:website_app/core/widgets/departure_time.dart';
import 'package:website_app/l10n/l10n.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));
  final planned = DateTime.utc(2026, 11, 3, 13, 50);

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('fr'),
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ));

  testWidgets('a time moved by the real time: the planned one struck through, the new one beside it in its color',
      (tester) async {
    final late = planned.add(const Duration(minutes: 3));
    await pump(tester, RetimedClock(time: late, planned: planned));

    final was = find.text(formatClock(planned));
    final now = find.text(formatClock(late));
    expect(tester.widget<Text>(was).style?.decoration, TextDecoration.lineThrough);
    expect(tester.widget<Text>(now).style?.color, AppColors.light.delayed);
    // Read in order: the planned time, then the new one
    expect(tester.getCenter(was).dx, lessThan(tester.getCenter(now).dx));
    expect(find.bySemanticsLabel(currentL10n.retimedClock(formatClock(late), formatClock(planned))), findsOneWidget);
  });

  testWidgets('early in blue, stacked in a narrow column with the new time on top', (tester) async {
    final early = planned.subtract(const Duration(minutes: 2));
    await pump(tester, RetimedClock(time: early, planned: planned, stacked: true));

    final was = find.text(formatClock(planned));
    final now = find.text(formatClock(early));
    expect(tester.widget<Text>(now).style?.color, AppTheme.lightTheme.colorScheme.secondary);
    expect(tester.getCenter(now).dy, lessThan(tester.getCenter(was).dy));
  });

  testWidgets('less than a minute off, or no planned time: the time alone', (tester) async {
    await pump(tester, RetimedClock(time: planned.add(const Duration(seconds: 25)), planned: planned));
    expect(find.byType(Text), findsOneWidget);
    expect(tester.widget<Text>(find.byType(Text)).style?.decoration, isNot(TextDecoration.lineThrough));

    await pump(tester, RetimedClock(time: planned, planned: null));
    expect(find.text(formatClock(planned)), findsOneWidget);
  });
}
