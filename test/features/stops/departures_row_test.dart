import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:website_app/app/theme.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/widgets/departure_time.dart';
import 'package:website_app/features/stops/widgets/stop_departures_card.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));
  final now = DateTime.utc(2026, 11, 14, 7);
  DateTime inMinutes(int minutes) => now.add(Duration(minutes: minutes, seconds: 20));

  group('the departures after the first one', () {
    test('their minutes counted once', () {
      final departures = [for (final minutes in [7, 12, 47]) departure(inMinutes(minutes))];
      expect(followingDepartures(departures, now), 'puis 12 et 47 min');
      expect(followingDepartures(departures.take(2).toList(), now), 'puis 12 min');
      expect(followingDepartures(departures, now, count: 1), 'puis 12 min');
    });

    test('none after it: nothing', () {
      expect(followingDepartures([departure(inMinutes(7))], now), isNull);
      expect(followingDepartures(const [], now), isNull);
    });

    test('over an hour ahead, a clock time said whole; a cancelled one left out', () {
      final departures = [
        departure(inMinutes(7)),
        departure(inMinutes(20), status: 'cancelled'),
        departure(inMinutes(58)),
        departure(DateTime.utc(2026, 11, 14, 8, 5)),
      ];
      expect(followingDepartures(departures, now), matches(RegExp(r'^puis 58 min et \d\d:05$')));
    });
  });

  group('a line and destination of a stop', () {
    Future<void> pump(WidgetTester tester, LineDepartures row, {bool realtimeAvailable = true}) => tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('fr'),
          localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: LineDeparturesRow(row: row, now: now, realtimeAvailable: realtimeAvailable)),
        ));

    testWidgets('the destination in clear, one departure large, the next ones under the destination', (tester) async {
      await pump(tester, LineDepartures(line: bus38, destination: 'Gare de Lyon', departures: [
        for (final minutes in [7, 12, 47]) departure(inMinutes(minutes)),
      ]));

      expect(find.text('Gare de Lyon'), findsOneWidget);
      expect(find.text('puis 12 et 47 min'), findsOneWidget);
      // Not three times side by side, squeezing the destination
      expect(find.byType(DepartureTime), findsOneWidget);
    });

    testWidgets('only scheduled, its platform: said with the next ones', (tester) async {
      await pump(tester, LineDepartures(line: rerA, destination: 'Saint-Germain-en-Laye', departures: [
        departure(inMinutes(15), realtime: false).copyWith(platform: '2'),
        departure(inMinutes(51), realtime: false),
      ]));
      expect(find.text('puis 51 min · horaire prévu · voie 2'), findsOneWidget);

      // The whole stop without real time is said above its rows, not on each
      await pump(tester, LineDepartures(line: rerA, destination: 'Saint-Germain-en-Laye', departures: [
        departure(inMinutes(15), realtime: false),
      ]), realtimeAvailable: false);
      expect(find.textContaining('oraire prévu'), findsNothing);
    });

    testWidgets('a note alone starts its line', (tester) async {
      await pump(tester, LineDepartures(line: bus38, destination: 'Gare de Lyon', departures: [departure(inMinutes(15), realtime: false)]));
      expect(find.text('Horaire prévu'), findsOneWidget);
    });
  });
}
