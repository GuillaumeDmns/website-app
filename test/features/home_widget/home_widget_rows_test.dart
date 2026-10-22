import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/time_format.dart';
import 'package:website_app/features/home_widget/home_widget_sync.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  final now = DateTime.utc(2026, 10, 22, 8, 10);
  DateTime at(int minutes) => now.add(Duration(minutes: minutes));

  test('one row per line and direction, soonest first: time, state, the following one', () {
    final rows = widgetRows(StopDepartures(
      stop: chatelet,
      realtimeAvailable: true,
      lines: [
        LineDepartures(line: bus38, destination: 'Gare de Lyon', departures: [departure(at(12), realtime: false)]),
        LineDepartures(line: metro1, destination: 'Nation', departures: [departure(at(3)), departure(at(9))]),
        LineDepartures(line: rerA, destination: 'Boissy', departures: [
          departure(at(1), status: 'cancelled'),
          departure(at(6), aimed: at(4), status: 'delayed'),
        ]),
      ],
    )).trimRight().split('\n');

    expect(rows, [
      '1|FFCD00|000000|${formatClock(at(3))}|Nation|metro|live|${formatClock(at(9))}',
      // The cancelled one left out
      'A|EB2132|FFFFFF|${formatClock(at(6))}|Boissy|rer|late|',
      '38|82C8E6|000000|${formatClock(at(12))}|Gare de Lyon|bus||',
    ]);
  });

  test('the separators never come from the data', () {
    final rows = widgetRows(StopDepartures(stop: chatelet, realtimeAvailable: true, lines: [
      LineDepartures(line: metro1, destination: 'A|B\nC', departures: [departure(at(3))]),
    ]));
    // A single row ends with a new line too
    expect(rows.endsWith('\n'), isTrue);
    expect(rows.trimRight().split('\n'), hasLength(1));
    expect(rows.trimRight().split('|'), hasLength(8));
    expect(rows, contains('A/B C'));
  });

  test('at most four rows; none without departures', () {
    final many = StopDepartures(stop: chatelet, realtimeAvailable: true, lines: [
      for (var i = 0; i < 6; i++) LineDepartures(line: metro1, destination: 'D$i', departures: [departure(at(i + 1))]),
      LineDepartures(line: rerA, destination: 'Nowhere', departures: const []),
    ]);
    expect(widgetRows(many).trimRight().split('\n'), hasLength(4));
    expect(widgetRows(StopDepartures(stop: chatelet, realtimeAvailable: true)), isEmpty);
  });
}
