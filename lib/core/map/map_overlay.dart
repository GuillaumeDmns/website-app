import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

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
  const MapPath({required this.points, required this.color, this.width = 5, this.dotted = false});

  final List<LatLng> points;
  final Color color;
  final double width;

  /// Walking paths
  final bool dotted;
}

/// What a screen shows on the map, and where the camera should go.
class MapOverlay {
  const MapOverlay({this.pins = const [], this.paths = const [], this.fit = const []});

  static const empty = MapOverlay();

  final List<MapPin> pins;
  final List<MapPath> paths;

  /// Points to frame when the overlay is shown; empty to leave the camera where it is
  final List<LatLng> fit;
}

/// Overlays by route location: the map shows the one of the current page, so going back restores the previous one.
class MapOverlays extends Notifier<Map<String, MapOverlay>> {
  @override
  Map<String, MapOverlay> build() => const {};

  void set(String location, MapOverlay overlay) => state = {...state, location: overlay};

  void remove(String location) => state = {...state}..remove(location);
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
