import 'dart:convert';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/core/map/maplibre_overlay.dart';

void main() {
  const points = [LatLng(48.8584, 2.3470), LatLng(48.8611, 2.3372)];

  test('a walk is round dots on the map itself, nothing under them', () {
    final layers = mapLibrePathLayers(const MapPath(points: points, color: Color(0xFF3C4654), dotted: true));

    final dots = layers.single;
    expect(dots.layout, containsPair('line-cap', 'round'));
    // Dashes of no length: only their round ends, as wide as the line, one every two widths
    expect(dots.paint, containsPair('line-dasharray', [0, 2]));
    expect(dots.paint, containsPair('line-color', styleColor(const Color(0xFF3C4654))));
  });

  test('a ride is solid, on a light edge as faded as it', () {
    final faded = const Color(0xFFFFCD00).withValues(alpha: 0.3);
    final layers = mapLibrePathLayers(MapPath(points: points, color: faded, width: 6));

    expect(layers, hasLength(2));
    final [edge, line] = layers;
    expect(edge.paint, containsPair('line-color', styleColor(Colors.white.withValues(alpha: faded.a))));
    expect(edge.paint, containsPair('line-width', 9));
    expect(line.paint, containsPair('line-color', styleColor(faded)));
    expect(line.paint.containsKey('line-dasharray'), isFalse);
  });

  test("a line's branches are one path: every edge under every line, rounded where they meet", () {
    const branch = [LatLng(48.8584, 2.3470), LatLng(48.8500, 2.3300)];
    final path = MapPath(points: points, parts: const [branch], color: const Color(0xFFFFCD00), width: 6);

    final lines = (jsonDecode(pathGeoJson(path)) as Map<String, dynamic>)['features'] as List<dynamic>;
    expect(lines, hasLength(2));
    // One layer for the edges, one for the lines: none drawn over another one's
    final [edge, line] = mapLibrePathLayers(path);
    expect(edge.layout, containsPair('line-join', 'round'));
    expect(line.layout, containsPair('line-cap', 'round'));
    expect(path.sameAs(MapPath(points: points, parts: const [branch], color: const Color(0xFFFFCD00), width: 6)), isTrue);
    expect(path.sameAs(MapPath(points: points, color: const Color(0xFFFFCD00), width: 6)), isFalse);
  });

  test('pins as the map draws them: their image once there, a callout standing on its place, turned ones apart', () {
    const at = LatLng(48.8584, 2.3470);
    final pins = [
      const MapPin(point: at, color: Color(0xFF0A8F4E), label: 'Châtelet'),
      const MapPin(point: at, color: Color(0xFF0A8F4E), above: true, image: 'callout-Rue Cantin', child: SizedBox()),
      const MapPin(point: at, color: Color(0xFF1F2933), rotation: 90, image: 'vehicle-pointer', child: SizedBox()),
      const MapPin(point: at, color: Color(0xFF0A8F4E), image: 'not-drawn-yet', child: SizedBox()),
      const MapPin(point: at, color: Color(0xFF233A7E), closeUp: true, image: 'access-3', child: SizedBox()),
      const MapPin(point: at, color: Color(0xFF101215), zoom: PinZoom.stopDot, image: 'stop-dot', child: SizedBox()),
    ];
    final data = jsonDecode(pinsGeoJson(pins, image: (pin) => pinImageName(pin, Colors.white), ready: (id) => id != 'not-drawn-yet'))
        as Map<String, Object?>;
    final features = [for (final feature in data['features']! as List) (feature as Map)['properties'] as Map];

    // Not there yet: left out until its image is on the map; the others keep their place in the list
    expect([for (final feature in features) feature['pin']], [0, 1, 2, 4, 5]);
    expect(features[0]['image'], startsWith('dot-'));
    expect(features[0]['anchor'], 'center');
    // A callout by its bottom, its arrow's tip on the place
    expect(features[1]['anchor'], 'bottom');
    expect(features[2], containsPair('rotate', 90));
    expect(features[2]['turned'], isTrue);
    expect(features[0]['turned'], isFalse);
    // A station's way in or out, for the layer shown close up only
    expect(features[3]['closeUp'], isTrue);
    expect(features[0]['closeUp'], isFalse);
    // For the layer of the zooms it shows at
    expect(features[0]['zoom'], 'any');
    expect(features[4]['zoom'], 'stopDot');
    expect((data['features']! as List).first, containsPair('geometry', {'type': 'Point', 'coordinates': [2.3470, 48.8584]}));
  });

  test("a dot's image is named after its look, the same look the same image", () {
    const pin = MapPin(point: LatLng(48.8584, 2.3470), color: Color(0xFF0A8F4E), icon: Icons.directions_transit, size: 22);
    expect(pinImageName(pin, Colors.white), pinImageName(pin, Colors.white));
    expect(pinImageName(pin, Colors.white), isNot(pinImageName(pin, Colors.black)));
    expect(pinImageName(const MapPin(point: LatLng(0, 0), color: Colors.red, image: 'badge', child: SizedBox()), Colors.white), 'badge');
  });

  test('the user dot, its heading lying under it, the circle of its accuracy doubled at each zoom level', () {
    const at = LatLng(60, 2);
    final user = jsonDecode(userGeoJson(at, dot: 'dot', heading: 30, cone: 'cone')) as Map<String, Object?>;
    final kinds = [for (final feature in user['features']! as List) ((feature as Map)['properties'] as Map)['kind']];
    expect(kinds, ['heading', 'dot']);
    // Nothing until the dot's image is there
    expect((jsonDecode(userGeoJson(at, heading: 30, cone: 'cone')) as Map)['features'], hasLength(1));
    expect((jsonDecode(userGeoJson(null, dot: 'dot')) as Map)['features'], isEmpty);

    final circle = jsonDecode(accuracyGeoJson(at, 30)) as Map<String, Object?>;
    final r0 = (((circle['features']! as List).single as Map)['properties'] as Map)['r0'] as num;
    // MapLibre at zoom 18, 60° north: 30 m are 201 px
    expect(r0 * math.pow(2, 18), closeTo(201, 0.5));
    expect((jsonDecode(accuracyGeoJson(at, null)) as Map)['features'], isEmpty);
  });

  test(
      "the overlay's layers from the bottom: the circle, the close-up pins, the stops' dots, the Vélib "
      "stations, the pins, the turned pins (a line's vehicles, over its stops), the stops' lines, the heading, the dot", () {
    final layers = overlayStyleLayers();
    Map<String, Object?> layout(StyleLayer layer) => layer.toJson()['layout']! as Map<String, Object?>;
    expect([for (final layer in layers) layer.id], [
      MapLibreOverlay.accuracyLayer,
      MapLibreOverlay.closeUpPinsLayer,
      MapLibreOverlay.stopDotsLayer,
      MapLibreOverlay.closePinsLayer,
      MapLibreOverlay.pinsLayer,
      MapLibreOverlay.turnedPinsLayer,
      MapLibreOverlay.stopLinesLayer,
      MapLibreOverlay.headingLayer,
      MapLibreOverlay.userLayer,
    ]);
    // A station's ways in and out from a few streets on the screen; the other pins at any zoom, apart from them
    final closeUp = layers[1] as SymbolStyleLayer;
    expect(closeUp.minZoom, MapPin.closeUpZoom);
    expect(closeUp.filter.toString(), contains('closeUp'));
    expect((layers[4] as SymbolStyleLayer).minZoom, 0);
    expect(layers[4].filter.toString(), contains('closeUp'));
    // The stops, by the map itself as it zooms: their dots from a part of the town until their lines show, nothing
    // further out
    final dots = layers[2] as SymbolStyleLayer;
    expect((dots.minZoom, dots.maxZoom), (PinZoom.stopDotZoom, PinZoom.stopLinesZoom));
    expect(dots.filter.toString(), contains('stopDot'));
    final lines = layers[6] as SymbolStyleLayer;
    expect((lines.minZoom, lines.maxZoom), (PinZoom.stopLinesZoom, 24));
    expect(lines.filter.toString(), contains('stopLines'));
    // The Vélib stations around from a neighbourhood on the screen, under the stops' lines
    final close = layers[3] as SymbolStyleLayer;
    expect((close.minZoom, close.maxZoom), (PinZoom.stopLinesZoom, 24));
    expect(close.filter.toString(), contains('close'));
    expect(layers[4].filter.toString(), contains('any'));
    expect(layers[5], isA<SymbolStyleLayer>());
    expect(layout(layers[5]), containsPair('icon-rotation-alignment', 'map'));
    // The vehicles smaller further out, where a whole line is on the screen
    expect(layout(layers[5]), containsPair('icon-size', turnedPinSize));
    expect(layout(layers[4]), containsPair('icon-rotation-alignment', 'viewport'));
    // Images made at the screen's density and the map told so: shown at their size, no icon-size
    expect(layout(layers[4]).containsKey('icon-size'), isFalse);
    expect(layout(layers[4]), containsPair('icon-allow-overlap', true));
    // The heading lies on the map; the circle too
    expect(layout(layers[7]), containsPair('icon-pitch-alignment', 'map'));
    expect(layers[0].toJson()['paint'], containsPair('circle-pitch-alignment', 'map'));
  });
}
