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

  test('moved: the minutes between the clocks printed, not the delay rounded', () {
    // 20:1x UTC: 21:1x in Paris
    DateTime at(int minute, int second) => DateTime.utc(2026, 11, 3, 20, minute, second);
    // 40 s late, still 21:11
    expect(RetimedClock.moved(at(11, 40), at(11, 0)), 0);
    // 20 s late across the minute: 21:10, then 21:11
    expect(RetimedClock.moved(at(11, 10), at(10, 50)), 1);
    // 20 s early across the minute: 21:11, then 21:10
    expect(RetimedClock.moved(at(10, 50), at(11, 10)), -1);
    expect(RetimedClock.moved(at(14, 30), at(11, 30)), 3);
    expect(RetimedClock.moved(at(11, 40), null), 0);
  });

  testWidgets('late by less than a minute within the same minute: the time alone, nothing struck through', (tester) async {
    // Transilien L at Bécon les Bruyères, 21:11 planned and expected 40 s later: no "21:11" struck through before "21:11"
    final aimed = DateTime.utc(2026, 11, 3, 20, 11);
    await pump(tester, RetimedClock(time: aimed.add(const Duration(seconds: 40)), planned: aimed));
    expect(find.text(formatClock(aimed)), findsOneWidget);
    expect(tester.widget<Text>(find.byType(Text)).style?.decoration, isNot(TextDecoration.lineThrough));

    // 20 s late across the minute: moved, the planned time struck through
    final crossing = DateTime.utc(2026, 11, 3, 20, 10, 50);
    await pump(tester, RetimedClock(time: crossing.add(const Duration(seconds: 20)), planned: crossing));
    expect(tester.widget<Text>(find.text(formatClock(crossing))).style?.decoration, TextDecoration.lineThrough);
    expect(tester.widget<Text>(find.text(formatClock(aimed))).style?.color, AppColors.light.delayed);
  });

  testWidgets('less than a minute off, or no planned time: the time alone', (tester) async {
    await pump(tester, RetimedClock(time: planned.add(const Duration(seconds: 25)), planned: planned));
    expect(find.byType(Text), findsOneWidget);
    expect(tester.widget<Text>(find.byType(Text)).style?.decoration, isNot(TextDecoration.lineThrough));

    await pump(tester, RetimedClock(time: planned, planned: null));
    expect(find.text(formatClock(planned)), findsOneWidget);
  });
}
