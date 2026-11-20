import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/core/map/map_view.dart';
import 'package:website_app/features/home/map_stops.dart';

import '../../support/samples.dart';

void main() {
  const paris = LatLng(48.8584, 2.347);
  const phone = Size(412, 915);
  const noctilien = LineSummary(id: 'C09001', name: 'N16', mode: TransportMode.noctilien, color: 'D2D200', textColor: '000000');
  const bus275 = LineSummary(id: 'C02275', name: '275', mode: TransportMode.bus, color: 'FFC000', textColor: '000000');
  const tram3 = LineSummary(id: 'C03000', name: 'T3a', mode: TransportMode.tram, color: 'FF5A00');

  group('the part of the map shown', () {
    // The map beside the 420 px side panel of a 1920 × 994 window
    const desktop = Size(1499, 994);
    double metersAcross(double fromLon, double toLon, double lat) => (toLon - fromLon) * metersPerDegree * math.cos(lat * math.pi / 180);
    double metersUp(double fromLat, double toLat) => (toLat - fromLat) * metersPerDegree;

    test('the same scale whatever draws the map: MapLibre counts its zooms one less than flutter_map', () {
      final mapLibre = mapViewOf(paris, 15, phone, tileSize: 512);
      final flutterMap = mapViewOf(paris, 16, phone, tileSize: 256);
      expect(mapLibre.metersPerPixel, closeTo(1.57, 0.01));
      expect(flutterMap.metersPerPixel, closeTo(mapLibre.metersPerPixel, 1e-9));
    });

    test('on a phone, the part above the sheet: its middle higher than the map\'s, as wide, less high', () {
      final view = mapViewOf(paris, 15, phone, tileSize: 512, hidden: 400);
      final area = visibleArea(view);
      final meters = view.metersPerPixel;
      expect(metersUp(paris.latitude, area.center.latitude), closeTo(200 * meters, 0.01));
      expect(area.center.longitude, paris.longitude);
      expect(area.halfWidth, closeTo(206 * meters, 0.01));
      expect(area.halfHeight, closeTo(257.5 * meters, 0.01));
      // With a margin, a tenth more on each side
      final wider = visibleArea(view, margin: 0.1);
      expect(wider.halfWidth, closeTo(412 * 0.6 * meters, 0.01));
      expect(wider.halfHeight, closeTo(515 * 0.6 * meters, 0.01));
      // The sheet never hides more than the map
      expect(mapViewOf(paris, 15, phone, tileSize: 512, hidden: 2000).hidden, phone.height);
      expect(visibleArea(mapViewOf(paris, 15, phone, tileSize: 512)).center, paris);
    });

    test('on a wide window, the whole map beside the side panel, MapLibre and flutter_map alike', () {
      final mapLibre = visibleArea(mapViewOf(paris, 13, desktop, tileSize: 512));
      final flutterMap = visibleArea(mapViewOf(paris, 14, desktop, tileSize: 256));
      expect(mapLibre.center, paris);
      // About 9.4 × 6.3 km
      expect(mapLibre.halfWidth * 2, closeTo(9420, 20));
      expect(mapLibre.halfHeight * 2, closeTo(6250, 20));
      expect(flutterMap.halfWidth, closeTo(mapLibre.halfWidth, 1e-6));
      expect(flutterMap.halfHeight, closeTo(mapLibre.halfHeight, 1e-6));
    });

    test('its stops are asked once close enough, none further out', () {
      // A neighbourhood on the screen
      expect(mapStopsQuery(mapViewOf(paris, 16, phone, tileSize: 512)), isNotNull);
      expect(mapStopsQuery(mapViewOf(paris, 15, phone, tileSize: 512)), isNotNull);
      // A part of the town: their dots, from the zoom they show at
      expect(mapStopsQuery(mapViewOf(paris, PinZoom.stopDotZoom, phone, tileSize: 512)), isNotNull);
      // The whole town: the dots would cover the map
      expect(mapStopsQuery(mapViewOf(paris, PinZoom.stopDotZoom - 0.2, phone, tileSize: 512)), isNull);
      expect(mapStopsQuery(mapViewOf(paris, 11, phone, tileSize: 512)), isNull);
      // Not drawn yet
      expect(mapStopsQuery(null), isNull);
    });

    test('on a phone, the box of the part above the sheet with its margin', () {
      final view = mapViewOf(paris, 15, phone, tileSize: 512, hidden: 400);
      final box = mapStopsQuery(view)!;
      final area = visibleArea(view, margin: mapStopsMargin);
      final middle = (lat: (box.minLat + box.maxLat) / 2, lon: (box.minLon + box.maxLon) / 2);
      // Its middle above the map's, within the rounding
      expect(metersUp(area.center.latitude, middle.lat).abs(), lessThan(60));
      expect(middle.lat, greaterThan(paris.latitude));
      // At least the visible part and its margin, at most 200 m more on each side
      final width = metersAcross(box.minLon, box.maxLon, middle.lat);
      final height = metersUp(box.minLat, box.maxLat);
      expect(width, inInclusiveRange(area.halfWidth * 2, area.halfWidth * 2 + 400));
      expect(height, inInclusiveRange(area.halfHeight * 2, area.halfHeight * 2 + 400));
      // Not what the sheet hides: its bottom above the map's
      expect(box.minLat, greaterThan(paris.latitude - phone.height / 2 * view.metersPerPixel / metersPerDegree));
    });

    test('on a wide window, the whole map, not a disc 2 km around its middle', () {
      final view = mapViewOf(paris, 13, desktop, tileSize: 512);
      final box = mapStopsQuery(view)!;
      final width = metersAcross(box.minLon, box.maxLon, paris.latitude);
      final height = metersUp(box.minLat, box.maxLat);
      // 9.4 × 6.3 km and a tenth more on each side
      expect(width, inInclusiveRange(9420 * 1.2, 9420 * 1.2 + 400));
      expect(height, inInclusiveRange(6250 * 1.2, 6250 * 1.2 + 400));
      expect(box.minLat, lessThan(paris.latitude));
      expect(box.maxLat, greaterThan(paris.latitude));
      // flutter_map's zoom one more: the same box
      expect(mapStopsQuery(mapViewOf(paris, 14, desktop, tileSize: 256)), box);
    });

    test('a small move of the map asks nothing new, a very wide screen no more than the backend takes', () {
      final view = mapViewOf(paris, 16, phone, tileSize: 512);
      final moved = mapViewOf(const LatLng(48.8582, 2.3472), 16, phone, tileSize: 512);
      expect(mapStopsQuery(moved), mapStopsQuery(view));
      // An 8K screen at the zoom the dots show from: 15 km each side at most, under half a degree
      final huge = mapStopsQuery(mapViewOf(paris, PinZoom.stopDotZoom, const Size(7680, 4320), tileSize: 512))!;
      expect(huge.maxLon - huge.minLon, lessThan(0.5));
      expect(metersAcross(huge.minLon, huge.maxLon, paris.latitude), closeTo(30000, 200));
    });
  });

  test("a marker's lines: trains, metro, tram, bus then night bus, numbers in order, each once", () {
    final lines = markerLines([noctilien, bus275, bus38, metro1, tram3, rerA, metro1]);
    expect([for (final line in lines) line.name], ['A', '1', 'T3a', '38', '275', 'N16']);
  });

  group('the stops on the map', () {
    Future<List<MapPin>> pins(
      WidgetTester tester,
      List<StopAreaSummary> stops, {
      bool Function(TransportMode mode)? shows,
      Map<String, DisruptionSeverity> severities = const {},
    }) async {
      late List<MapPin> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          result = stopPins(context, stops, shows: shows, severities: severities);
          return const SizedBox();
        }),
      ));
      // The markers with their lines; their dots from afar apart
      return [for (final pin in result) if (pin.zoom == PinZoom.stopLines) pin];
    }

    testWidgets('progressively as the map zooms in: nothing from afar, a dot, then the marker with its lines',
        (tester) async {
      late List<MapPin> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          result = stopPins(context, [chatelet, gareDeLyon]);
          return const SizedBox();
        }),
      ));
      // Each stop its dot, then its marker
      expect([for (final pin in result) (pin.label, pin.zoom)], [
        ('Châtelet', PinZoom.stopDot),
        ('Châtelet', PinZoom.stopLines),
        ('Gare de Lyon', PinZoom.stopDot),
        ('Gare de Lyon', PinZoom.stopLines),
      ]);
      List<String?> shownAt(double zoom) => [for (final pin in result) if (pin.shownAt(zoom)) pin.child.runtimeType.toString()];
      // The whole town: nothing, the stops of a closer view left behind gone too
      expect(shownAt(11), isEmpty);
      expect(shownAt(12.9), isEmpty);
      // A part of the town: dots
      expect(shownAt(13), ['StopDot', 'StopDot']);
      expect(shownAt(13.9), ['StopDot', 'StopDot']);
      // A neighbourhood: the markers with their lines instead
      expect(shownAt(14), ['StopMarker', 'StopMarker']);
      expect(shownAt(18), ['StopMarker', 'StopMarker']);
      // One image for every dot, tapped to open its stop, named for screen readers
      final dot = result.first;
      expect(dot.image, result[2].image);
      expect(dot.onTap, isNotNull);
      expect(dot.childSize, StopDot.box);
    });

    testWidgets("on a stop's page, its own marker at every zoom, the others' as anywhere else", (tester) async {
      late List<MapPin> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          result = stopPins(context, [chatelet, gareDeLyon], opened: gareDeLyon.id);
          return const SizedBox();
        }),
      ));
      expect([for (final pin in result) (pin.label, pin.zoom)], [
        ('Châtelet', PinZoom.stopDot),
        ('Châtelet', PinZoom.stopLines),
        ('Gare de Lyon', PinZoom.any),
      ]);
      expect(result.last.onTap, isNull);
    });

    testWidgets('a stop drawn in its box from afar: a small dot', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Center(child: SizedBox(width: 20, height: 20, child: StopDot()))));
      expect(tester.getSize(find.byType(Container)), const Size.square(StopDot.size));
      expect(tester.takeException(), isNull);
    });

    testWidgets('one marker per stop with its lines, standing on it, named for screen readers', (tester) async {
      final result = await pins(tester, [chatelet, gareDeLyon]);
      expect(result, hasLength(2));
      final marker = result.first;
      expect(marker.label, 'Châtelet');
      expect(marker.point, const LatLng(48.8584, 2.347));
      expect(marker.above, isTrue);
      expect(marker.onTap, isNotNull);
      expect((marker.child! as StopMarker).lines, [rerA, metro1, bus38]);
    });

    testWidgets('a stop given twice (around the user, and in the part shown) has one marker, drawn last', (tester) async {
      final result = await pins(tester, [chatelet, gareDeLyon, chatelet]);
      expect([for (final pin in result) pin.label], ['Gare de Lyon', 'Châtelet']);
    });

    testWidgets('the same lines draw the same image, another one with an interrupted line', (tester) async {
      final result = await pins(tester, [gareDeLyon, nation]);
      expect(result.first.image, result.last.image);
      final stopped = await pins(tester, [gareDeLyon], severities: {metro1.id: DisruptionSeverity.blocking});
      expect(stopped.single.image, isNot(result.first.image));
      expect((stopped.single.child! as StopMarker).interrupted, {metro1.id});
    });

    testWidgets('three badges at most, the others counted', (tester) async {
      final big = chatelet.copyWith(lines: [metro1, rerA, bus38, bus275, noctilien]);
      final marker = (await pins(tester, [big])).single;
      final child = marker.child! as StopMarker;
      expect(child.lines, [rerA, metro1, bus38]);
      expect(child.more, 2);
      // Drawn in its box: the badges, `+2`, the point under them
      await tester.pumpWidget(MaterialApp(
        home: Center(child: SizedBox.fromSize(size: marker.childSize, child: Center(child: child))),
      ));
      expect(find.text('+2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a big station's marker holds its count of two digits (Châtelet: +27)", (tester) async {
      final lines = [
        rerA,
        metro1,
        tram3,
        for (var number = 20; number < 47; number++)
          LineSummary(id: 'C0$number', name: '$number', mode: TransportMode.bus, color: 'FFC000', textColor: '000000'),
      ];
      final marker = (await pins(tester, [chatelet.copyWith(lines: lines)])).single;
      final child = marker.child! as StopMarker;
      expect(child.more, 27);
      await tester.pumpWidget(MaterialApp(
        home: Center(child: SizedBox.fromSize(size: marker.childSize, child: Center(child: child))),
      ));
      expect(find.text('+27'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a kind of departures chosen: the stops with such lines, those lines only', (tester) async {
      final busStop = nation.copyWith(lines: [bus38]);
      final result = await pins(tester, [chatelet, gareDeLyon, busStop], shows: (mode) => mode == TransportMode.bus);
      expect([for (final pin in result) pin.label], ['Châtelet', 'Nation']);
      expect((result.first.child! as StopMarker).lines, [bus38]);
    });
  });
}
