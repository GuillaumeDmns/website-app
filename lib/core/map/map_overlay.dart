import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../location/device_heading.dart';
import '../utils/geo.dart';

/// Marker drawn on the shared map: a colored dot, or any [child] (e.g. a line badge).
class MapPin {
  const MapPin({
    required this.point,
    required this.color,
    this.icon = Icons.circle,
    this.size = 14,
    this.label,
    this.onTap,
    this.child,
    this.childSize = const Size(40, 28),
    this.above = false,
  });

  final LatLng point;
  final Color color;
  final IconData icon;
  final double size;
  final String? label;
  final VoidCallback? onTap;

  /// Replaces the dot, drawn in a [childSize] box
  final Widget? child;
  final Size childSize;

  /// Draws the marker above the point (like a callout) instead of centered on it
  final bool above;
}

/// Line drawn on the shared map
class MapPath {
  const MapPath({
    required this.points,
    required this.color,
    this.width = 5,
    this.dotted = false,
    this.casing = true,
    this.others = const [],
  });

  final List<LatLng> points;
  final Color color;
  final double width;

  /// Walking paths
  final bool dotted;

  /// On a light edge, so that it stands out from the map's roads
  final bool casing;

  /// More lines drawn the same way, in the same map layer (the trails of a line's vehicles)
  final List<List<LatLng>> others;

  List<List<LatLng>> get parts => [points, ...others];

  /// Drawn the same: the map keeps its layer instead of sending it again
  bool sameAs(MapPath other) =>
      color == other.color &&
      width == other.width &&
      dotted == other.dotted &&
      casing == other.casing &&
      listEquals(points, other.points) &&
      others.length == other.others.length &&
      [for (var i = 0; i < others.length; i++) listEquals(others[i], other.others[i])].every((same) => same);
}

/// The camera following the user (GO on foot or by bike): the way ahead up, the user low in the visible part, close.
class MapFollow {
  const MapFollow({required this.position, required this.bearing, this.zoom = 18, this.compass = false});

  final LatLng position;

  /// Degrees clockwise from north: what is up on the screen
  final double bearing;
  final double zoom;

  /// Where the device points turns the map instead of [bearing] when it is known (the phone in the hand turns, the
  /// map turns): [bearing] is then only the fallback, without compass
  final bool compass;

  MapFollow withBearing(double bearing) => MapFollow(position: position, bearing: bearing, zoom: zoom, compass: compass);

  MapFollow withPosition(LatLng position) => MapFollow(position: position, bearing: bearing, zoom: zoom, compass: compass);

  /// The camera showing [other] only has to move a little, at once (no animation): a smoothed position redrawn several
  /// times a second, or the compass turning it
  bool closeTo(MapFollow other) =>
      zoom == other.zoom &&
      metersBetween(position, other.position) < 8 &&
      headingDelta(bearing, other.bearing).abs() < 25;

  /// Time constants of [glideTo] (s): turns catch up with the hand quickly, moves with the smoothed position
  static const turnLag = 0.07;
  static const moveLag = 0.12;

  /// The camera showing this view [seconds] later on its way to [target]: part of the way (more the longer), [target]
  /// itself once there
  MapFollow glideTo(MapFollow target, double seconds) {
    final turn = 1 - math.exp(-seconds / turnLag);
    final move = 1 - math.exp(-seconds / moveLag);
    final nextBearing = (bearing + headingDelta(bearing, target.bearing) * turn + 360) % 360;
    final nextPosition = LatLng(
      position.latitude + (target.position.latitude - position.latitude) * move,
      position.longitude + (target.position.longitude - position.longitude) * move,
    );
    final there =
        headingDelta(nextBearing, target.bearing).abs() < 0.2 && metersBetween(nextPosition, target.position) < 0.05;
    return there
        ? target
        : MapFollow(position: nextPosition, bearing: nextBearing, zoom: target.zoom, compass: target.compass);
  }

  /// The camera showing [other] doesn't need to move for this one: same place and zoom, less than half a degree apart
  bool sameView(MapFollow other) =>
      position == other.position && zoom == other.zoom && headingDelta(bearing, other.bearing).abs() < 0.5;
}

/// The heading of the follow camera, for the maps: the device's (kept from [deviceHeadingProvider] while the follow
/// asks for it) or the way's
class FollowHeading {
  /// New headings for the camera at most this often (they come about 50 times a second; the map glides between them)
  static const turnInterval = Duration(milliseconds: 20);

  /// The device's last heading, null without compass or while nothing is followed with it
  double? device;

  Timer? _wait;
  bool _pending = false;

  /// [follow] with the device's heading when it asks for it and one is known
  MapFollow apply(MapFollow follow) => follow.compass && device != null ? follow.withBearing(device!) : follow;

  /// Keeps the device's [heading] and calls [turn] now, or at the end of the current [turnInterval]: the last heading
  /// is always shown, even when the device stops turning in between
  void update(double heading, void Function() turn) {
    device = heading;
    if (_wait != null) {
      _pending = true;
      return;
    }
    turn();
    _wait = Timer(turnInterval, () {
      _wait = null;
      if (_pending) {
        _pending = false;
        update(device ?? heading, turn);
      }
    });
  }

  void dispose() => _wait?.cancel();
}

/// What a screen shows on the map, and where the camera should go.
class MapOverlay {
  const MapOverlay({
    this.pins = const [],
    this.paths = const [],
    this.fit = const [],
    this.follow,
  });

  static const empty = MapOverlay();

  final List<MapPin> pins;
  final List<MapPath> paths;

  /// Points to frame when the overlay is shown; empty to leave the camera where it is
  final List<LatLng> fit;

  /// Instead of framing [fit], the camera follows the user (until they move the map themselves)
  final MapFollow? follow;

  MapOverlay withFollow(MapFollow? follow) => MapOverlay(pins: pins, paths: paths, fit: fit, follow: follow);

}

/// Position shown as the user dot instead of the regular one (GO mode: more frequent fixes, smoothed between them); the
/// map following the user follows it too

class PreciseUserPosition extends Notifier<LatLng?> {
  @override
  LatLng? build() => null;

  void set(LatLng? position) => state = position;
}

final preciseUserPositionProvider = NotifierProvider<PreciseUserPosition, LatLng?>(PreciseUserPosition.new);

/// Overlays by route location: the map shows the one of the current page, so going back restores the previous one.
class MapOverlays extends Notifier<Map<String, MapOverlay>> {
  @override
  Map<String, MapOverlay> build() => const {};

  void set(String location, MapOverlay overlay) => state = {...state, location: overlay};

  void remove(String location) {
    // Called after the page is gone: the whole app may be gone too
    if (ref.mounted) {
      state = {...state}..remove(location);
    }
  }
}

final mapOverlaysProvider = NotifierProvider<MapOverlays, Map<String, MapOverlay>>(MapOverlays.new);

/// Location of the page shown in the panel, kept up to date by the router
class RouterLocation extends Notifier<String> {
  @override
  String build() => '/';

  void update(String location) {
    if (location != state) {
      state = location;
    }
  }
}

final routerLocationProvider = NotifierProvider<RouterLocation, String>(RouterLocation.new);

/// Publishes [overlay] for the page it is in while the page exists.
class MapOverlayScope extends ConsumerStatefulWidget {
  const MapOverlayScope({super.key, required this.overlay, required this.child});

  final MapOverlay overlay;
  final Widget child;

  @override
  ConsumerState<MapOverlayScope> createState() => _MapOverlayScopeState();
}

class _MapOverlayScopeState extends ConsumerState<MapOverlayScope> {
  String? _location;
  late final MapOverlays _overlays = ref.read(mapOverlaysProvider.notifier);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _location = GoRouterState.of(context).uri.toString();
    _publish();
  }

  @override
  void didUpdateWidget(MapOverlayScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overlay != widget.overlay) {
      _publish();
    }
  }

  void _publish() {
    final location = _location;
    if (location != null) {
      // Not during build: providers can't be modified while widgets build
      Future.microtask(() {
        if (mounted) {
          _overlays.set(location, widget.overlay);
        }
      });
    }
  }

  @override
  void dispose() {
    final location = _location;
    if (location != null) {
      Future.microtask(() => _overlays.remove(location));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
