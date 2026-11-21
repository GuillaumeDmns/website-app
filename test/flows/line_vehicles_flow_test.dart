import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/app/router.dart';
import 'package:website_app/app/routes.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/core/widgets/line_badge.dart';
import 'package:website_app/features/lines/line_vehicles.dart';
import 'package:website_app/features/lines/widgets/line_stop_tile.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/samples.dart';
import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// The vehicles of a line on its page: capsules turned the way they go, gliding along, selected and followed
void main() {
  testWidgets('vehicles glide along the line, pointing the way they go', (tester) async {
    final backend = standardBackend();
    final now = DateTime.now().toUtc();
    backend.get('/api/v2/lines/C01371/vehicles', [
      // Halfway from Châtelet to Gare de Lyon, two minutes late
      Vehicle(
        id: 'moving',
        destination: 'Nation',
        direction: 0,
        branch: 0,
        fromStopId: chatelet.id,
        toStopId: gareDeLyon.id,
        toStopName: 'Gare de Lyon',
        progress: 0.5,
        expectedAt: now.add(const Duration(seconds: 60)),
        delaySeconds: 120,
      ).toJson(),
      // Missing from the latest real time
      Vehicle(
        id: 'stale',
        destination: 'Nation',
        direction: 0,
        branch: 0,
        fromStopId: gareDeLyon.id,
        toStopId: nation.id,
        toStopName: 'Nation',
        progress: 0.3,
        expectedAt: now.add(const Duration(seconds: 90)),
        stale: true,
      ).toJson(),
      // The other way, from Nation to Gare de Lyon
      Vehicle(
        id: 'back',
        destination: 'Châtelet',
        direction: 1,
        branch: 0,
        fromStopId: nation.id,
        toStopId: gareDeLyon.id,
        toStopName: 'Gare de Lyon',
        progress: 0.4,
        expectedAt: now.add(const Duration(seconds: 80)),
      ).toJson(),
    ]);
    await pumpApp(tester, backend);

    await tapOn(tester, find.text('Châtelet'));
    // Its badge in the stop's page (the stop's marker on the map has one too)
    await tapOn(
      tester,
      find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byWidgetPredicate((widget) => widget is LineBadge && widget.line.id == metro1.id),
      ),
    );

    // On the map, a capsule turned the way it goes (the map turns it), nothing of its delay on it
    final map = find.byType(fm.FlutterMap);
    final onMap = find.descendant(of: map, matching: find.byType(VehicleCapsule));
    // Both ways by default: the whole line and every vehicle
    expect(onMap, findsNWidgets(3));
    expect(tester.widgetList<VehicleCapsule>(onMap).where((capsule) => capsule.selected || capsule.atStop), isEmpty);
    // Châtelet → Gare de Lyon goes south-east
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    List<MapPin> pins() => container.read(mapOverlaysProvider)[container.read(routerLocationProvider)]!.pins;
    expect(pins().firstWhere((pin) => pin.rotation != null).rotation, inInclusiveRange(90, 180));

    // On the stop list, each one on a row of its own between the stops, how many there are above them; the other
    // direction's running up the list
    expect(find.textContaining('3 trains'), findsOneWidget);
    final rows = tester.widgetList<LineVehicleTile>(find.byType(LineVehicleTile)).toList();
    expect(rows.map((row) => row.vehicle.id), ['moving', 'stale', 'back']);
    expect(rows.map((row) => row.reverse), [false, false, true]);
    expect(find.textContaining(currentL10n.goMinutesLate(2)), findsOneWidget);

    // One direction: its vehicles listed, the other one's faded on the map
    await tapOn(tester, find.text(currentL10n.towards('Nation')));
    expect(find.textContaining('2 trains vers Nation'), findsOneWidget);
    expect(find.byType(LineVehicleTile), findsNWidgets(2));
    expect(tester.widgetList<VehicleCapsule>(onMap).where((capsule) => capsule.faded), hasLength(1));
    await tapOn(tester, find.text(currentL10n.lineBothDirections));
    expect(find.byType(LineVehicleTile), findsNWidgets(3));

    // No trail behind them: the line's branches only
    final paths = tester.widgetList<fm.PolylineLayer>(find.byType(fm.PolylineLayer)).expand((layer) => layer.polylines);
    expect(paths.where((polyline) => polyline.strokeWidth > 6), isEmpty);

    // It moves on between two fetches, every second
    final before = tester.getCenter(onMap.first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1500)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getCenter(onMap.first), isNot(before));

    // Its sheet open, it is selected on the map, its next stop over it
    await tapOn(tester, onMap.first);
    bool selected() => tester.widgetList<VehicleCapsule>(onMap).any((capsule) => capsule.selected);
    expect(selected(), isTrue);
    expect(find.descendant(of: map, matching: find.byType(VehicleCallout)), findsOneWidget);
    expect(tester.widget<VehicleCallout>(find.byType(VehicleCallout)).stop, 'Gare de Lyon');

    // Followed on the map from its sheet, still selected once it is closed, until stopped
    await tapOn(tester, find.text(currentL10n.vehicleFollow));
    expect(find.text(currentL10n.vehicleFollowing), findsOneWidget);
    expect(selected(), isTrue);
    await tapOn(tester, find.byTooltip(currentL10n.vehicleStopFollowing));
    expect(find.text(currentL10n.vehicleFollowing), findsNothing);
    expect(selected(), isFalse);
    expect(find.byType(VehicleCallout), findsNothing);

    await closeApp(tester);
  });

  testWidgets('a line with branches: its trunk, its branches folded, its trains not stopping everywhere', (tester) async {
    StopRef at(String id, double km) => StopRef(id: id, name: 'Gare $id', lat: 48.8, lon: 2.0 + km * 0.013662);
    StopRef off(String id, double km) => StopRef(id: id, name: 'Gare $id', lat: 48.8 + km * 0.009, lon: 2.0 + 2 * 0.013662);
    const line = LineSummary(id: 'C09999', name: 'Z', mode: TransportMode.transilien, color: '00A88F', textColor: 'FFFFFF');
    final backend = standardBackend();
    backend.get('/api/v2/lines/C09999', LineDetail(line: line, directions: [
      LineDirection(directionId: 0, branches: [
        LineBranch(headsign: 'Gare D', tripCount: 100, stops: [at('A', 0), at('B', 1), at('C', 2), at('D', 10)]),
        LineBranch(headsign: 'Gare D', tripCount: 60, stops: [at('A', 0), at('D', 10)]),
        // A branch joining at C, from F through E
        LineBranch(headsign: 'Gare D', tripCount: 40, stops: [off('F', 6), off('E', 3), at('C', 2), at('D', 10)]),
      ]),
    ]).toJson());
    final now = DateTime.now().toUtc();
    backend.get('/api/v2/lines/C09999/vehicles', [
      Vehicle(id: 'direct', name: 'ZOPA', destination: 'Gare D', direction: 0, branch: 1, fromStopId: 'A', toStopId: 'D',
          toStopName: 'Gare D', progress: 0.5, expectedAt: now.add(const Duration(minutes: 4))).toJson(),
      Vehicle(id: 'joining', destination: 'Gare D', direction: 0, branch: 2, fromStopId: 'E', toStopId: 'C',
          toStopName: 'Gare C', progress: 0.5, expectedAt: now.add(const Duration(minutes: 1))).toJson(),
    ]);
    backend.get('/api/v2/lines/C09999/disruptions', []);
    await pumpApp(tester, backend);
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(routerProvider).push(Routes.line('C09999'));
    await settle(tester);

    // The direct train among the stops it runs past, with its destination
    expect(find.byWidgetPredicate((widget) => widget is LineVehicleTile && widget.vehicle.id == 'direct'), findsOneWidget);
    expect(find.text('→ Gare D'), findsNWidgets(2));
    // The branch folded, the train between it and the trunk still listed under it
    expect(find.text(currentL10n.lineBranchFrom('Gare F')), findsOneWidget);
    expect(find.text('Gare E'), findsNothing);
    expect(find.byWidgetPredicate((widget) => widget is LineVehicleTile && widget.vehicle.id == 'joining'), findsOneWidget);

    // Unfolded: its stops, the train still there once
    await tapOn(tester, find.text(currentL10n.lineBranchFrom('Gare F')));
    expect(find.text('Gare E'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is LineVehicleTile && widget.vehicle.id == 'joining'), findsOneWidget);

    await closeApp(tester);
  });
}
