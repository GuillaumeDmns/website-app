import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:maplibre/maplibre.dart';

import '../../l10n/l10n.dart';
import '../location/device_heading.dart';
import '../location/location_providers.dart';
import 'map_overlay.dart';
import 'map_pins.dart';

/// OpenFreeMap styles (free, no key, OpenStreetMap data): Liberty in light mode, Fiord in dark mode
const _lightStyle = 'https://tiles.openfreemap.org/styles/liberty';
const _darkStyle = 'https://tiles.openfreemap.org/styles/fiord';

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

class _MapLibreMainMapState extends ConsumerState<MapLibreMainMap> {
  MapController? _controller;
  bool _ready = false;
  String? _style;

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

  @override
  void dispose() {
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
    // Only turning (the phone in the hand): quickly, the map stays with the hand
    final turning = shown != null && shown.position == view.position && shown.zoom == view.zoom;
    final height = context.size?.height ?? 0;
    final visible = height - widget.padding.bottom;
    unawaited(controller.animateCamera(
      center: _geo(view.position),
      zoom: view.zoom,
      bearing: view.bearing,
      padding: EdgeInsets.only(top: visible * 0.44, bottom: widget.padding.bottom),
      nativeDuration: Duration(milliseconds: turning ? 250 : 700),
    ));
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
    _frame(_overlay);
  }

  void _stopFollowing() {
    _following = null;
    _shown = null;
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
          final center = _controller?.camera?.center;
          if (mounted && center != null) {
            ref.read(mapCenterProvider.notifier).update(LatLng(center.lat, center.lon));
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
    final overlay = ref.watch(mapOverlaysProvider.select((overlays) => overlays[location])) ?? MapOverlay.empty;
    _overlay = overlay;
    // Followed (GO on foot): the position the camera follows, so that both agree
    final user = overlay.follow?.position ?? ref.watch(preciseUserPositionProvider) ?? ref.watch(userLocationProvider).value;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    final style = dark ? _darkStyle : _lightStyle;
    if (_style != null && _style != style) {
      _controller?.setStyle(style);
    }
    _style = style;

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

    final casing = dark ? Colors.black54 : Colors.white;
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
      return _map(context, style, user, overlay, scheme, casing);
    });
  }

  Widget _map(BuildContext context, String style, LatLng? user, MapOverlay overlay, ColorScheme scheme, Color casing) {
    return MapLibreMap(
      options: MapOptions(
        initStyle: style,
        initCenter: _geo(user ?? parisCenter),
        initZoom: user != null ? 16 : 13,
        minZoom: 8,
        maxZoom: 19,
        // Turned by GO on foot only
        gestures: const MapGestures.all(rotate: false, pitch: false),
      ),
      onEvent: _onEvent,
      layers: [
        for (final path in overlay.paths) ...[
          // A light edge under the solid paths, so that they stand out from the map's roads
          if (!path.dotted)
            PolylineLayer(polylines: [_line(path.points)], color: casing, width: (path.width + 3).round()),
          PolylineLayer(
            polylines: [_line(path.points)],
            color: path.color,
            width: path.width.round(),
            dashArray: path.dotted ? const [1, 2] : null,
          ),
        ],
      ],
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
