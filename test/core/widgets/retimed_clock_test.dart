import 'package:material_ui/material_ui.dart';
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

  test('moved: the minutes between the clocks printed, from 2 min off or said delayed', () {
    // 20:1x UTC: 21:1x in Paris
    DateTime at(int minute, int second) => DateTime.utc(2026, 11, 3, 20, minute, second);
    // 40 s late, still 21:11
    expect(RetimedClock.moved(at(11, 40), at(11, 0)), 0);
    // The RER A at Gare de Lyon, 45 s late across the minute (21:07:41, then 21:08:26): on time
    expect(RetimedClock.moved(at(8, 26), at(7, 41)), 0);
    // 4 s early across the minute (Transilien P, 21:12:00 then 21:11:56), 64 s early: on time
    expect(RetimedClock.moved(at(11, 56), at(12, 0)), 0);
    expect(RetimedClock.moved(at(21, 59), at(23, 3)), 0);
    // 1 min 59 off: still on time; 2 min: the minutes printed
    expect(RetimedClock.moved(at(12, 59), at(11, 0)), 0);
    expect(RetimedClock.moved(at(13, 0), at(11, 0)), 2);
    // 2 min 6 late across a minute (RER D, 21:36:30 then 21:38:36): the clocks print 2 min apart
    expect(RetimedClock.moved(at(38, 36), at(36, 30)), 2);
    expect(RetimedClock.moved(at(8, 59), at(11, 0)), -3);
    expect(RetimedClock.moved(at(14, 30), at(11, 30)), 3);
    // Said delayed by the real time (a bus, 77 s late): moved however little, as long as its clock changes
    expect(RetimedClock.moved(at(12, 17), at(11, 0), delayed: true), 1);
    expect(RetimedClock.moved(at(11, 40), at(11, 0), delayed: true), 0);
    // Said delayed but early by the real time: not late
    expect(RetimedClock.moved(at(10, 30), at(11, 30), delayed: true), 0);
    expect(RetimedClock.moved(at(11, 40), null), 0);
  });

  testWidgets('less than 2 min off: the new time alone, nothing struck through nor colored', (tester) async {
    // RER A at Gare de Lyon, 21:07:41 planned and expected 45 s later: "21:08" alone, not "21:07" struck through
    final aimed = DateTime.utc(2026, 11, 3, 20, 7, 41);
    final expected = aimed.add(const Duration(seconds: 45));
    await pump(tester, RetimedClock(time: expected, planned: aimed));
    expect(find.byType(Text), findsOneWidget);
    expect(find.text(formatClock(expected)), findsOneWidget);
    expect(tester.widget<Text>(find.byType(Text)).style?.decoration, isNot(TextDecoration.lineThrough));
    expect(tester.widget<Text>(find.byType(Text)).style?.color, isNot(AppColors.light.delayed));

    // The same said delayed by the real time: late, the planned time struck through
    await pump(tester, RetimedClock(time: expected, planned: aimed, delayed: true));
    expect(tester.widget<Text>(find.text(formatClock(aimed))).style?.decoration, TextDecoration.lineThrough);
    expect(tester.widget<Text>(find.text(formatClock(expected))).style?.color, AppColors.light.delayed);
  });

  testWidgets('less than a minute off, or no planned time: the time alone', (tester) async {
    await pump(tester, RetimedClock(time: planned.add(const Duration(seconds: 25)), planned: planned));
    expect(find.byType(Text), findsOneWidget);
    expect(tester.widget<Text>(find.byType(Text)).style?.decoration, isNot(TextDecoration.lineThrough));

    await pump(tester, RetimedClock(time: planned, planned: null));
    expect(find.text(formatClock(planned)), findsOneWidget);
  });
}
