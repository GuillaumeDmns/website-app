import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:maplibre/maplibre.dart';

import '../../l10n/l10n.dart';
import '../location/device_heading.dart';
import '../location/location_providers.dart';
import 'map_overlay.dart';
import 'map_pins.dart';

/// OpenFreeMap's Liberty style (free, no key, OpenStreetMap data), in dark mode too: its dark style (Fiord) showed too
/// little of the streets
const _style = 'https://tiles.openfreemap.org/styles/liberty';

/// The web map is created at the window's size and resized by the browser after the frame that shows it
const _webResizeDelay = Duration(milliseconds: 50);

/// The map with MapLibre (native SDK on Android and iOS, maplibre-gl-js on the web): OpenFreeMap's vector tiles drawn
/// by the GPU. Paths are style layers, pins and the user position Flutter widgets over the map. See [MainMap].
class MapLibreMainMap extends ConsumerStatefulWidget {
  const MapLibreMainMap({super.key, this.padding = EdgeInsets.zero, this.onLongPress});

  final EdgeInsets padding;
  final void Function(BuildContext context, LatLng position)? onLongPress;

  @override
  ConsumerState<MapLibreMainMap> createState() => _MapLibreMainMapState();
}

class _MapLibreMainMapState extends ConsumerState<MapLibreMainMap> with SingleTickerProviderStateMixin {
  MapController? _controller;
  bool _ready = false;

  /// Points framed last: pages republish their overlay when their data refreshes, the camera only moves when the
  /// points to frame change
  List<LatLng>? _framedFit;
  bool _centeredOnUser = false;
  Timer? _centerDebounce;

  /// Follow camera of the overlay (GO on foot), and whether the user moved the map away from it
  MapFollow? _following;
  bool _followPaused = false;

  /// What the camera shows of the follow (its heading the device's when known), and that heading
  MapFollow? _shown;
  final _heading = FollowHeading();

  /// The overlay shown, for the callbacks of the map
  MapOverlay _overlay = MapOverlay.empty;

  /// Size of the map last laid out: a frame computed at another size (the page still being laid out) is done again
  Size? _size;

  /// Small steps of the follow camera (the smoothed position, the compass) are eased frame by frame towards the last
  /// view asked, so that the camera glides whatever the rate views come at; the ticker only runs until it is there
  late final Ticker _glide = createTicker(_onGlideFrame);

  /// What the camera shows now, and where it glides to
  MapFollow? _camera;
  MapFollow? _target;
  EdgeInsets _followPadding = EdgeInsets.zero;
  Duration? _lastGlideFrame;

  /// An animation to the follow is running until then: the glide waits for it
  DateTime _animatedUntil = DateTime(0);

  @override
  void dispose() {
    _glide.dispose();
    _centerDebounce?.cancel();
    _heading.dispose();
    super.dispose();
  }

  static Geographic _geo(LatLng point) => Geographic(lon: point.longitude, lat: point.latitude);

  void _frame(MapOverlay overlay) {
    final follow = overlay.follow;
    if (follow != null) {
      _follow(follow);
      return;
    }
    if (_following != null) {
      _stopFollowing();
    }
    final controller = _controller;
    if (!_ready || controller == null || overlay.fit.isEmpty || listEquals(overlay.fit, _framedFit)) {
      return;
    }
    _framedFit = overlay.fit;
    final padding = widget.padding + const EdgeInsets.all(48);
    if (overlay.fit.length == 1) {
      unawaited(controller.animateCamera(
        center: _geo(overlay.fit.single),
        zoom: 16,
        bearing: 0,
        padding: padding,
        nativeDuration: const Duration(milliseconds: 500),
      ));
      return;
    }
    unawaited(controller.fitBounds(
      bounds: _bounds(overlay.fit),
      bearing: 0,
      padding: padding,
      nativeDuration: const Duration(milliseconds: 500),
      webMaxZoom: 17,
    ));
  }

  /// The points' bounds, at least about 300 m wide so that close points aren't zoomed in too much
  static LngLatBounds _bounds(List<LatLng> points) {
    var south = points.first.latitude, north = south, west = points.first.longitude, east = west;
    for (final point in points) {
      south = point.latitude < south ? point.latitude : south;
      north = point.latitude > north ? point.latitude : north;
      west = point.longitude < west ? point.longitude : west;
      east = point.longitude > east ? point.longitude : east;
    }
    const minLat = 0.0027, minLon = 0.004;
    if (north - south < minLat) {
      final middle = (north + south) / 2;
      south = middle - minLat / 2;
      north = middle + minLat / 2;
    }
    if (east - west < minLon) {
      final middle = (east + west) / 2;
      west = middle - minLon / 2;
      east = middle + minLon / 2;
    }
    return LngLatBounds(longitudeWest: west, longitudeEast: east, latitudeSouth: south, latitudeNorth: north);
  }

  /// The user low in the visible part (above the panel), the way ahead up: the camera's padding puts its center at
  /// 72 % of the height left above the panel
  void _follow(MapFollow follow) {
    _following = follow;
    final controller = _controller;
    if (!_ready || controller == null || _followPaused) {
      return;
    }
    final view = _heading.apply(follow);
    final shown = _shown;
    if (shown != null && shown.sameView(view)) {
      return;
    }
    _shown = view;
    final height = context.size?.height ?? 0;
    final visible = height - widget.padding.bottom;
    _followPadding = EdgeInsets.only(top: visible * 0.44, bottom: widget.padding.bottom);
    // A small step (the smoothed position, the compass): glided to, frame by frame
    if (shown != null && shown.closeTo(view)) {
      _camera ??= shown;
      _target = view;
      if (!_glide.isActive) {
        _lastGlideFrame = null;
        _glide.start();
      }
      return;
    }
    _glide.stop();
    const duration = Duration(milliseconds: 700);
    _camera = view;
    _target = view;
    _animatedUntil = DateTime.now().add(duration);
    unawaited(controller.animateCamera(
      center: _geo(view.position),
      zoom: view.zoom,
      bearing: view.bearing,
      padding: _followPadding,
      nativeDuration: duration,
    ));
  }

  /// A frame of the glide: the camera goes part of the way to the target (more the longer the frame), at most 60 times
  /// a second, and stops once there
  void _onGlideFrame(Duration elapsed) {
    final camera = _camera;
    final target = _target;
    final controller = _controller;
    if (camera == null || target == null || controller == null || _following == null || _followPaused) {
      _glide.stop();
      return;
    }
    final last = _lastGlideFrame;
    if (DateTime.now().isBefore(_animatedUntil)) {
      _lastGlideFrame = elapsed;
      return;
    }
    if (last != null && elapsed - last < const Duration(milliseconds: 15)) {
      return;
    }
    _lastGlideFrame = elapsed;
    final shown = camera.glideTo(target, last == null ? 1 / 60 : (elapsed - last).inMicroseconds / 1e6);
    _camera = shown;
    unawaited(controller.moveCamera(
      center: _geo(shown.position),
      zoom: shown.zoom,
      bearing: shown.bearing,
      padding: _followPadding,
    ));
    if (shown == target) {
      _glide.stop();
    }
  }

  /// A new heading of the device: the camera turns with it (at most 10 times a second)
  void _onDeviceHeading(double heading) {
    _heading.update(heading, () {
      final follow = _following;
      if (mounted && follow != null && follow.compass) {
        _follow(follow);
      }
    });
  }

  /// Frames (or follows) the overlay again, even if it is the one framed last
  void _reframe() {
    _framedFit = null;
    _following = null;
    _shown = null;
    _camera = null;
    _glide.stop();
    _frame(_overlay);
  }

  void _stopFollowing() {
    _following = null;
    _shown = null;
    _camera = null;
    _glide.stop();
    _followPaused = false;
    // North up again, then the page's points are framed
    _framedFit = null;
    if (_ready) {
      unawaited(_controller?.animateCamera(bearing: 0, nativeDuration: const Duration(milliseconds: 500)));
    }
  }

  void _recenter() {
    setState(() => _followPaused = false);
    final follow = _following;
    if (follow != null) {
      _following = null;
      _shown = null;
      _camera = null;
      _glide.stop();
      _follow(follow);
    }
  }

  void _onEvent(MapEvent event) {
    switch (event) {
      case MapEventStyleLoaded():
        if (_ready) {
          _reframe();
        }
      case MapEventStartMoveCamera(reason: CameraChangeReason.apiGesture):
        // Moving the map by hand stops following until "Recentrer"
        if (_following != null && !_followPaused) {
          setState(() => _followPaused = true);
        }
      case MapEventCameraIdle():
        _centerDebounce?.cancel();
        _centerDebounce = Timer(const Duration(milliseconds: 600), () {
          final controller = _controller;
          final center = controller?.camera?.center;
          if (mounted && controller != null && center != null) {
            ref.read(mapCenterProvider.notifier).update(LatLng(center.lat, center.lon));
            ref.read(mapScaleProvider.notifier).update(controller.getMetersPerPixelAtLatitude(center.lat.toDouble()));
          }
        });
      case MapEventLongClick(:final point) || MapEventSecondaryClick(:final point):
        widget.onLongPress?.call(context, LatLng(point.lat, point.lon));
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(routerLocationProvider);
    final page = ref.watch(mapOverlaysProvider.select((overlays) => overlays[location])) ?? MapOverlay.empty;
    // Followed (GO on foot): the smoothed position when there is one, so that the camera and the dot agree
    final precise = ref.watch(preciseUserPositionProvider);
    final pageFollow = page.follow;
    final overlay = pageFollow != null && precise != null ? page.withFollow(pageFollow.withPosition(precise)) : page;
    _overlay = overlay;
    final user = overlay.follow?.position ?? precise ?? ref.watch(userLocationProvider).value;
    final scheme = Theme.of(context).colorScheme;


    WidgetsBinding.instance.addPostFrameCallback((_) => _frame(overlay));

    // GO on foot or by bike: the device's heading turns the map (the sensor only runs meanwhile)
    if (overlay.follow?.compass ?? false) {
      ref.listen(deviceHeadingProvider, (_, next) {
        final heading = next.value;
        if (heading != null) {
          _onDeviceHeading(heading);
        }
      });
    } else {
      _heading.device = null;
    }

    // First fix: go to the user unless a page already framed something
    ref.listen(userLocationProvider, (previous, next) {
      final position = next.value;
      if (position != null && !_centeredOnUser && _ready && overlay.follow == null) {
        _centeredOnUser = true;
        if (_framedFit == null) {
          unawaited(_controller?.animateCamera(center: _geo(position), zoom: 16, nativeDuration: const Duration(milliseconds: 500)));
        }
      }
    });

    const casing = Colors.white;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (size != _size) {
        _size = size;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _ready) {
            _reframe();
          }
        });
      }
      return _map(context, user, overlay, scheme, casing);
    });
  }

  Widget _map(BuildContext context, LatLng? user, MapOverlay overlay, ColorScheme scheme, Color casing) {
    return MapLibreMap(
      options: MapOptions(
        initStyle: _style,
        initCenter: _geo(user ?? parisCenter),
        initZoom: user != null ? 16 : 13,
        minZoom: 8,
        maxZoom: 19,
        // Turned by GO on foot only
        gestures: const MapGestures.all(rotate: false, pitch: false),
      ),
      onEvent: _onEvent,
      layers: _layers(overlay.paths, casing),
      children: [
        // The controller of the map actually shown: the map can be created again (the page laid out again), and the
        // overlay is then framed on the new one
        Builder(builder: (context) {
          final controller = MapController.maybeOf(context);
          if (controller != null && controller != _controller) {
            _controller = controller;
            _ready = true;
            // On the web, once the browser has given the map its size (web/index.html), after this frame
            WidgetsBinding.instance.addPostFrameCallback((_) => Timer(kIsWeb ? _webResizeDelay : Duration.zero, () {
                  if (mounted) {
                    _reframe();
                  }
                }));
          }
          return const SizedBox.shrink();
        }),
        WidgetLayer(
          allowInteraction: true,
          markers: [
            for (final pin in overlay.pins)
              Marker(
                point: _geo(pin.point),
                size: pin.child != null ? pin.childSize : Size.square(pin.size + 16),
                alignment: pin.above ? Alignment.topCenter : Alignment.center,
                child: PinView(pin: pin, outline: scheme.surface),
              ),
            if (user != null)
              Marker(
                point: _geo(user),
                size: UserDot.size,
                child: Builder(
                  builder: (context) {
                    // Upright marker: the heading on the screen is the heading minus the map's bearing
                    final bearing = MapCamera.maybeOf(context)?.bearing ?? 0;
                    final follow = overlay.follow;
                    return UserDot(screenHeading: follow == null ? null : _heading.apply(follow).bearing - bearing);
                  },
                ),
              ),
          ],
        ),
        if (_following != null && _followPaused)
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.only(right: 16, bottom: widget.padding.bottom + 16),
              child: FloatingActionButton.small(
                heroTag: null,
                tooltip: context.l10n.recenter,
                onPressed: _recenter,
                child: const Icon(Icons.navigation),
              ),
            ),
          ),
        const _Attribution(),
      ],
    );
  }

  /// Layers of the paths drawn last: the map sends a layer to the map engine again unless it is the same object, so
  /// the layers of unchanged paths are kept (vehicles move every second on a line's page)
  List<(MapPath, List<Layer>)> _pathLayers = const [];

  List<Layer> _layers(List<MapPath> paths, Color casing) {
    final previous = _pathLayers;
    _pathLayers = [
      for (final (index, path) in paths.indexed)
        index < previous.length && previous[index].$1.sameAs(path) ? previous[index] : (path, _pathLayersOf(path, casing)),
    ];
    return [for (final (_, layers) in _pathLayers) ...layers];
  }

  static List<Layer> _pathLayersOf(MapPath path, Color casing) {
    final lines = [for (final part in path.parts) if (part.length >= 2) _line(part)];
    return [
      // A light edge under the path (a band under the dotted ones), as faded as the path
      if (path.casing) PolylineLayer(polylines: lines, color: casing.withValues(alpha: path.color.a), width: (path.width + 3).round()),
      PolylineLayer(polylines: lines, color: path.color, width: path.width.round(), dashArray: path.dotted ? const [1, 2] : null),
    ];
  }

  static Feature<LineString> _line(List<LatLng> points) =>
      Feature(geometry: LineString.from([for (final point in points) _geo(point)]));
}

/// Short credits, the full ones on the About page
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
        child: Text('© OpenFreeMap © OpenMapTiles © OpenStreetMap · IDFM', style: theme.textTheme.labelSmall?.copyWith(fontSize: 9)),
      ),
    );
  }
}
