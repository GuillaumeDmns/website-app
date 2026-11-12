import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:maplibre/maplibre.dart';

import '../location/location_providers.dart';
import 'base_map_style.dart';
import 'map_overlay.dart';
import 'map_panel.dart';
import 'map_pins.dart';
import 'maplibre_overlay.dart';

/// The web map is created at the window's size and resized by the browser after the frame that shows it
const _webResizeDelay = Duration(milliseconds: 50);

/// The map with MapLibre (native SDK on Android and iOS, maplibre-gl-js on the web): OpenFreeMap's vector tiles drawn
/// by the GPU. What a page shows on it, and the user dot, are layers of the map ([MapLibreOverlay]): they move with it.
/// The part hidden by the [panel] is the camera's padding: changing it without animation keeps what is in the middle of
/// the part left above (MapLibre's camera center is that of its padded area). See [MainMap].
class MapLibreMainMap extends ConsumerStatefulWidget {
  const MapLibreMainMap({super.key, this.panel, this.onLongPress});

  final MapPanel? panel;
  final void Function(BuildContext context, LatLng position)? onLongPress;

  @override
  ConsumerState<MapLibreMainMap> createState() => _MapLibreMainMapState();
}

class _MapLibreMainMapState extends ConsumerState<MapLibreMainMap> {
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

  /// Where the user dot is and how sure, and the theme the pins are drawn with
  LatLng? _user;
  double? _accuracy;
  ThemeData? _theme;

  /// The overlay as layers of the map shown, once its style is loaded
  MapLibreOverlay? _layers;

  /// Size of the map last laid out: a frame computed at another size (the page still being laid out) is done again
  Size? _size;

  /// Small steps of the follow camera (the smoothed position, the compass) are eased step by step towards the last
  /// view asked ([MapFollow.glideStepTo]), so that the camera glides whatever the rate views come at, until it is
  /// there. A timer, not a ticker: a ticker draws every frame of the screen (up to 120 a second) while it runs.
  Timer? _glide;

  /// What the camera shows now, and where it glides to
  MapFollow? _camera;
  MapFollow? _target;
  EdgeInsets _followPadding = EdgeInsets.zero;
  DateTime? _lastGlide;

  /// A camera animation runs until this timer ends: the glide and the panel's moves wait for it (a move would stop it)
  Timer? _animation;

  /// The padding the camera was given last, and the panel's moves to follow once per frame
  EdgeInsets _cameraPadding = EdgeInsets.zero;
  bool _panelScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.panel?.addListener(_onPanel);
  }

  @override
  void dispose() {
    widget.panel?.removeListener(_onPanel);
    _glide?.cancel();
    _animation?.cancel();
    _centerDebounce?.cancel();
    _heading.dispose();
    _layers?.dispose();
    super.dispose();
  }

  double get _height => _size?.height ?? context.size?.height ?? 0;
  double get _livePanel => widget.panel?.live ?? 0;
  double get _restingPanel => widget.panel?.resting ?? 0;

  /// A camera animation of [duration] towards [padding] starts; the panel's moves meanwhile are followed after it
  void _animating(Duration duration, EdgeInsets padding) {
    _cameraPadding = padding;
    _animation?.cancel();
    _animation = Timer(duration, () {
      _animation = null;
      _followPanel();
    });
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
    // Where the panel goes to rest: the page just changed, the sheet is on its way
    final padding = framePadding(_restingPanel, _height);
    _animating(const Duration(milliseconds: 500), padding);
    if (overlay.fit.length == 1) {
      unawaited(controller.animateCamera(
        center: _geo(overlay.fit.single),
        zoom: 16,
        bearing: 0,
        pitch: 0,
        padding: padding,
        nativeDuration: const Duration(milliseconds: 500),
      ));
      return;
    }
    unawaited(controller.fitBounds(
      bounds: _bounds(overlay.fit),
      bearing: 0,
      pitch: 0,
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
    _followPadding = followPadding(_livePanel, _height, overhead: view.overhead);
    // A small step (the smoothed position, the compass): glided to, step by step
    if (shown != null && shown.closeTo(view)) {
      _camera ??= shown;
      _target = view;
      if (_glide == null) {
        _lastGlide = null;
        _glide = Timer(Duration.zero, _glideStep);
      }
      return;
    }
    _stopGlide();
    const duration = Duration(milliseconds: 700);
    _camera = view;
    _target = view;
    final padding = followPadding(_restingPanel, _height, overhead: view.overhead);
    _animating(duration, padding);
    unawaited(controller.animateCamera(
      center: _geo(view.position),
      zoom: view.zoom,
      bearing: view.bearing,
      pitch: view.pitch,
      padding: padding,
      nativeDuration: duration,
    ));
  }

  /// A step of the glide: the camera goes part of the way to the target (more the longer since the last step), then
  /// the next step is due ([MapFollow.glideStepTo]), until it is there
  void _glideStep() {
    _glide = null;
    final camera = _camera;
    final target = _target;
    final controller = _controller;
    if (!mounted || camera == null || target == null || controller == null || _following == null || _followPaused) {
      return;
    }
    // An animation to the follow is running: the glide goes on after it
    if (_animation != null) {
      _lastGlide = null;
      _glide = Timer(MapFollow.moveStep, _glideStep);
      return;
    }
    final now = DateTime.now();
    final last = _lastGlide;
    _lastGlide = now;
    final shown = camera.glideTo(target, last == null ? 1 / 60 : math.min(0.1, now.difference(last).inMicroseconds / 1e6));
    _camera = shown;
    _cameraPadding = _followPadding;
    unawaited(controller.moveCamera(
      center: _geo(shown.position),
      zoom: shown.zoom,
      bearing: shown.bearing,
      pitch: shown.pitch,
      padding: _followPadding,
    ));
    if (shown != target) {
      _glide = Timer(shown.glideStepTo(target), _glideStep);
    }
  }

  void _stopGlide() {
    _glide?.cancel();
    _glide = null;
  }

  /// The device turned: the camera turns with it
  void _turn() {
    final follow = _following;
    if (mounted && follow != null && follow.compass) {
      _follow(follow);
      // The user's heading turned too
      _showLayers();
    }
  }

  /// Shows the overlay, the user dot and its heading on the map's own layers
  void _showLayers() {
    final layers = _layers;
    final theme = _theme;
    if (layers == null || theme == null || !mounted) {
      return;
    }
    final follow = _overlay.follow;
    layers
      ..showPaths(_overlay.paths)
      ..showPins(_overlay.pins, outline: theme.colorScheme.surface, theme: theme)
      ..showUser(
        _user,
        accuracy: _accuracy,
        heading: follow == null || follow.overhead ? null : _heading.apply(follow).bearing,
        zoom: _controller?.camera?.zoom ?? 0,
      );
  }

  @override
  void didUpdateWidget(covariant MapLibreMainMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.panel != oldWidget.panel) {
      oldWidget.panel?.removeListener(_onPanel);
      widget.panel?.addListener(_onPanel);
      _onPanel();
    }
  }

  /// The panel moved: followed once a frame
  void _onPanel() {
    if (_panelScheduled) {
      return;
    }
    _panelScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _panelScheduled = false;
      _followPanel();
    });
  }

  /// The camera keeps its center in the middle of the part of the map left above the panel (the user at 72 % of it when
  /// followed), at once: what is there stays there while the sheet moves. After the camera's own animation, which aims
  /// at where the panel rests.
  void _followPanel() {
    final controller = _controller;
    if (!mounted || !_ready || controller == null || _animation != null) {
      return;
    }
    final following = _following != null;
    final padding = following
        ? followPadding(_livePanel, _height, overhead: (_camera ?? _shown)?.overhead ?? false)
        : framePadding(_livePanel, _height);
    if (following) {
      _followPadding = padding;
    }
    // The glide's next step takes it
    if (padding == _cameraPadding || (following && !_followPaused && _glide != null)) {
      return;
    }
    final camera = following && !_followPaused ? _camera ?? _shown : null;
    final center = camera != null ? _geo(camera.position) : controller.camera?.center;
    if (center == null) {
      return;
    }
    _cameraPadding = padding;
    unawaited(controller.moveCamera(center: center, zoom: camera?.zoom, bearing: camera?.bearing, padding: padding));
  }

  /// Frames (or follows) the overlay again, even if it is the one framed last
  void _reframe() {
    _framedFit = null;
    _following = null;
    _shown = null;
    _camera = null;
    _stopGlide();
    _frame(_overlay);
  }

  void _stopFollowing() {
    _following = null;
    _shown = null;
    _camera = null;
    _stopGlide();
    _followPaused = false;
    // North up again, then the page's points are framed
    _framedFit = null;
    if (_ready) {
      const duration = Duration(milliseconds: 500);
      final padding = framePadding(_restingPanel, _height);
      _animating(duration, padding);
      unawaited(_controller?.animateCamera(bearing: 0, pitch: 0, padding: padding, nativeDuration: duration));
    }
  }

  void _recenter() {
    setState(() => _followPaused = false);
    final follow = _following;
    if (follow != null) {
      _following = null;
      _shown = null;
      _camera = null;
      _stopGlide();
      _follow(follow);
    }
  }

  void _onEvent(MapEvent event) {
    switch (event) {
      case MapEventStyleLoaded(:final style):
        for (final id in hiddenStyleLayers) {
          // A style without one of them (another version of it) is fine as it is
          unawaited(style.removeLayer(id).catchError((Object e) => debugPrint('Map layer $id not removed: $e')));
        }
        // The overlay's layers on this style (the map may be created again)
        _layers?.dispose();
        _layers = MapLibreOverlay(style, theme: Theme.of(context), pixelRatio: View.of(context).devicePixelRatio);
        _showLayers();
        if (_ready) {
          _reframe();
        }
      case MapEventMoveCamera(:final camera):
        _layers?.zoomed(camera.zoom);
      case MapEventClick(:final screenPoint):
        final controller = _controller;
        if (controller != null) {
          _layers?.tappedPin(controller, screenPoint)?.onTap?.call();
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
    final (:overlay, :user, :accuracy) = watchMapView(ref);
    _overlay = overlay;
    _user = user;
    _accuracy = accuracy;
    _theme = Theme.of(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frame(overlay);
      _showLayers();
    });

    _heading.watch(ref, overlay.follow, _turn);

    // First fix: go to the user unless a page already framed something
    ref.listen(userLocationProvider, (previous, next) {
      final position = next.value;
      if (position != null && !_centeredOnUser && _ready && overlay.follow == null) {
        _centeredOnUser = true;
        if (_framedFit == null) {
          // In the middle of the part of the map above the panel, not behind its edge
          const duration = Duration(milliseconds: 500);
          final padding = framePadding(_restingPanel, _height);
          _animating(duration, padding);
          unawaited(_controller?.animateCamera(center: _geo(position), zoom: 16, padding: padding, nativeDuration: duration));
        }
      }
    });

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
      return _map(context, user, overlay);
    });
  }

  Widget _map(BuildContext context, LatLng? user, MapOverlay overlay) {
    return MapLibreMap(
      options: MapOptions(
        initStyle: baseMapStyleUrl,
        initCenter: _geo(user ?? parisCenter),
        initZoom: user != null ? 16 : 13,
        minZoom: 8,
        maxZoom: 19,
        // Turned by GO on foot only
        gestures: const MapGestures.all(rotate: false, pitch: false),
      ),
      onEvent: _onEvent,
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
        // The pins for screen readers (drawn by the map): where they are, named, tappable; nothing seen nor touched
        if (MediaQuery.of(context).accessibleNavigation)
          WidgetLayer(
            allowInteraction: true,
            markers: [
              for (final pin in overlay.pins)
                if (pin.label != null)
                  Marker(
                    point: _geo(pin.point),
                    size: PinView.boxOf(pin),
                    alignment: pin.above ? Alignment.bottomCenter : Alignment.center,
                    child: Semantics(
                      label: pin.label,
                      button: pin.onTap != null,
                      onTap: pin.onTap,
                      child: SizedBox.fromSize(size: PinView.boxOf(pin)),
                    ),
                  ),
            ],
          ),
        if (_following != null && _followPaused)
          ListenableBuilder(
            listenable: widget.panel ?? const AlwaysStoppedAnimation(0),
            builder: (context, _) => RecenterButton(bottom: panelInset(_livePanel, _height), onPressed: _recenter),
          ),
        const _Attribution(),
      ],
    );
  }
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
