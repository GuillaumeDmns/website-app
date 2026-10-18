import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/api/models.dart';
import '../../../core/map/map_overlay.dart';
import '../../../core/utils/colors.dart';
import '../../bikes/bike_widgets.dart';
import '../../../core/utils/geo.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../app/theme.dart';

/// Walks on the map: dark, since the map stays light in dark mode too (the theme's grey is light there)
const walkPathColor = Color(0xFF3C4654);

/// Bike rides on the map: a darker green than [velibColor], which melts into the map's parks
const bikePathColor = Color(0xFF2E7D32);

/// Map overlay of a journey: rides in their line color, bikes green, walks dotted, the line badge where you board, a
/// dot where you get off, small dots at the stops between (named in the sheet, not here: the map stays light), start
/// and end.
///
/// The camera frames the section [fitSection] instead of the whole journey. GO mode: sections before [currentSection]
/// and the first [currentAlong] meters of it are faded.
MapOverlay journeyOverlay(
  BuildContext context,
  JourneyOption journey, {
  int currentSection = -1,
  double currentAlong = 0,
  int? fitSection,
}) {
  final scheme = Theme.of(context).colorScheme;
  final paths = <MapPath>[];
  final stopDots = <MapPin>[];
  final dots = <MapPin>[];
  final badges = <MapPin>[];
  final points = <LatLng>[];
  var sectionPoints = const <LatLng>[];

  for (final (index, section) in journey.sections.indexed) {
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
    if (index == fitSection) {
      sectionPoints = shape;
    }

    final ride = section.kind == SectionKind.transit;
    final bike = section.kind == SectionKind.bike;
    final color = ride
        ? parseHexColor(section.line?.color, scheme.primary)
        : bike
            ? bikePathColor
            : walkPathColor;
    final width = ride ? 6.0 : 5.0;
    // Walks dotted, rides and bikes solid
    final dotted = !ride && !bike;
    // Done part: the line's color faded (plain grey looks like a road on the map)
    final done = color.withValues(alpha: 0.3);
    if (index < currentSection) {
      paths.add(MapPath(points: shape, color: done, width: width, dotted: dotted));
    } else if (index == currentSection && currentAlong > 0) {
      final (before, after) = MeasuredPolyline(shape).split(currentAlong);
      if (before.length >= 2) {
        paths.add(MapPath(points: before, color: done, width: width, dotted: dotted));
      }
      if (after.length >= 2) {
        paths.add(MapPath(points: after, color: color, width: width, dotted: dotted));
      }
    } else {
      paths.add(MapPath(points: shape, color: color, width: width, dotted: dotted));
    }

    if (ride) {
      final stops = section.stops;
      final stopColor = index < currentSection ? done : color;
      // Stops between: smaller dots, under everything else
      for (final (k, stop) in stops.indexed) {
        if (k == 0 || k == stops.length - 1) {
          continue;
        }
        stopDots.add(MapPin(
          point: LatLng(stop.lat, stop.lon),
          color: stopColor,
          label: stop.name,
          childSize: const Size(12, 12),
          child: _StopDot(color: stopColor, size: 9),
        ));
      }
      // Get off: small dot in the line color
      dots.add(MapPin(
        point: shape.last,
        color: color,
        label: section.to?.name,
        childSize: const Size(16, 16),
        child: _StopDot(color: color),
      ));
      // Board: the line badge, above the stop
      if (section.line != null) {
        badges.add(MapPin(
          point: shape.first,
          color: color,
          label: '${section.line!.mode.label} ${section.line!.name ?? ''} · ${section.from?.name ?? ''}',
          above: true,
          childSize: const Size(56, 34),
          child: _BadgeCallout(line: section.line!),
        ));
      }
    }
  }

  final start = journey.sections.firstOrNull?.from;
  final end = journey.sections.lastOrNull?.to;
  return MapOverlay(
    paths: paths,
    pins: [
      ...stopDots,
      ...dots,
      if (start != null) MapPin(point: LatLng(start.lat, start.lon), color: context.colors.live, size: 16, label: start.name),
      ...badges,
      if (end != null) MapPin(point: LatLng(end.lat, end.lon), color: scheme.error, icon: Icons.place, size: 24, label: end.name),
    ],
    fit: sectionPoints.isNotEmpty ? sectionPoints : points,
  );
}

class _StopDot extends StatelessWidget {
  const _StopDot({required this.color, this.size = 12});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: size / 4),
      ),
    );
  }
}

/// Line badge in a small bubble pointing at the boarding stop
class _BadgeCallout extends StatelessWidget {
  const _BadgeCallout({required this.line});

  final LineSummary line;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: LineBadge(line, size: 20),
          ),
          CustomPaint(size: const Size(10, 6), painter: _ArrowPainter(surface)),
        ],
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) => oldDelegate.color != color;
}
