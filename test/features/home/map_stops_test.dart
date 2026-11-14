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
    test('the same scale whatever draws the map: MapLibre counts its zooms one less than flutter_map', () {
      final mapLibre = mapViewOf(paris, 15, phone, tileSize: 512);
      final flutterMap = mapViewOf(paris, 16, phone, tileSize: 256);
      expect(mapLibre.metersPerPixel, closeTo(1.57, 0.01));
      expect(flutterMap.metersPerPixel, closeTo(mapLibre.metersPerPixel, 1e-9));
      // To its corners: half its diagonal
      expect(mapLibre.radius, closeTo(1.57 * 1003.5 / 2, 2));
    });

    test('its stops are asked once close enough, none further out', () {
      // A neighbourhood on the screen
      final close = mapStopsQuery(mapViewOf(paris, 16, phone, tileSize: 512));
      expect(close, (lat: 48.858, lon: 2.347, radius: 500));
      expect(mapStopsQuery(mapViewOf(paris, 15, phone, tileSize: 512)), isNotNull);
      // A whole part of the town: the markers would cover the map
      expect(mapStopsQuery(mapViewOf(paris, 14, phone, tileSize: 512)), isNull);
      // Not drawn yet
      expect(mapStopsQuery(null), isNull);
    });

    test('a small move of the map asks nothing new, a wide screen never more than the backend looks around', () {
      final view = mapViewOf(paris, 16, phone, tileSize: 512);
      final moved = mapViewOf(const LatLng(48.8582, 2.3472), 16, phone, tileSize: 512);
      expect(mapStopsQuery(moved), mapStopsQuery(view));
      expect(mapStopsQuery(mapViewOf(paris, 15, const Size(3840, 2160), tileSize: 512))?.radius, 2000);
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
      return result;
    }

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

    testWidgets('a kind of departures chosen: the stops with such lines, those lines only', (tester) async {
      final busStop = nation.copyWith(lines: [bus38]);
      final result = await pins(tester, [chatelet, gareDeLyon, busStop], shows: (mode) => mode == TransportMode.bus);
      expect([for (final pin in result) pin.label], ['Châtelet', 'Nation']);
      expect((result.first.child! as StopMarker).lines, [bus38]);
    });
  });
}
