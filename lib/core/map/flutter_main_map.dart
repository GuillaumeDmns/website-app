import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show Distance, LatLng;

import '../../l10n/l10n.dart';
import '../location/device_heading.dart';
import '../location/location_providers.dart';
import 'main_map.dart' show mapTilesEnabledProvider;
import 'map_overlay.dart';
import 'map_pins.dart';

/// The map with flutter_map and the Plan IGN raster tiles (Géoplateforme, free, no key; light in dark mode too): on
/// desktop, where MapLibre doesn't run, and in the tests (the tiles off). See [MainMap].
class FlutterMainMap extends ConsumerStatefulWidget {
  const FlutterMainMap({super.key, this.padding = EdgeInsets.zero, this.onLongPress});

  /// Part of the map hidden by the panel, kept out of the framed area
  final EdgeInsets padding;

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

  @override
  void dispose() {
    _centerDebounce?.cancel();
    _heading.dispose();
    _controller.dispose();
    super.dispose();
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
    _controller.animatedFitCamera(
      cameraFit: CameraFit.coordinates(
        coordinates: overlay.fit,
        padding: widget.padding + const EdgeInsets.all(48),
        maxZoom: overlay.fit.length == 1 ? 16 : 17,
      ),
    );
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
    // Only turning (the phone in the hand): quickly, the map stays with the hand
    final turning = shown != null && shown.position == view.position && shown.zoom == view.zoom;
    final size = _controller.mapController.camera.nonRotatedSize;
    final visibleHeight = size.height - widget.padding.bottom;
    // The user shown this many pixels below the center of the map, which is then that far ahead of them (the
    // animation's own offset doesn't work with a rotation)
    final below = visibleHeight * 0.72 - size.height / 2;
    final metersPerPixel = 156543.03392 * math.cos(view.position.latitudeInRad) / math.pow(2, view.zoom);
    final center = const Distance().offset(view.position, below.abs() * metersPerPixel, below >= 0 ? view.bearing : view.bearing + 180);
    _controller.animateTo(
      dest: center,
      zoom: view.zoom,
      rotation: _closestRotation(-view.bearing),
      duration: Duration(milliseconds: turning ? 250 : 700),
    );
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

  void _stopFollowing() {
    _following = null;
    _shown = null;
    _followPaused = false;
    // North up again, then the page's points are framed
    _framedFit = null;
    if (_ready) {
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
    if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd || event is MapEventDoubleTapZoomEnd ||
        event is MapEventScrollWheelZoom) {
      _centerDebounce?.cancel();
      _centerDebounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) {
          ref.read(mapCenterProvider.notifier).update(_controller.mapController.camera.center);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(routerLocationProvider);
    final overlay = ref.watch(mapOverlaysProvider.select((overlays) => overlays[location])) ?? MapOverlay.empty;
    // Followed (GO on foot): the position the camera follows, so that both agree
    final user = overlay.follow?.position ?? ref.watch(preciseUserPositionProvider) ?? ref.watch(userLocationProvider).value;
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
          _controller.animateTo(dest: position, zoom: 16);
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
                borderColor: path.dotted ? Colors.transparent : Colors.white,
                borderStrokeWidth: path.dotted ? 0 : 1.5,
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

