import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show Distance, LatLng;

import '../location/location_providers.dart';
import 'main_map.dart' show mapTilesEnabledProvider;
import 'map_overlay.dart';
import 'map_panel.dart';
import 'map_pins.dart';

/// The map with flutter_map and the Plan IGN raster tiles (Géoplateforme, free, no key; light in dark mode too): on
/// desktop, where MapLibre doesn't run, and in the tests (the tiles off). flutter_map has no padding: the camera's
/// center is moved by half the panel's moves instead, so that what is in the middle of the part left above stays
/// there. See [MainMap].
class FlutterMainMap extends ConsumerStatefulWidget {
  const FlutterMainMap({super.key, this.panel, this.onLongPress});

  /// The bottom sheet over the map
  final MapPanel? panel;

  /// Long press (right click on desktop) on a point of the map
  final void Function(BuildContext context, LatLng position)? onLongPress;

  @override
  ConsumerState<FlutterMainMap> createState() => _FlutterMainMapState();
}

class _FlutterMainMapState extends ConsumerState<FlutterMainMap> with TickerProviderStateMixin {
  late final _controller = AnimatedMapController(vsync: this, duration: const Duration(milliseconds: 500));
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

  /// The part hidden by the panel the camera was placed for, and its animation running until this timer ends (the
  /// panel's moves are followed after it)
  double _cameraInset = 0;
  Timer? _animation;
  bool _panelScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.panel?.addListener(_onPanel);
  }

  @override
  void dispose() {
    widget.panel?.removeListener(_onPanel);
    _animation?.cancel();
    _centerDebounce?.cancel();
    _heading.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FlutterMainMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.panel != oldWidget.panel) {
      oldWidget.panel?.removeListener(_onPanel);
      widget.panel?.addListener(_onPanel);
      _onPanel();
    }
  }

  double get _height => _controller.mapController.camera.nonRotatedSize.height;
  double _inset(double? extent) => panelInset(extent ?? 0, _height);

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

  /// The camera keeps what is in the middle of the part of the map left above the panel there (the user at 72 % of it
  /// when followed), at once. After the camera's own animation, which aims at where the panel rests.
  void _followPanel() {
    if (!mounted || !_ready || _animation != null) {
      return;
    }
    final inset = _inset(widget.panel?.live);
    if ((inset - _cameraInset).abs() < 0.5) {
      return;
    }
    final shown = _shown;
    if (_following != null && !_followPaused && shown != null) {
      _cameraInset = inset;
      _controller.mapController.moveAndRotate(_followCenter(shown, inset), shown.zoom, -shown.bearing);
      return;
    }
    final camera = _controller.mapController.camera;
    final shift = visibleCenterShift(_cameraInset, inset, _height);
    _cameraInset = inset;
    _controller.mapController.move(camera.screenOffsetToLatLng(camera.nonRotatedSize.center(Offset.zero) - Offset(0, shift)), camera.zoom);
  }

  /// The camera's center putting [view]'s position at 72 % of the part of the map left above a panel hiding [inset] px
  LatLng _followCenter(MapFollow view, double inset) {
    final size = _controller.mapController.camera.nonRotatedSize;
    // The user shown this many pixels below the center of the map, which is then that far ahead of them (the
    // animation's own offset doesn't work with a rotation)
    final below = (size.height - inset) * 0.72 - size.height / 2;
    final metersPerPixel = 156543.03392 * math.cos(view.position.latitudeInRad) / math.pow(2, view.zoom);
    return const Distance().offset(view.position, below.abs() * metersPerPixel, below >= 0 ? view.bearing : view.bearing + 180);
  }

  /// A camera animation of [duration] starts
  void _animating(Duration duration) {
    _animation?.cancel();
    _animation = Timer(duration, () {
      _animation = null;
      _followPanel();
    });
  }

  /// Frames [points] in the part of the map left above where the panel rests
  void _fit(List<LatLng> points, {required double maxZoom}) {
    _cameraInset = _inset(widget.panel?.resting);
    _animating(const Duration(milliseconds: 500));
    _controller.animatedFitCamera(
      cameraFit: CameraFit.coordinates(coordinates: points, padding: framePadding(widget.panel?.resting ?? 0, _height), maxZoom: maxZoom),
    );
  }

  void _frame(MapOverlay overlay) {
    final follow = overlay.follow;
    if (follow != null) {
      _follow(follow);
      return;
    }
    if (_following != null) {
      _stopFollowing();
    }
    if (!_ready || overlay.fit.isEmpty || listEquals(overlay.fit, _framedFit)) {
      return;
    }
    _framedFit = overlay.fit;

    // Also for a single point, so that it is centered in the part of the map not hidden by the panel
    _fit(overlay.fit, maxZoom: overlay.fit.length == 1 ? 16 : 17);
  }

  /// The user low in the visible part (above the panel), the way ahead up
  void _follow(MapFollow follow) {
    _following = follow;
    if (!_ready || _followPaused) {
      return;
    }
    final view = _heading.apply(follow);
    final shown = _shown;
    if (shown != null && shown.sameView(view) && _controller.mapController.camera.zoom == view.zoom) {
      return;
    }
    _shown = view;
    // A small step (the smoothed position, the compass): at once, the next one comes a tenth of a second later
    final step = shown != null && shown.closeTo(view);
    // Only turning (the phone in the hand): quickly, the map stays with the hand
    final turning = shown != null && shown.position == view.position && shown.zoom == view.zoom;
    if (step) {
      _cameraInset = _inset(widget.panel?.live);
      _controller.mapController.moveAndRotate(_followCenter(view, _cameraInset), view.zoom, -view.bearing);
      return;
    }
    final duration = Duration(milliseconds: turning ? 250 : 700);
    _cameraInset = _inset(widget.panel?.resting);
    _animating(duration);
    _controller.animateTo(
      dest: _followCenter(view, _cameraInset),
      zoom: view.zoom,
      rotation: _closestRotation(-view.bearing),
      duration: duration,
    );
  }

  /// The device turned: the camera turns with it
  void _turn() {
    final follow = _following;
    if (mounted && follow != null && follow.compass) {
      _follow(follow);
    }
  }

  void _stopFollowing() {
    _following = null;
    _shown = null;
    _followPaused = false;
    // North up again, then the page's points are framed
    _framedFit = null;
    if (_ready) {
      _animating(const Duration(milliseconds: 500));
      _controller.animateTo(rotation: _closestRotation(0));
    }
  }

  /// [target] as the angle closest to the current rotation, so that the map turns the short way
  double _closestRotation(double target) {
    final current = _controller.mapController.camera.rotation;
    return current + ((target - current) % 360 + 540) % 360 - 180;
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

  void _onMapEvent(MapEvent event) {
    // Moving the map by hand stops following until "Recentrer"
    if (_following != null && !_followPaused && switch (event.source) {
          MapEventSource.dragStart || MapEventSource.multiFingerGestureStart || MapEventSource.doubleTap ||
          MapEventSource.scrollWheel => true,
          _ => false,
        }) {
      setState(() => _followPaused = true);
    }
    // Moves by hand, and framings: the center nearby searches start from without a position
    if (event is MapEventMove || event is MapEventMoveEnd || event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd || event is MapEventScrollWheelZoom) {
      _centerDebounce?.cancel();
      _centerDebounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) {
          final camera = _controller.mapController.camera;
          ref.read(mapCenterProvider.notifier).update(camera.center);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final (:overlay, :user) = watchMapView(ref);
    final scheme = Theme.of(context).colorScheme;

    WidgetsBinding.instance.addPostFrameCallback((_) => _frame(overlay));

    _heading.watch(ref, overlay.follow, _turn);

    // First fix: go to the user unless a page already framed something
    ref.listen(userLocationProvider, (previous, next) {
      final position = next.value;
      if (position != null && !_centeredOnUser && _ready && overlay.follow == null) {
        _centeredOnUser = true;
        if (_framedFit == null) {
          // In the middle of the part of the map above the panel, not behind its edge
          _fit([position], maxZoom: 16);
        }
      }
    });

    return FlutterMap(
      mapController: _controller.mapController,
      options: MapOptions(
        initialCenter: user ?? parisCenter,
        initialZoom: user != null ? 16 : 13,
        minZoom: 8,
        maxZoom: 19,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onMapReady: () {
          _ready = true;
          _centeredOnUser = user != null;
          _frame(overlay);
        },
        onMapEvent: _onMapEvent,
        onLongPress: widget.onLongPress == null ? null : (_, position) => widget.onLongPress!(context, position),
        onSecondaryTap: widget.onLongPress == null ? null : (_, position) => widget.onLongPress!(context, position),
      ),
      children: [
        // Plan IGN (Géoplateforme): free, no key, open licence; light in dark mode too, like the MapLibre map
        if (ref.watch(mapTilesEnabledProvider))
          TileLayer(
            urlTemplate: 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
                '&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&STYLE=normal&TILEMATRIXSET=PM'
                '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png',
            userAgentPackageName: 'com.guillaumedamiens.app',
            maxNativeZoom: 19,
          ),
        PolylineLayer(
          polylines: [
            for (final path in overlay.paths)
              Polyline(
                points: path.points,
                color: path.color,
                strokeWidth: path.width,
                pattern: path.dotted ? StrokePattern.dotted(spacingFactor: 2) : const StrokePattern.solid(),
                borderColor: Colors.white.withValues(alpha: path.color.a),
                borderStrokeWidth: 1.5,
              ),
          ],
        ),
        MarkerLayer(
          // Upright when the map turns (GO on foot)
          rotate: true,
          markers: [
            for (final pin in overlay.pins)
              Marker(
                point: pin.point,
                width: pin.child != null ? pin.childSize.width : pin.size + 16,
                height: pin.child != null ? pin.childSize.height : pin.size + 16,
                alignment: pin.above ? Alignment.topCenter : Alignment.center,
                child: PinView(pin: pin, outline: scheme.surface),
              ),
            if (user != null)
              Marker(
                point: user,
                width: UserDot.size.width,
                height: UserDot.size.height,
                // Upright marker: the heading on the screen is the map's rotation plus the heading
                child: Builder(
                  builder: (context) => UserDot(
                    screenHeading: overlay.follow == null ? null : _heading.apply(overlay.follow!).bearing + MapCamera.of(context).rotation,
                  ),
                ),
              ),
          ],
        ),
        if (_following != null && _followPaused)
          ListenableBuilder(
            listenable: widget.panel ?? const AlwaysStoppedAnimation(0),
            builder: (context, _) => RecenterButton(bottom: _inset(widget.panel?.live), onPressed: _recenter),
          ),
        RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          // Full credits on the About page
          attributions: [
            TextSourceAttribution('IGN – Plan IGN', onTap: null),
            TextSourceAttribution('Île-de-France Mobilités', onTap: null),
            TextSourceAttribution('© contributeurs OpenStreetMap', onTap: null),
          ],
        ),
      ],
    );
  }
}

