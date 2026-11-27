import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/app/panel_scope.dart';
import 'package:website_app/app/router.dart';
import 'package:website_app/app/routes.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/core/widgets/line_badge.dart';
import 'package:website_app/features/lines/line_vehicles.dart';
import 'package:website_app/features/lines/widgets/line_stop_tile.dart';
import 'package:website_app/features/lines/widgets/vehicle_follow_card.dart';
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

    // On the stop list, on the rail between the stops (no row of their own), how many there are above them; the
    // other direction's pointing up the list
    expect(find.textContaining('3 trains'), findsOneWidget);
    expect(find.byType(LineVehicleMark), findsNWidgets(3));
    Finder mark(String id) => find.byWidgetPredicate((widget) => widget is LineVehicleMark && widget.vehicles.any((vehicle) => vehicle.id == id));
    LineVehicleMark markOf(String id) => tester.widget<LineVehicleMark>(mark(id));
    expect([for (final id in ['moving', 'stale', 'back']) markOf(id).reverse], [false, false, true]);
    expect([for (final id in ['moving', 'stale', 'back']) markOf(id).vehicles.length], [1, 1, 1]);
    // Châtelet → Gare de Lyon, between their dots
    double dotY(String name) => tester.getCenter(find.widgetWithText(LineStopTile, name)).dy;
    expect(tester.getCenter(mark('moving')).dy, inExclusiveRange(dotY('Châtelet'), dotY('Gare de Lyon')));
    // Both ways between Gare de Lyon and Nation: back to back, each against the stop it goes to
    final back = tester.getRect(mark('back'));
    final stale = tester.getRect(mark('stale'));
    expect(back.center.dy, lessThan(stale.center.dy));
    expect(back.center.dy - dotY('Gare de Lyon'), lessThan(dotY('Nation') - back.center.dy));
    expect(dotY('Nation') - stale.center.dy, lessThan(stale.center.dy - dotY('Gare de Lyon')));
    expect(back.overlaps(stale), isFalse);
    // Its delay in its sheet, opened from the list (and over it on the map)
    await tapOn(tester, mark('moving'));
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining(currentL10n.goMinutesLate(2))), findsOneWidget);
    await tapOn(tester, find.byTooltip(currentL10n.close));

    // Both ways, a metro's directions run side by side: one path, the other direction's only where it serves other
    // stops (a bus's two ways are both drawn, often by other streets); one direction, its own
    Iterable<fm.Polyline> linePaths() => tester
        .widgetList<fm.PolylineLayer>(find.byType(fm.PolylineLayer))
        .expand((layer) => layer.polylines)
        .where((polyline) => polyline.strokeWidth == 6);
    expect(linePaths(), hasLength(1));

    // One direction: its vehicles listed, the other one's faded on the map
    await tapOn(tester, find.text(currentL10n.towards('Nation')));
    expect(linePaths(), hasLength(1));
    expect(find.textContaining('2 trains vers Nation'), findsOneWidget);
    expect(find.byType(LineVehicleMark), findsNWidgets(2));
    expect(tester.widgetList<VehicleCapsule>(onMap).where((capsule) => capsule.faded), hasLength(1));
    await tapOn(tester, find.text(currentL10n.lineBothDirections));
    expect(find.byType(LineVehicleMark), findsNWidgets(3));

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

    // Followed on the map from its sheet: the page is its card alone, the sheet lowered to it, the map above; still
    // selected, until stopped
    double sheetTop() =>
        tester.getTopLeft(find.byWidgetPredicate((widget) => widget is PanelSheetScope)).dy;
    final sheetBefore = sheetTop();
    await tapOn(tester, find.text(currentL10n.vehicleFollow));
    expect(find.byType(VehicleFollowCard), findsOneWidget);
    expect(find.byType(LineStopTile), findsNothing);
    expect(selected(), isTrue);
    expect(find.text(currentL10n.vehicleNextStop), findsOneWidget);
    expect(find.descendant(of: find.byType(VehicleFollowCard), matching: find.text('Gare de Lyon')), findsOneWidget);
    expect(find.descendant(of: find.byType(VehicleFollowCard), matching: find.text(currentL10n.goMinutesLate(2))), findsOneWidget);
    expect(sheetTop(), greaterThan(sheetBefore + 100));
    // Its stops in its sheet
    await tapOn(tester, find.text(currentL10n.vehicleAllStops));
    expect(find.text(currentL10n.vehicleFollow), findsOneWidget);
    await tapOn(tester, find.byTooltip(currentL10n.close));
    await tapOn(tester, find.text(currentL10n.followStop));
    expect(find.byType(VehicleFollowCard), findsNothing);
    expect(find.byType(LineStopTile), findsWidgets);
    expect(selected(), isFalse);
    expect(find.byType(VehicleCallout), findsNothing);
    expect(sheetTop(), moreOrLessEquals(sheetBefore, epsilon: 2));

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
        // Another way from A to C, by W
        LineBranch(headsign: 'Gare D', tripCount: 20, stops: [at('A', 0), off('W', 1), at('C', 2), at('D', 10)]),
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

    Finder mark(String id) => find.byWidgetPredicate((widget) => widget is LineVehicleMark && widget.vehicles.any((vehicle) => vehicle.id == id));
    double rowY(Finder row) => tester.getCenter(row).dy;
    // The direct train on the rail among the stops it runs past: halfway from A to D, past C (2 km of 10)
    expect(mark('direct'), findsOneWidget);
    expect(rowY(mark('direct')), greaterThan(rowY(find.widgetWithText(LineStopTile, 'Gare C'))));
    // The branch folded, the train between it and the trunk on its row
    final folded = find.widgetWithText(LineSpurTile, currentL10n.lineBranchFrom('Gare F'));
    expect(folded, findsOneWidget);
    expect(find.text('Gare E'), findsNothing);
    expect(mark('joining'), findsOneWidget);
    expect(rowY(mark('joining')), moreOrLessEquals(rowY(folded), epsilon: 1));

    // Unfolded: its stops, the train still there once, between E and C
    await tapOn(tester, find.text(currentL10n.lineBranchFrom('Gare F')));
    expect(find.text('Gare E'), findsOneWidget);
    expect(mark('joining'), findsOneWidget);
    expect(rowY(mark('joining')), greaterThan(rowY(find.widgetWithText(LineStopTile, 'Gare E'))));

    // Another way between two stops: folded as a closed loop; unfolded, its lane runs on until the stop it rejoins
    LineStopTile stopTile(String name) =>
        tester.widget<LineStopTile>(find.byWidgetPredicate((widget) => widget is LineStopTile && widget.stop.name == name));
    expect(tester.widget<LineSpurTile>(find.widgetWithText(LineSpurTile, currentL10n.lineBranchVia('Gare W'))).loop, isTrue);
    expect(stopTile('Gare C').rail.joinFrom, isEmpty);
    await tapOn(tester, find.text(currentL10n.lineBranchVia('Gare W')));
    expect(find.text('Gare W'), findsOneWidget);
    expect(stopTile('Gare B').rail.passing, contains(1));
    expect(stopTile('Gare C').rail.joinFrom, {1});

    await closeApp(tester);
  });

  testWidgets('several vehicles the same way between two stops: one mark, how many on it, a choice when tapped', (tester) async {
    final backend = standardBackend();
    final now = DateTime.now().toUtc();
    Vehicle between(String id, double progress, int seconds) => Vehicle(
          id: id,
          destination: 'Nation',
          direction: 0,
          branch: 0,
          fromStopId: chatelet.id,
          toStopId: gareDeLyon.id,
          toStopName: 'Gare de Lyon',
          progress: progress,
          expectedAt: now.add(Duration(seconds: seconds)),
        );
    backend.get('/api/v2/lines/C01371/vehicles', [between('first', 0.8, 30).toJson(), between('second', 0.2, 150).toJson()]);
    await pumpApp(tester, backend);
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(routerProvider).push(Routes.line(metro1.id));
    await settle(tester);

    final marks = tester.widgetList<LineVehicleMark>(find.byType(LineVehicleMark)).toList();
    expect(marks, hasLength(1));
    expect(marks.single.vehicles.map((vehicle) => vehicle.id), unorderedEquals(['first', 'second']));
    expect(find.descendant(of: find.byType(LineVehicleMark), matching: find.text('2')), findsOneWidget);

    // A tap: which one, then its sheet
    await tapOn(tester, find.byType(LineVehicleMark));
    expect(find.text(currentL10n.towards('Nation')), findsNWidgets(3));
    await tapOn(tester, find.textContaining('Gare de Lyon · 3 min'));
    expect(find.text(currentL10n.vehicleFollow), findsOneWidget);

    await closeApp(tester);
  });
}
