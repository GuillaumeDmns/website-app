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

    final dots = layers.single as PolylineLayer;
    expect(dots.getLayout(), containsPair('line-cap', 'round'));
    // Dashes of no length: only their round ends, as wide as the line, one every two widths
    expect(dots.getPaint(), containsPair('line-dasharray', [0, 2]));
    expect(dots.color, const Color(0xFF3C4654));
  });

  test('a ride is solid, on a light edge as faded as it', () {
    final faded = const Color(0xFFFFCD00).withValues(alpha: 0.3);
    final layers = mapLibrePathLayers(MapPath(points: points, color: faded, width: 6));

    expect(layers, hasLength(2));
    final [edge, line] = layers.cast<PolylineLayer>();
    expect(edge.color, Colors.white.withValues(alpha: faded.a));
    expect(edge.width, 9);
    expect(line.color, faded);
    expect(line.dashArray, isNull);
  });

  test('pins as the map draws them: their image once there, a callout standing on its place, turned ones apart', () {
    const at = LatLng(48.8584, 2.3470);
    final pins = [
      const MapPin(point: at, color: Color(0xFF0A8F4E), label: 'Châtelet'),
      const MapPin(point: at, color: Color(0xFF0A8F4E), above: true, image: 'callout-Rue Cantin', child: SizedBox()),
      const MapPin(point: at, color: Color(0xFF1F2933), rotation: 90, image: 'vehicle-pointer', child: SizedBox()),
      const MapPin(point: at, color: Color(0xFF0A8F4E), image: 'not-drawn-yet', child: SizedBox()),
      const MapPin(point: at, color: Color(0xFF233A7E), closeUp: true, image: 'access-3', child: SizedBox()),
    ];
    final data = jsonDecode(pinsGeoJson(pins, image: (pin) => pinImageName(pin, Colors.white), ready: (id) => id != 'not-drawn-yet'))
        as Map<String, Object?>;
    final features = [for (final feature in data['features']! as List) (feature as Map)['properties'] as Map];

    // Not there yet: left out until its image is on the map; the others keep their place in the list
    expect([for (final feature in features) feature['pin']], [0, 1, 2, 4]);
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

  test('images drawn at the screen density are shown at their size on every platform', () {
    expect(overlayIconSize(2.625, web: true), 1);
    expect(overlayIconSize(2.625, web: false), closeTo(1 / 2.625, 1e-9));
  });

  test("the overlay's layers from the bottom: the circle, the close-up pins, the turned pins, the pins, the heading, the dot",
      () {
    final layers = overlayStyleLayers(iconSize: 0.5);
    expect([for (final layer in layers) layer.id], [
      MapLibreOverlay.accuracyLayer,
      MapLibreOverlay.closeUpPinsLayer,
      MapLibreOverlay.turnedPinsLayer,
      MapLibreOverlay.pinsLayer,
      MapLibreOverlay.headingLayer,
      MapLibreOverlay.userLayer,
    ]);
    // A station's ways in and out from a few streets on the screen; the other pins at any zoom, apart from them
    final closeUp = layers[1] as SymbolStyleLayer;
    expect(closeUp.minZoom, MapPin.closeUpZoom);
    expect(closeUp.filter.toString(), contains('closeUp'));
    expect((layers[3] as SymbolStyleLayer).minZoom, 0);
    expect(layers[3].filter.toString(), contains('closeUp'));
    final turned = layers[2] as SymbolStyleLayer;
    expect(turned.layout, containsPair('icon-rotation-alignment', 'map'));
    expect(layers[3].layout, containsPair('icon-rotation-alignment', 'viewport'));
    expect(layers[3].layout, containsPair('icon-size', 0.5));
    expect(layers[3].layout, containsPair('icon-allow-overlap', true));
    // The heading lies on the map; the circle too
    expect(layers[4].layout, containsPair('icon-pitch-alignment', 'map'));
    expect(layers[0].paint, containsPair('circle-pitch-alignment', 'map'));
  });
}
