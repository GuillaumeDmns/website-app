import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/models.dart';
import '../../../core/map/map_overlay.dart';
import '../../../core/utils/colors.dart';

/// Map overlay of a journey: rides in their line color, walks dotted, start, end and transfer points.
MapOverlay journeyOverlay(BuildContext context, JourneyOption journey, {bool faded = false}) {
  final scheme = Theme.of(context).colorScheme;
  final paths = <MapPath>[];
  final pins = <MapPin>[];
  final points = <LatLng>[];

  for (final section in journey.sections) {
    final shape = section.shape.isNotEmpty
        ? [for (final point in section.shape) LatLng(point[1], point[0])]
        : [
            if (section.from != null) LatLng(section.from!.lat, section.from!.lon),
            if (section.to != null) LatLng(section.to!.lat, section.to!.lon),
          ];
    if (shape.length < 2) {
      continue;
    }
    points.addAll(shape);

    final isRide = section.kind == SectionKind.transit;
    final color = isRide ? parseHexColor(section.line?.color, scheme.primary) : scheme.onSurfaceVariant;
    paths.add(MapPath(
      points: shape,
      color: faded ? color.withValues(alpha: 0.6) : color,
      width: isRide ? 6 : 4,
      dotted: !isRide,
    ));

    if (isRide) {
      for (final end in [shape.first, shape.last]) {
        pins.add(MapPin(point: end, color: color, size: 10));
      }
    }
  }

  final start = journey.sections.firstOrNull?.from;
  final end = journey.sections.lastOrNull?.to;
  if (start != null) {
    pins.add(MapPin(point: LatLng(start.lat, start.lon), color: Colors.green.shade600, size: 16, label: start.name));
  }
  if (end != null) {
    pins.add(MapPin(point: LatLng(end.lat, end.lon), color: scheme.error, icon: Icons.place, size: 24, label: end.name));
  }

  return MapOverlay(paths: paths, pins: pins, fit: points);
}
