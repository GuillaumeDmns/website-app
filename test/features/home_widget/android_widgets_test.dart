import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/mobility_api.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/time_format.dart';
import 'package:website_app/features/home_widget/android_widgets.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/fake_backend.dart';
import '../../support/fake_home_widget.dart';
import '../../support/samples.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => useLocale(const Locale('fr')));

  final now = DateTime.utc(2026, 11, 12, 8, 10);
  DateTime at(int minutes) => now.add(Duration(minutes: minutes));
  int seconds(int minutes) => at(minutes).millisecondsSinceEpoch ~/ 1000;

  StopDepartures chateletBoard() => StopDepartures(
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
      );

  test('one row per line and direction, soonest first, with the times of its departures and their state', () {
    final rows = androidWidgetRows(chateletBoard()).trimRight().split('\n');

    expect(rows, [
      '1|FFCD00|000000|metro|Nation|${seconds(3)}:l,${seconds(9)}:l',
      // The cancelled one left out
      'A|EB2132|FFFFFF|rer|Boissy|${seconds(6)}:d',
      '38|82C8E6|000000|bus|Gare de Lyon|${seconds(12)}:s',
    ]);
  });

  test('only the lines chosen for the widget, in all their directions', () {
    final board = chateletBoard().copyWith(lines: [
      ...chateletBoard().lines,
      LineDepartures(line: metro1, destination: 'La Défense', departures: [departure(at(4))]),
    ]);

    final rows = androidWidgetRows(board, lines: {metro1.id}).trimRight().split('\n');
    expect(rows, hasLength(2));
    expect(rows, everyElement(startsWith('1|')));
  });

  test('the separators never come from the data; at most 8 rows', () {
    final rows = androidWidgetRows(StopDepartures(stop: chatelet, realtimeAvailable: true, lines: [
      LineDepartures(line: metro1, destination: 'A|B\nC', departures: [departure(at(3))]),
    ]));
    expect(rows.trimRight().split('|'), hasLength(6));
    expect(rows, contains('A/B C'));

    final many = StopDepartures(stop: chatelet, realtimeAvailable: true, lines: [
      for (var i = 0; i < 12; i++) LineDepartures(line: metro1, destination: 'D$i', departures: [departure(at(i + 1))]),
    ]);
    expect(androidWidgetRows(many).trimRight().split('\n'), hasLength(androidWidgetMaxRows));
  });

  test('without departures the widget says so', () {
    final content = widgetContent(StopDepartures(stop: chatelet, realtimeAvailable: true), now);
    expect(content['rows'], isNull);
    expect(content['message'], currentL10n.widgetNoDeparture);
    expect(content['updated'], formatClock(now));
  });

  test('a widget opens its stop, or the choice of its stop; nothing else', () {
    expect(widgetLaunchLocation(Uri.parse('guillaumedamiens://stop?id=IDFM:71264')), '/stops/IDFM%3A71264');
    expect(widgetLaunchLocation(Uri.parse('guillaumedamiens://widget?id=12')), '/widget/12');
    expect(widgetLaunchLocation(Uri.parse('guillaumedamiens://widget?id=x')), isNull);
    expect(widgetLaunchLocation(Uri.parse('guillaumedamiens://refreshdepartures')), isNull);
    expect(widgetLaunchLocation(null), isNull);
  });

  test('each widget gets the departures of its own stop, fetched once per stop', () async {
    final widgets = FakeHomeWidget(widgetIds: [3, 4, 5], data: {
      'w3_stop_id': chatelet.id,
      'w3_stop_name': chatelet.name,
      'w4_stop_id': chatelet.id,
      'w4_stop_name': chatelet.name,
      'w4_filter': rerA.id,
      // Widget 5 has no stop yet
    });
    final backend = FakeBackend()
      ..on('GET', '/api/v2/stops/IDFM:70001/departures', (_) => FakeResponse(chateletBoard().toJson()));

    await refreshAndroidWidgets(MobilityApi(backend.dio()));

    expect(backend.requestsTo('/api/v2/stops/IDFM:70001/departures'), hasLength(1));
    expect(widgets.data['w3_rows']!.trimRight().split('\n'), hasLength(3));
    // Only the RER A
    expect(widgets.data['w4_rows']!.trimRight().split('\n'), [startsWith('A|')]);
    expect(widgets.data.keys.where((key) => key.startsWith('w5_')), isEmpty);
    expect(widgets.data['widgets_fetched_at'], isNotNull);
    expect(widgets.redraws, 1);
  });

  test('the stop unreachable: the widgets keep their departures and say it failed', () async {
    final widgets = FakeHomeWidget(widgetIds: [3], data: {'w3_stop_id': chatelet.id, 'w3_rows': 'old\n', 'w3_updated': '08:00'});
    final backend = FakeBackend()..down = true;

    await refreshAndroidWidgets(MobilityApi(backend.dio()));

    expect(widgets.data['w3_rows'], 'old\n');
    expect(widgets.data['w3_updated'], startsWith(currentL10n.widgetFailedAt('')));
    expect(widgets.data['widgets_fetched_at'], isNull);
  });
}
