import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/theme.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/time_format.dart';
import 'package:website_app/features/stops/widgets/stop_departures_card.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));
  final now = DateTime.utc(2026, 10, 28, 20);
  DateTime inMinutes(int minutes) => now.add(Duration(minutes: minutes));

  test("a train line's destinations in one board, in time order, as far as all of them are known", () {
    final board = trainBoard([
      // Every 7 min: its 5 departures run out at 31 min
      LineDepartures(line: rerA, destination: 'Paris Saint-Lazare', departures: [
        for (final minutes in [3, 10, 17, 24, 31]) departure(inMinutes(minutes)),
      ]),
      // Twice in the next hour: both known
      LineDepartures(line: rerA, destination: 'Maisons-Laffitte', departures: [departure(inMinutes(6)), departure(inMinutes(40))]),
    ], perDestination: 5);

    expect([for (final train in board) (train.departure.time.difference(now).inMinutes, train.destination[0])],
        [(3, 'P'), (6, 'M'), (10, 'P'), (17, 'P'), (24, 'P'), (31, 'P')]);
    // None ran out: all of them
    expect(trainBoard([LineDepartures(line: rerA, destination: 'Cergy', departures: [departure(inMinutes(5))])], perDestination: 5),
        hasLength(1));
  });

  testWidgets('a train of the board: its time, its delay, its mission and destination, its platform', (tester) async {
    final delayed = departure(inMinutes(4), aimed: inMinutes(1), mission: 'POPU', status: 'delayed').copyWith(platform: 'A');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      locale: const Locale('fr'),
      localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TrainDepartureRow(line: rerA, departure: delayed, destination: 'Paris Saint-Lazare', now: now),
      ),
    ));

    expect(find.text(formatClock(inMinutes(1))), findsOneWidget);
    expect(find.text(currentL10n.delayedTo(formatClock(inMinutes(4)))), findsOneWidget);
    expect(find.text('POPU'), findsOneWidget);
    expect(find.text('Paris Saint-Lazare'), findsOneWidget);
    expect(find.text('Voie A'), findsOneWidget);
  });
}
