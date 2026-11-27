import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/widgets/line_badge.dart';
import 'package:website_app/features/service_hours/service_hours.dart';
import 'package:website_app/features/stops/widgets/stop_departures_card.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/samples.dart';
import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// A stop's page: its lines (the replacement buses apart), its departures by line, where the next bus is
void main() {
  testWidgets('replacement buses apart, departures under their line with its frequency, the next bus 2 stops away', (tester) async {
    const replacementA = LineSummary(
        id: 'C01849', name: 'A', longName: 'Remplacement RER A', mode: TransportMode.bus, color: 'FF1400', textColor: 'FFFFFF', replacement: true);
    final now = DateTime.now().toUtc();
    DateTime inMinutes(int minutes) => now.add(Duration(minutes: minutes));
    final backend = standardBackend();
    backend.get('/api/v2/stops/IDFM:70001', const StopAreaDetail(
      id: 'IDFM:70001',
      name: 'Châtelet',
      lat: 48.8584,
      lon: 2.3470,
      lines: [metro1, bus38, replacementA],
    ).toJson());
    backend.get('/api/v2/stops/IDFM:70001/departures', StopDepartures(
      stop: chatelet,
      realtimeAvailable: true,
      lines: [
        LineDepartures(line: metro1, destination: 'Nation', departures: [departure(inMinutes(3))]),
        LineDepartures(line: bus38, destination: 'Gare de Lyon', departures: [departure(inMinutes(6)), departure(inMinutes(18))]),
        LineDepartures(line: bus38, destination: 'Porte d\'Orléans', departures: [departure(inMinutes(4))]),
      ],
    ).toJson());
    backend.get('/api/v2/stops/IDFM:70001/service-hours', StopServiceHours(stop: chatelet, date: DateTime.utc(2026, 10, 14), lines: [
      LineServiceHours(line: bus38, date: DateTime.utc(2026, 10, 14), directions: [
        ServiceDirection(name: 'Gare de Lyon', first: inMinutes(-300), last: inMinutes(300), frequencies: [
          Frequency(period: ServicePeriod.daytime, start: inMinutes(-60), end: inMinutes(60), departures: 10, minMinutes: 12, maxMinutes: 15),
        ]),
      ]),
    ]).toJson());
    // The bus of the 6 min departure: two stops before Châtelet
    backend.get('/api/v2/lines/C02000/vehicles', [
      Vehicle(
        id: 'bus',
        destination: 'Gare de Lyon',
        direction: 0,
        branch: 0,
        fromStopId: 'IDFM:1',
        toStopId: 'IDFM:2',
        toStopName: 'Hôtel de Ville',
        progress: 0.5,
        expectedAt: inMinutes(2),
        calls: [
          VehicleCall(stopId: 'IDFM:2', stopName: 'Hôtel de Ville', expectedAt: inMinutes(2)),
          VehicleCall(stopId: 'IDFM:3', stopName: 'Pont Neuf', expectedAt: inMinutes(4)),
          VehicleCall(stopId: chatelet.id, stopName: 'Châtelet', expectedAt: inMinutes(6)),
        ],
      ).toJson(),
    ]);
    await pumpApp(tester, backend);
    await tapOn(tester, find.text('Châtelet'));

    // The replacement bus apart, under its own title
    expect(find.text(currentL10n.stopReplacementLines), findsOneWidget);
    // (once in the page: the stop's marker on the map has its lines too)
    expect(
      find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byWidgetPredicate((widget) => widget is LineBadge && widget.line.id == replacementA.id),
      ),
      findsOneWidget,
    );

    // The bus 38's two destinations under one badge with its frequency; the metro's single row keeps its own
    // (exactly so: the day's hours further down say it too, after "En ce moment")
    expect(
      find.text(frequencyLabel(Frequency(period: ServicePeriod.daytime, start: now, end: now, departures: 10, minMinutes: 12, maxMinutes: 15))),
      findsOneWidget,
    );
    final rows = tester.widgetList<LineDeparturesRow>(find.byType(LineDeparturesRow)).toList();
    expect([for (final row in rows) (row.row.destination, row.showBadge)], [
      ('Nation', true),
      ('Gare de Lyon', false),
      ("Porte d'Orléans", false),
    ]);
    // Where its next bus is
    expect(rows[1].approach, currentL10n.departureVehicleAway(2));
    expect(find.textContaining(currentL10n.departureVehicleAway(2).replaceFirst('à', 'À')), findsOneWidget);
    expect(rows[2].approach, isNull);

    await closeApp(tester);
  });
}
