import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/api/models.dart';
import '../../../core/map/map_overlay.dart';
import '../../../core/utils/colors.dart';
import '../../bikes/bike_widgets.dart';
import '../../../core/utils/geo.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/line_badge.dart';

/// Map overlay of a journey: rides in their line color, bikes green, walks dotted, the line badge where you board, a
/// dot where you get off, small dots at the stops between, start and end.
///
/// The camera frames the section [fitSection] instead of the whole journey. The ride [focusSection] (the one looked
/// at, or followed in GO) names its stops with their times. GO mode: sections before [currentSection] and the first
/// [currentAlong] meters of it are faded.
MapOverlay journeyOverlay(
  BuildContext context,
  JourneyOption journey, {
  int currentSection = -1,
  double currentAlong = 0,
  int? fitSection,
  int? focusSection,
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
            ? velibColor
            : scheme.onSurfaceVariant;
    final width = ride ? 6.0 : bike ? 5.0 : 4.0;
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
      final focused = index == focusSection;
      final stops = section.stops;
      final stopColor = index < currentSection ? done : color;
      // Stops between: smaller dots, under everything else
      for (final (k, stop) in stops.indexed) {
        if (k == 0 || k == stops.length - 1) {
          continue;
        }
        final text = _stopText(stop.name, stop.time);
        stopDots.add(focused
            ? MapPin(point: LatLng(stop.lat, stop.lon), color: stopColor, childSize: _namedSize, child: _NamedStop(color: stopColor, text: text, dotSize: 9))
            : MapPin(point: LatLng(stop.lat, stop.lon), color: stopColor, label: text, childSize: const Size(12, 12), child: _StopDot(color: stopColor, size: 9)));
      }
      // Get off: small dot in the line color
      final alightText = _stopText(section.to?.name ?? '', section.arrival);
      dots.add(focused
          ? MapPin(point: shape.last, color: color, childSize: _namedSize, child: _NamedStop(color: color, text: alightText))
          : MapPin(
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
      if (start != null) MapPin(point: LatLng(start.lat, start.lon), color: Colors.green.shade600, size: 16, label: start.name),
      ...badges,
      if (end != null) MapPin(point: LatLng(end.lat, end.lon), color: scheme.error, icon: Icons.place, size: 24, label: end.name),
    ],
    fit: sectionPoints.isNotEmpty ? sectionPoints : points,
    // The stops' names on the right of their dot
    fitMargin: focusSection == null ? EdgeInsets.zero : const EdgeInsets.only(right: 150),
  );
}

String _stopText(String name, DateTime? time) => time == null ? name : '$name · ${formatClock(time)}';

/// Box of a named stop: the dot in its middle, the name on its right
const _namedSize = Size(360, 24);

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

/// A stop of the ride looked at: its dot, and its name and time on a small label beside it
class _NamedStop extends StatelessWidget {
  const _NamedStop({required this.color, required this.text, this.dotSize = 12});

  final Color color;
  final String text;
  final double dotSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelLeft = _namedSize.width / 2 + dotSize / 2 + 4;
    return Stack(
      children: [
        Center(child: _StopDot(color: color, size: dotSize)),
        Positioned(
          left: labelLeft,
          top: 0,
          bottom: 0,
          right: 0,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall),
            ),
          ),
        ),
      ],
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
