import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show Distance, LatLng;

import '../../l10n/l10n.dart';
import '../location/location_providers.dart';
import 'map_overlay.dart';

/// Background tiles of the map (Plan IGN); the tests turn them off (no network)
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

/// The map behind every page. Shows the overlay of the current page and the user position, and frames the
/// overlay's points when the page changes.
class MainMap extends ConsumerStatefulWidget {
  const MainMap({super.key, this.padding = EdgeInsets.zero, this.onLongPress});

  /// Part of the map hidden by the panel, kept out of the framed area
  final EdgeInsets padding;

  /// Long press (right click on desktop) on a point of the map
  final void Function(BuildContext context, LatLng position)? onLongPress;

  @override
  ConsumerState<MainMap> createState() => _MainMapState();
}

class _MainMapState extends ConsumerState<MainMap> with TickerProviderStateMixin {
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

  @override
  void dispose() {
    _centerDebounce?.cancel();
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
        padding: widget.padding + const EdgeInsets.all(48) + overlay.fitMargin,
        maxZoom: overlay.fit.length == 1 ? 16 : 17,
      ),
    );
  }

  /// The user low in the visible part (above the panel), the way ahead up
  void _follow(MapFollow follow) {
    final previous = _following;
    _following = follow;
    if (!_ready || _followPaused) {
      return;
    }
    if (previous != null && previous.position == follow.position && (previous.bearing - follow.bearing).abs() < 2 &&
        previous.zoom == follow.zoom && _controller.mapController.camera.zoom == follow.zoom) {
      return;
    }
    final size = _controller.mapController.camera.nonRotatedSize;
    final visibleHeight = size.height - widget.padding.bottom;
    // The user shown this many pixels below the center of the map, which is then that far ahead of them (the
    // animation's own offset doesn't work with a rotation)
    final below = visibleHeight * 0.72 - size.height / 2;
    final metersPerPixel = 156543.03392 * math.cos(follow.position.latitudeInRad) / math.pow(2, follow.zoom);
    final center = const Distance().offset(follow.position, below.abs() * metersPerPixel, below >= 0 ? follow.bearing : follow.bearing + 180);
    _controller.animateTo(
      dest: center,
      zoom: follow.zoom,
      rotation: _closestRotation(-follow.bearing),
      duration: const Duration(milliseconds: 700),
    );
  }

  void _stopFollowing() {
    _following = null;
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    WidgetsBinding.instance.addPostFrameCallback((_) => _frame(overlay));

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
        // Plan IGN (Géoplateforme): free, no key, open licence; no dark style, so it is inverted in dark mode
        if (ref.watch(mapTilesEnabledProvider))
          TileLayer(
            urlTemplate: 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
                '&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&STYLE=normal&TILEMATRIXSET=PM'
                '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png',
            userAgentPackageName: 'com.guillaumedamiens.app',
            maxNativeZoom: 19,
            tileBuilder: dark ? darkModeTileBuilder : null,
          ),
        PolylineLayer(
          polylines: [
            for (final path in overlay.paths)
              Polyline(
                points: path.points,
                color: path.color,
                strokeWidth: path.width,
                pattern: path.dotted ? StrokePattern.dotted(spacingFactor: 2) : const StrokePattern.solid(),
                borderColor: path.dotted ? Colors.transparent : (dark ? Colors.black54 : Colors.white),
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
                child: _PinView(pin: pin, outline: scheme.surface),
              ),
            if (user != null)
              Marker(
                point: user,
                width: 72,
                height: 72,
                child: _UserDot(heading: overlay.follow?.bearing),
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

class _PinView extends StatelessWidget {
  const _PinView({required this.pin, required this.outline});

  final MapPin pin;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: pin.size,
      height: pin.size,
      decoration: BoxDecoration(
        color: pin.color,
        shape: BoxShape.circle,
        border: Border.all(color: outline, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
      child: pin.icon == Icons.circle ? null : Icon(pin.icon, size: pin.size * 0.6, color: Colors.white),
    );

    final marker = pin.child ?? dot;
    final child = Center(child: pin.label == null ? marker : Tooltip(message: pin.label!, child: marker));
    if (pin.onTap == null) {
      return child;
    }
    // A button for screen readers, named by the label
    return Semantics(
      button: true,
      label: pin.label,
      excludeSemantics: pin.label != null,
      child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: pin.onTap, child: child)),
    );
  }
}

/// The user's position; with a [heading] (degrees from north), a cone in that direction
class _UserDot extends StatelessWidget {
  const _UserDot({this.heading});

  final double? heading;

  @override
  Widget build(BuildContext context) {
    final heading = this.heading;
    // The marker stays upright: the heading on the screen is the map's rotation plus the heading
    final rotation = heading == null ? null : (heading + MapCamera.of(context).rotation) * math.pi / 180;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (rotation != null)
          Transform.rotate(angle: rotation, child: const CustomPaint(size: Size(72, 72), painter: _HeadingPainter())),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: _dot(),
        ),
      ],
    );
  }

  Widget _dot() {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
    );
  }
}

/// A soft cone pointing up, from the center of the box
class _HeadingPainter extends CustomPainter {
  const _HeadingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx - size.width * 0.3, size.height * 0.04)
      ..quadraticBezierTo(center.dx, -size.height * 0.06, center.dx + size.width * 0.3, size.height * 0.04)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.blue.withValues(alpha: 0.8), Colors.blue.withValues(alpha: 0.05)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, center.dy)),
    );
  }

  @override
  bool shouldRepaint(_HeadingPainter oldDelegate) => false;
}
