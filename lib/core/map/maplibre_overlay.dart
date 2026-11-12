import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:maplibre/maplibre.dart';

import 'map_overlay.dart';
import 'map_pins.dart';

/// What the MapLibre map draws of an overlay as layers of its own over its style: the paths, the pins, the user dot
/// and how sure its position is. Drawn by the map, they move with it, where Flutter widgets over the map are placed
/// once it has moved, a frame or more behind (they trailed it as it panned). Pins and the dot keep their looks: each
/// look is drawn once from its widget into an image the map draws (`MapPin.image`).
///
/// From the bottom: the paths, the circle of accuracy, the pins shown close up only (a station's ways in and out), the
/// pins turned with the map (a vehicle's pointer), the
/// upright pins, the user's heading lying on the map, the user dot.
class MapLibreOverlay {
  MapLibreOverlay(this._style, {required this.theme, required double pixelRatio})
      : _pixelRatio = pixelRatio,
        _iconSize = overlayIconSize(pixelRatio) {
    _run(() async {
      for (final source in [accuracySource, pinsSource, userSource]) {
        await _style.addSource(GeoJsonSource(id: source, data: _empty));
      }
      for (final layer in overlayStyleLayers(iconSize: _iconSize)) {
        await _style.addLayer(layer);
      }
    });
  }

  static const accuracySource = 'overlay-accuracy';
  static const pinsSource = 'overlay-pins';
  static const userSource = 'overlay-user';

  static const accuracyLayer = 'overlay-accuracy';
  static const closeUpPinsLayer = 'overlay-pins-close-up';
  static const turnedPinsLayer = 'overlay-pins-turned';
  static const pinsLayer = 'overlay-pins';
  static const headingLayer = 'overlay-user-heading';
  static const userLayer = 'overlay-user';

  /// Images kept on the map beyond those shown: older unused ones are removed past this
  static const keptImages = 200;

  static const _empty = '{"type":"FeatureCollection","features":[]}';

  final StyleController _style;
  final double _pixelRatio;
  final double _iconSize;
  /// What the pins are drawn with (their colors, a dot's surface ring)
  ThemeData theme;
  bool _disposed = false;

  /// The map's changes, one after the other in the order asked (a path's layers under the overlay's, a source before
  /// its layers)
  Future<void> _queue = Future.value();

  void _run(Future<void> Function() change) {
    _queue = _queue.then((_) => _disposed ? null : change()).catchError((Object e) => debugPrint('Map overlay: $e'));
  }

  void dispose() => _disposed = true;

  // Paths

  final _paths = <({MapPath path, String id, int layers})>[];
  var _pathCount = 0;

  /// Shows [paths], the first one at the bottom: those unchanged from the start stay, the others are drawn again in
  /// order (a path's layers are sent again whole to the map engine)
  void showPaths(List<MapPath> paths) {
    var kept = 0;
    while (kept < paths.length && kept < _paths.length && _paths[kept].path.sameAs(paths[kept])) {
      kept++;
    }
    if (kept == paths.length && kept == _paths.length) {
      return;
    }
    final gone = _paths.sublist(kept);
    _paths.removeRange(kept, _paths.length);
    final added = [
      for (final path in paths.skip(kept)) (path: path, id: 'overlay-path-${_pathCount++}', layers: mapLibrePathLayers(path)),
    ];
    _paths.addAll([for (final next in added) (path: next.path, id: next.id, layers: next.layers.length)]);
    _run(() async {
      for (final old in gone) {
        for (var index = 0; index < old.layers; index++) {
          await _style.removeLayer('${old.id}-$index');
        }
        await _style.removeSource(old.id);
      }
      for (final next in added) {
        await _style.addSource(GeoJsonSource(id: next.id, data: pathGeoJson(next.path)));
        for (final (index, layer) in next.layers.indexed) {
          await _style.addLayer(
            LineStyleLayer(id: '${next.id}-$index', sourceId: next.id, layout: layer.getLayout(), paint: layer.getPaint()),
            belowLayerId: accuracyLayer,
          );
        }
      }
    });
  }

  // Images

  /// Images on the map, and being drawn
  final _images = <String>{};
  final _drawing = <String>{};

  /// The name of an image on the map: its look in the theme's brightness (a dot is ringed with the surface color)
  String _imageId(String look) => '${theme.brightness.name}/$look';

  /// Draws [build] into the image [id] unless it is there or on its way; the overlay is shown again once it is there
  void _draw(String id, Size size, Widget Function() build) {
    if (_images.contains(id) || _drawing.contains(id)) {
      return;
    }
    _drawing.add(id);
    final theme = this.theme;
    unawaited(() async {
      try {
        await _style.addImageFromWidget(
          id: id,
          widget: Theme(
            data: theme,
            child: Material(
              type: MaterialType.transparency,
              child: SizedBox.fromSize(size: size, child: Center(child: build())),
            ),
          ),
          logicalSize: size,
          imageSize: size * overlayImageRatio(_pixelRatio),
        );
        _images.add(id);
      } catch (e) {
        debugPrint('Map image $id not drawn: $e');
      } finally {
        _drawing.remove(id);
      }
      _showSoon();
    }());
  }

  bool _showScheduled = false;

  /// Images came: the pins and the dot waiting for them are shown, once for all of them
  void _showSoon() {
    if (_showScheduled || _disposed) {
      return;
    }
    _showScheduled = true;
    scheduleMicrotask(() {
      _showScheduled = false;
      _pushPins();
      _pushUser();
      _prune();
    });
  }

  /// Past [keptImages], the images nothing shows any more are taken off the map
  void _prune() {
    if (_images.length <= keptImages) {
      return;
    }
    final used = {for (final pin in _pins) _imageId(pinImageName(pin, _outline)), _imageId(_dot), _imageId(_heading)};
    final unused = _images.difference(used).toList();
    _images.removeAll(unused);
    _run(() async {
      for (final id in unused) {
        await _style.removeImage(id);
      }
    });
  }

  // Pins

  List<MapPin> _pins = const [];
  Color _outline = Colors.white;
  String? _pinsShown;

  /// Shows [pins], the last ones on top, dots ringed with [outline]
  void showPins(List<MapPin> pins, {required Color outline, required ThemeData theme}) {
    _pins = pins;
    _outline = outline;
    this.theme = theme;
    for (final pin in pins) {
      _draw(_imageId(pinImageName(pin, outline)), PinView.boxOf(pin), () => PinView.marker(pin, outline));
    }
    _pushPins();
  }

  void _pushPins() {
    final data = pinsGeoJson(_pins, image: (pin) => _imageId(pinImageName(pin, _outline)), ready: _images.contains);
    if (data == _pinsShown) {
      return;
    }
    _pinsShown = data;
    _run(() => _style.updateGeoJsonSource(id: pinsSource, data: data));
  }

  /// The pin under [screenPoint] that can be tapped, the one drawn on top
  MapPin? tappedPin(MapController controller, Offset screenPoint) {
    MapPin? tapped;
    var top = -1;
    for (final feature in controller.featuresAtPoint(screenPoint, layerIds: const [pinsLayer, turnedPinsLayer, closeUpPinsLayer])) {
      final index = switch (feature.properties['pin']) {
        final num value => value.toInt(),
        final String value => int.tryParse(value),
        _ => null,
      };
      if (index != null && index > top && index < _pins.length && _pins[index].onTap != null) {
        top = index;
        tapped = _pins[index];
      }
    }
    return tapped;
  }

  // The user

  static const _dot = 'user-dot';
  static const _heading = 'user-heading';

  LatLng? _user;
  double? _accuracy;
  double? _userHeading;
  double _zoom = 0;
  String? _userShown;
  String? _accuracyShown;

  /// Shows the user dot at [position], its [heading] (degrees from north) when known, and the circle of its
  /// [accuracy] (meters) when wider than the dot's halo at [zoom]
  void showUser(LatLng? position, {double? accuracy, double? heading, required double zoom}) {
    _user = position;
    _accuracy = accuracy;
    _userHeading = heading;
    _zoom = zoom;
    if (position != null) {
      _draw(_imageId(_dot), UserDot.size, () => const UserDot());
      if (heading != null) {
        _draw(_imageId(_heading), UserDot.size, () => const HeadingCone());
      }
    }
    _pushUser();
  }

  /// The camera moved: the circle of accuracy shows from the zoom where it is wider than the dot's halo
  void zoomed(double zoom) {
    if (zoom != _zoom) {
      _zoom = zoom;
      _pushUser();
    }
  }

  void _pushUser() {
    final dot = _imageId(_dot);
    final heading = _imageId(_heading);
    final user = userGeoJson(
      _user,
      dot: _images.contains(dot) ? dot : null,
      heading: _userHeading,
      cone: _images.contains(heading) ? heading : null,
    );
    if (user != _userShown) {
      _userShown = user;
      _run(() => _style.updateGeoJsonSource(id: userSource, data: user));
    }
    final position = _user;
    final shown = position != null && AccuracyCircle.radiusFor(_accuracy, position.latitude, _zoom, tileSize: 512) != null;
    final circle = accuracyGeoJson(shown ? position : null, _accuracy);
    if (circle != _accuracyShown) {
      _accuracyShown = circle;
      _run(() => _style.updateGeoJsonSource(id: accuracySource, data: circle));
    }
  }
}

/// The pixels an image of the overlay is made of per logical pixel: the screen's [pixelRatio] for sharpness, but on
/// Android, whose map (`maplibre_android`) decodes images scaled up to the screen's density once more. Drawn at that
/// density there, every image came 7 times too big (2.625² on a Pixel 10), MapLibre's icon atlas outgrew what the GPU
/// takes and pins showed pieces of others: drawn at 1 and scaled up there, a little blurry instead.
double overlayImageRatio(double pixelRatio, {bool web = kIsWeb, TargetPlatform? platform}) =>
    !web && (platform ?? defaultTargetPlatform) == TargetPlatform.android ? 1 : pixelRatio;

/// The size images are drawn at on the map ([overlayImageRatio]): the web map is told their density, Android's scales
/// them to the screen's, iOS's takes them for points, so they are drawn smaller by as much there
double overlayIconSize(double pixelRatio, {bool web = kIsWeb, TargetPlatform? platform}) =>
    web || (platform ?? defaultTargetPlatform) == TargetPlatform.android ? 1 : 1 / pixelRatio;

/// The name of [pin]'s look: its own, else its dot's
String pinImageName(MapPin pin, Color outline) =>
    pin.image ?? 'dot-${pin.color.toARGB32()}-${pin.icon.codePoint}-${pin.size}-${outline.toARGB32()}';

/// The pins whose [image] is [ready] on the map as GeoJSON: where each one is, its image, how it stands on its point
/// (a callout by its bottom), its rotation and order (the last on top), and its place in [pins] (the one tapped)
String pinsGeoJson(List<MapPin> pins, {required String Function(MapPin pin) image, required bool Function(String id) ready}) =>
    jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final (index, pin) in pins.indexed)
          if (ready(image(pin)))
            {
              'type': 'Feature',
              'geometry': _point(pin.point),
              'properties': {
                'pin': index,
                'image': image(pin),
                'anchor': pin.above ? 'bottom' : 'center',
                'rotate': pin.rotation ?? 0,
                'turned': pin.rotation != null,
                'closeUp': pin.closeUp,
              },
            },
      ],
    });

/// The user dot at [position] as GeoJSON once its image is there, and its [heading]'s cone
String userGeoJson(LatLng? position, {String? dot, double? heading, String? cone}) => jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        if (position != null && heading != null && cone != null)
          {
            'type': 'Feature',
            'geometry': _point(position),
            'properties': {'image': cone, 'rotate': heading, 'kind': 'heading'},
          },
        if (position != null && dot != null)
          {
            'type': 'Feature',
            'geometry': _point(position),
            'properties': {'image': dot, 'rotate': 0, 'kind': 'dot'},
          },
      ],
    });

/// The circle of [accuracy] meters around [position] as GeoJSON, with its radius in pixels at zoom 0 (`r0`), which
/// the map doubles at each zoom level
String accuracyGeoJson(LatLng? position, double? accuracy) => jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        if (position != null && accuracy != null)
          {
            'type': 'Feature',
            'geometry': _point(position),
            'properties': {
              // MapLibre's world is 512 px wide at zoom 0
              'r0': accuracy * 512 / (40075016.686 * math.cos(position.latitude * math.pi / 180)),
            },
          },
      ],
    });

/// [path] as GeoJSON
String pathGeoJson(MapPath path) => jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        if (path.points.length >= 2)
          {
            'type': 'Feature',
            'geometry': {
              'type': 'LineString',
              'coordinates': [for (final point in path.points) _coordinates(point)],
            },
            'properties': <String, Object>{},
          },
      ],
    });

Map<String, Object> _point(LatLng point) => {'type': 'Point', 'coordinates': _coordinates(point)};

List<double> _coordinates(LatLng point) => [point.longitude, point.latitude];

/// The overlay's layers from the bottom, images drawn at [iconSize] ([overlayIconSize])
List<StyleLayer> overlayStyleLayers({required double iconSize}) {
  Map<String, Object> symbols({required bool turned, bool flat = false}) => {
        'icon-image': ['get', 'image'],
        'icon-size': iconSize,
        'icon-anchor': ['coalesce', ['get', 'anchor'], 'center'],
        'icon-rotate': ['get', 'rotate'],
        'icon-rotation-alignment': turned ? 'map' : 'viewport',
        'icon-pitch-alignment': flat ? 'map' : 'viewport',
        // Every one of them, whatever it covers, in their order
        'icon-allow-overlap': true,
        'icon-ignore-placement': true,
        'symbol-z-order': 'source',
      };
  return [
    CircleStyleLayer(
      id: MapLibreOverlay.accuracyLayer,
      sourceId: MapLibreOverlay.accuracySource,
      paint: {
        // Doubled at each zoom level, from its radius at zoom 0
        'circle-radius': [
          'interpolate',
          ['exponential', 2],
          ['zoom'],
          0,
          ['get', 'r0'],
          24,
          ['*', ['get', 'r0'], 16777216],
        ],
        'circle-color': _css(AccuracyCircle.fill),
        'circle-stroke-color': _css(AccuracyCircle.border),
        'circle-stroke-width': 1,
        // Lying on the map, flattened when it is tilted
        'circle-pitch-alignment': 'map',
        'circle-pitch-scale': 'map',
      },
    ),
    // A station's ways in and out, close up only: under the other pins
    SymbolStyleLayer(
      id: MapLibreOverlay.closeUpPinsLayer,
      sourceId: MapLibreOverlay.pinsSource,
      minZoom: MapPin.closeUpZoom,
      filter: const ['all', ['==', ['get', 'turned'], false], ['==', ['get', 'closeUp'], true]],
      layout: symbols(turned: false),
    ),
    SymbolStyleLayer(
      id: MapLibreOverlay.turnedPinsLayer,
      sourceId: MapLibreOverlay.pinsSource,
      filter: const ['==', ['get', 'turned'], true],
      layout: symbols(turned: true),
    ),
    SymbolStyleLayer(
      id: MapLibreOverlay.pinsLayer,
      sourceId: MapLibreOverlay.pinsSource,
      filter: const ['all', ['==', ['get', 'turned'], false], ['==', ['get', 'closeUp'], false]],
      layout: symbols(turned: false),
    ),
    SymbolStyleLayer(
      id: MapLibreOverlay.headingLayer,
      sourceId: MapLibreOverlay.userSource,
      filter: const ['==', ['get', 'kind'], 'heading'],
      layout: symbols(turned: true, flat: true),
    ),
    SymbolStyleLayer(
      id: MapLibreOverlay.userLayer,
      sourceId: MapLibreOverlay.userSource,
      filter: const ['==', ['get', 'kind'], 'dot'],
      layout: symbols(turned: false),
    ),
  ];
}

/// A color as the map's style reads it, transparency included
String _css(Color color) =>
    'rgba(${(color.r * 255).round()}, ${(color.g * 255).round()}, ${(color.b * 255).round()}, ${color.a.toStringAsFixed(3)})';

/// Light edge of the paths: the map stays light in dark mode too
const _casing = Colors.white;

/// The style layers of [path] on the MapLibre map: a solid path on a light edge as faded as it, a walk as round dots
/// on the map itself like Citymapper's (a light band under them hid the map)
List<Layer> mapLibrePathLayers(MapPath path) {
  final lines = [
    if (path.points.length >= 2)
      Feature(geometry: LineString.from([for (final point in path.points) Geographic(lon: point.longitude, lat: point.latitude)])),
  ];
  if (path.dotted) {
    return [DotsLayer(polylines: lines, color: path.color, width: path.width.round())];
  }
  return [
    PolylineLayer(polylines: lines, color: _casing.withValues(alpha: path.color.a), width: (path.width + 3).round()),
    PolylineLayer(polylines: lines, color: path.color, width: path.width.round()),
  ];
}

/// A line of round dots as wide as the line, one every two widths: dashes of no length, their round ends drawn
class DotsLayer extends PolylineLayer {
  const DotsLayer({required super.polylines, required super.color, required super.width});

  @override
  Map<String, Object> getLayout() => const {'line-cap': 'round', 'line-join': 'round'};

  @override
  Map<String, Object> getPaint() => {...super.getPaint(), 'line-dasharray': const [0, 2]};
}
