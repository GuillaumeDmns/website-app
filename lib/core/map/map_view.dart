import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// What the map shows once the user stopped moving it: its center, how many meters a logical pixel covers there (the
/// same scale whatever draws the map: MapLibre and flutter_map don't count their zooms alike) and how far its corners
/// are from the center, in meters
typedef MapView = ({LatLng center, double metersPerPixel, double radius});

/// The [MapView] of a map of [size] centered on [center] at [zoom], its world [tileSize] × 2^zoom pixels wide
/// (MapLibre's tiles are 512 px, flutter_map's 256)
MapView mapViewOf(LatLng center, double zoom, Size size, {required double tileSize}) {
  const equator = 40075016.686;
  final metersPerPixel = equator * math.cos(center.latitudeInRad) / (tileSize * math.pow(2, zoom));
  return (
    center: center,
    metersPerPixel: metersPerPixel,
    radius: metersPerPixel * math.sqrt(size.width * size.width + size.height * size.height) / 2,
  );
}

class MapViewController extends Notifier<MapView?> {
  @override
  MapView? build() => null;

  void update(MapView view) => state = view;
}

/// What the map shows, null until it has been drawn: given by the map once its camera rests
final mapViewProvider = NotifierProvider<MapViewController, MapView?>(MapViewController.new);
