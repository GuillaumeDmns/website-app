import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart';
import 'package:website_app/core/map/map_overlay.dart';
import 'package:website_app/core/map/maplibre_main_map.dart';

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
}
