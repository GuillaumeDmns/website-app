import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/mobility_api.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/home_widget/android_widgets.dart';
import 'package:website_app/features/home_widget/traffic_widget.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/fake_backend.dart';
import '../../support/fake_home_widget.dart';
import '../../support/samples.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => useLocale(const Locale('fr')));

  const tram3a = LineSummary(id: 'C01389', name: 'T3a', mode: TransportMode.tram, color: 'FF7E2E', textColor: '000000');
  Favorite favoriteLine(int id, LineSummary line) => Favorite(id: id, kind: FavoriteKind.line, line: line);
  final favorites = [
    favoriteLine(1, metro1),
    Favorite(id: 2, kind: FavoriteKind.stop, stopAreaId: chatelet.id, stop: chatelet),
    favoriteLine(3, rerA),
    favoriteLine(4, bus38),
    favoriteLine(5, tram3a),
  ];
  final traffic = [
    const LineTraffic(line: metro1),
    LineTraffic(line: rerA, severity: DisruptionSeverity.disrupted, titles: ['Trafic ralenti', 'Travaux']),
    const LineTraffic(line: bus38, severity: DisruptionSeverity.info, titles: ['Arrêt déplacé']),
    LineTraffic(line: tram3a, severity: DisruptionSeverity.blocking, titles: ['Trafic interrompu | manifestation']),
  ];

  test('the favorite lines are kept in their order for the widget, and read back', () {
    final text = trafficWidgetLines(favorites);

    expect(text, 'C01371|1|FFCD00|000000|metro\nC01742|A|EB2132|FFFFFF|rer\nC02000|38|82C8E6|000000|bus\nC01389|T3a|FF7E2E|000000|tram\n');
    expect(readTrafficWidgetLines(text), [metro1.copyWith(longName: null), rerA.copyWith(longName: null), bus38.copyWith(longName: null), tram3a]);
    expect(readTrafficWidgetLines(null), isEmpty);
    expect(readTrafficWidgetLines('broken\n'), isEmpty);
  });

  test('the interrupted lines first, then the disrupted ones, then the others in the user\'s order', () {
    final rows = trafficWidgetRows(readTrafficWidgetLines(trafficWidgetLines(favorites)), traffic).trimRight().split('\n');

    expect(rows, [
      // A title can't break the row
      'C01389|T3a|FF7E2E|000000|tram|b|Trafic interrompu / manifestation',
      'C01742|A|EB2132|FFFFFF|rer|d|Trafic ralenti',
      'C01371|1|FFCD00|000000|metro|n|',
      // An information alone is normal traffic, as in the app's "Mes lignes"
      'C02000|38|82C8E6|000000|bus|n|',
    ]);
  });

  test('a line the traffic doesn\'t list is normal, and the rows stop at eight', () {
    final lines = [for (var i = 0; i < 10; i++) LineSummary(id: 'L$i', name: '$i', mode: TransportMode.bus)];

    final rows = trafficWidgetRows(lines, const []).trimRight().split('\n');

    expect(rows, hasLength(trafficWidgetMaxRows));
    expect(rows.first, 'L0|0|||bus|n|');
  });

  test('without favorite line, the widget says how to add one', () {
    final content = trafficWidgetContent(const [], traffic, DateTime(2026, 11, 17, 8, 30));

    expect(content['traffic_rows'], isNull);
    expect(content['traffic_message'], currentL10n.trafficWidgetNoLine);
    expect(content['traffic_updated'], '08:30');
  });

  test('the widget\'s refresh fetches the traffic once for the lines the app wrote', () async {
    final widgets = FakeHomeWidget(trafficWidgetIds: [5], data: {'traffic_lines': trafficWidgetLines(favorites)});
    final backend = FakeBackend()..on('GET', '/api/v2/traffic', (_) => FakeResponse([for (final line in traffic) line.toJson()]));

    await refreshTrafficWidget(MobilityApi(backend.dio()));

    expect(backend.requestsTo('/api/v2/traffic'), hasLength(1));
    expect(widgets.data['traffic_rows']!.trimRight().split('\n'), hasLength(4));
    expect(widgets.data['traffic_rows'], startsWith('C01389|T3a|'));
    expect(widgets.data['traffic_message'], isNull);
    expect(widgets.data['traffic_fetched_at'], isNotNull);
    expect(widgets.redraws, 1);
  });

  test('nothing is fetched without a widget placed, nor without favorite line', () async {
    final backend = FakeBackend()..on('GET', '/api/v2/traffic', (_) => FakeResponse([]));

    FakeHomeWidget(widgetIds: [3], data: {'traffic_lines': trafficWidgetLines(favorites)});
    await refreshTrafficWidget(MobilityApi(backend.dio()));
    final placed = FakeHomeWidget(trafficWidgetIds: [5], data: {'traffic_lines': ''});
    await refreshTrafficWidget(MobilityApi(backend.dio()));

    expect(backend.requestsTo('/api/v2/traffic'), isEmpty);
    expect(placed.data['traffic_message'], currentL10n.trafficWidgetNoLine);
  });

  test('the traffic unreachable: the widget keeps its rows and says it failed', () async {
    final widgets = FakeHomeWidget(
      trafficWidgetIds: [5],
      data: {'traffic_lines': trafficWidgetLines(favorites), 'traffic_rows': 'old\n', 'traffic_updated': '08:00'},
    );
    final backend = FakeBackend()..down = true;

    await refreshTrafficWidget(MobilityApi(backend.dio()));

    expect(widgets.data['traffic_rows'], 'old\n');
    expect(widgets.data['traffic_updated'], startsWith(currentL10n.widgetFailedAt('')));
    expect(widgets.data['traffic_fetched_at'], isNull);
  });

  test('the app keeps the lines even without a widget, and fills a placed one with the traffic it has', () async {
    final none = FakeHomeWidget();
    await syncTrafficWidget(favorites, traffic);
    expect(none.data['traffic_lines'], trafficWidgetLines(favorites));
    expect(none.data['traffic_rows'], isNull);

    final placed = FakeHomeWidget(trafficWidgetIds: [5]);
    await syncTrafficWidget(favorites, traffic);
    expect(placed.data['traffic_rows'], startsWith('C01389|T3a|'));
    expect(placed.redraws, 1);

    // The last favorite line removed
    await syncTrafficWidget(const [], null);
    expect(placed.data['traffic_lines'], '');
    expect(placed.data['traffic_rows'], isNull);
    expect(placed.data['traffic_message'], currentL10n.trafficWidgetNoLine);
  });

  test('a tap on the widget opens the line, or the traffic page', () {
    expect(widgetLaunchLocation(Uri.parse('guillaumedamiens://line?id=C01371')), '/lines/C01371');
    expect(widgetLaunchLocation(Uri.parse('guillaumedamiens://line?id=')), isNull);
    expect(widgetLaunchLocation(Uri.parse('guillaumedamiens://traffic')), '/traffic');
    expect(widgetLaunchLocation(Uri.parse('guillaumedamiens://refreshtraffic')), isNull);
  });
}
