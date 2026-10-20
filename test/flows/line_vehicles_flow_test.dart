import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/widgets/line_badge.dart';
import 'package:website_app/features/lines/line_vehicles.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/samples.dart';
import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// The vehicles of a line on its page: pointing the way they go, gliding along, late or stale
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
    ]);
    await pumpApp(tester, backend);

    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.byWidgetPredicate((widget) => widget is LineBadge && widget.line.id == metro1.id));

    // On the map with a pointer, on the stop list without
    final onMap = find.byWidgetPredicate((widget) => widget is VehicleMarker && widget.heading != null);
    expect(onMap, findsNWidgets(2));
    final moving = tester.widget<VehicleMarker>(onMap.first);
    expect(moving.punctuality, Punctuality.late);
    // Châtelet → Gare de Lyon goes south-east
    expect(moving.heading, inInclusiveRange(90, 180));
    expect(tester.widgetList<VehicleMarker>(find.byType(VehicleMarker)).where((marker) => marker.stale), hasLength(2));

    // No trail behind them: the line's branches only
    final paths = tester.widgetList<fm.PolylineLayer>(find.byType(fm.PolylineLayer)).expand((layer) => layer.polylines);
    expect(paths.where((polyline) => polyline.strokeWidth > 6), isEmpty);

    // It moves on between two fetches, every second
    final before = tester.getCenter(onMap.first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1500)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getCenter(onMap.first), isNot(before));

    // Followed on the map from its sheet, until stopped
    await tapOn(tester, onMap.first);
    await tapOn(tester, find.text(currentL10n.vehicleFollow));
    expect(find.text(currentL10n.vehicleFollowing), findsOneWidget);
    await tapOn(tester, find.byTooltip(currentL10n.vehicleStopFollowing));
    expect(find.text(currentL10n.vehicleFollowing), findsNothing);

    await closeApp(tester);
  });
}
