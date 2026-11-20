import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// What the map shows once the user stopped moving it: the middle of the map (of the whole widget, whatever the
/// camera's padding), how many meters a logical pixel covers there (the same scale whatever draws the map: MapLibre
/// and flutter_map don't count their zooms alike), its size in logical pixels and how much of its bottom the panel
/// hides (narrow layout's sheet; nothing beside the side panel of the wide layout, which the map doesn't go under)
typedef MapView = ({LatLng center, double metersPerPixel, Size size, double hidden});

/// The [MapView] of a map of [size] whose middle is [center] at [zoom], its world [tileSize] × 2^zoom pixels wide
/// (MapLibre's tiles are 512 px, flutter_map's 256), the bottom [hidden] px behind the panel
MapView mapViewOf(LatLng center, double zoom, Size size, {required double tileSize, double hidden = 0}) {
  const equator = 40075016.686;
  final metersPerPixel = equator * math.cos(center.latitudeInRad) / (tileSize * math.pow(2, zoom));
  return (center: center, metersPerPixel: metersPerPixel, size: size, hidden: hidden.clamp(0, size.height));
}

/// Meters in a degree of latitude (and of longitude at the equator)
const metersPerDegree = 111320.0;

/// The part of [view] the user sees, the map above the panel, [margin] of its width and height wider on each side:
/// its middle and how far its sides are from it, in meters
({LatLng center, double halfWidth, double halfHeight}) visibleArea(MapView view, {double margin = 0}) {
  final width = view.size.width;
  final height = view.size.height - view.hidden;
  // Above the panel: its middle half the hidden part higher than the map's
  final up = view.hidden / 2 * view.metersPerPixel;
  return (
    center: LatLng(view.center.latitude + up / metersPerDegree, view.center.longitude),
    halfWidth: width * (0.5 + margin) * view.metersPerPixel,
    halfHeight: height * (0.5 + margin) * view.metersPerPixel,
  );
}

class MapViewController extends Notifier<MapView?> {
  @override
  MapView? build() => null;

  void update(MapView view) => state = view;
}

/// What the map shows, null until it has been drawn: given by the map once its camera rests
final mapViewProvider = NotifierProvider<MapViewController, MapView?>(MapViewController.new);
