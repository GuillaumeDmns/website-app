import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../location/location_providers.dart';
import 'map_overlay.dart';

/// The map behind every page. Shows the overlay of the current page and the user position, and frames the
/// overlay's points when the page changes.
class MainMap extends ConsumerStatefulWidget {
  const MainMap({super.key, this.padding = EdgeInsets.zero});

  /// Part of the map hidden by the panel, kept out of the framed area
  final EdgeInsets padding;

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

  @override
  void dispose() {
    _centerDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _frame(MapOverlay overlay) {
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

  void _onMapEvent(MapEvent event) {
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
    final user = ref.watch(preciseUserPositionProvider) ?? ref.watch(userLocationProvider).value;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    WidgetsBinding.instance.addPostFrameCallback((_) => _frame(overlay));

    // First fix: go to the user unless a page already framed something
    ref.listen(userLocationProvider, (previous, next) {
      final position = next.value;
      if (position != null && !_centeredOnUser && _ready) {
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
      ),
      children: [
        // Plan IGN (Géoplateforme): free, no key, open licence; no dark style, so it is inverted in dark mode
        TileLayer(
          urlTemplate: 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
              '&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&STYLE=normal&TILEMATRIXSET=PM'
              '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png',
          userAgentPackageName: 'com.guillaumedamiens.website_app',
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
                width: 22,
                height: 22,
                child: const _UserDot(),
              ),
          ],
        ),
        RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [
            TextSourceAttribution('IGN – Plan IGN', onTap: null),
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

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
        ),
      ),
    );
  }
}
