import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/theme.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/features/journey/station_accesses.dart';
import 'package:website_app/features/journey/widgets/journey_map.dart';
import 'package:website_app/features/journey/widgets/station_access_sign.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../../support/samples.dart';

void main() {
  final start = DateTime.utc(2026, 10, 10, 8, 0);
  final trip = journey([
    walk(start, 300),
    transit(start.add(const Duration(minutes: 5)), 600),
  ]);

  Future<MapOverlay> overlayIn(WidgetTester tester, ThemeData theme) async {
    late MapOverlay overlay;
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Builder(builder: (context) {
        overlay = journeyOverlay(context, trip);
        return const SizedBox.shrink();
      }),
    ));
    return overlay;
  }

  testWidgets('draws walks dark and dotted, in dark mode too: the map stays light', (tester) async {
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      final walkPath = (await overlayIn(tester, theme)).paths.firstWhere((path) => path.dotted);

      expect(walkPath.color, walkPathColor);
      expect(walkPath.width, 5);
    }
  });

  testWidgets('draws rides in their line color', (tester) async {
    final ridePath = (await overlayIn(tester, ThemeData.light())).paths.firstWhere((path) => !path.dotted);

    expect(ridePath.color, const Color(0xFFFFCD00));
  });

  test("a station's ways in and out: navy signs close up, the ones taken green and named on top of them", () {
    useLocale(const Locale('fr'));
    const way = StationEntrance(id: 'way', code: '3', name: 'r. Auber', lat: 48.8735, lon: 2.3278);
    const other = StationEntrance(id: 'other', code: '4', name: 'r. de Caumartin', lat: 48.8733, lon: 2.3290);
    const door = StationEntrance(id: 'door', name: 'bd Haussmann', lat: 48.8738, lon: 2.3285);
    const StationAccesses havre = (stopAreaId: 'IDFM:71337', entrances: [way, other, door], taken: {'way': true}, exit: true);

    final pins = stationAccessPins(const [havre]);
    expect([for (final pin in pins) pin.label], [
      currentL10n.goExitNamed('4', 'r. de Caumartin'),
      'bd Haussmann',
      currentL10n.goExitNamed('3', 'r. Auber'),
    ]);
    expect(pins.every((pin) => pin.closeUp), isTrue);
    expect(pins.last.color, AppTheme.brand);
    expect(pins.first.color, stationAccessColor);
    // Their looks: the same number the same image, a door without one
    expect([for (final pin in pins) pin.image], ['access-4', 'access-door', 'access-taken-3-r. Auber']);

    // GO getting out of that station: its ways whatever the zoom
    expect(stationAccessPins(const [havre], shown: 'IDFM:71337').any((pin) => pin.closeUp), isFalse);
  });

  testWidgets("the ways in and out come under the journey's own pins", (tester) async {
    const StationAccesses station = (stopAreaId: 'IDFM:70001', entrances: [StationEntrance(id: 'a', code: '1', name: 'r. de Rivoli', lat: 48.859, lon: 2.3455)], taken: {}, exit: false);
    late MapOverlay overlay;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        overlay = journeyOverlay(context, trip, stations: const [station]);
        return const SizedBox.shrink();
      }),
    ));

    expect(overlay.pins.first.image, 'access-1');
    expect(overlay.pins.where((pin) => pin.closeUp), hasLength(1));
  });
}
