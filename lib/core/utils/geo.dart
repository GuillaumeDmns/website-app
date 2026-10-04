import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const _earthRadius = 6371000.0;

/// Great-circle distance in meters
double metersBetween(LatLng a, LatLng b) {
  final dLat = _radians(b.latitude - a.latitude);
  final dLon = _radians(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radians(a.latitude)) * math.cos(_radians(b.latitude)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadius * math.asin(math.min(1, math.sqrt(h)));
}

double _radians(double degrees) => degrees * math.pi / 180;

/// Where a point falls on a [MeasuredPolyline]
class PolylineProjection {
  const PolylineProjection({required this.point, required this.along, required this.distance});

  /// Closest point of the line
  final LatLng point;

  /// Meters from the start of the line to [point]
  final double along;

  /// Meters from the projected point to the line
  final double distance;
}

/// Polyline with the distance from its start to each point, to project positions on it and cut it.
class MeasuredPolyline {
  MeasuredPolyline(List<LatLng> points)
      : points = points.isEmpty ? const [] : points,
        cumulative = _cumulative(points);

  final List<LatLng> points;

  /// Meters from the start to each point
  final List<double> cumulative;

  double get length => cumulative.isEmpty ? 0 : cumulative.last;

  bool get isEmpty => points.isEmpty;

  static List<double> _cumulative(List<LatLng> points) {
    final result = <double>[];
    var total = 0.0;
    for (var i = 0; i < points.length; i++) {
      if (i > 0) {
        total += metersBetween(points[i - 1], points[i]);
      }
      result.add(total);
    }
    return result;
  }

  /// Closest point of the line to [position], only looking at the part after [minAlong] meters (so that a line
  /// passing twice near the same place does not send the progress back).
  PolylineProjection? project(LatLng position, {double minAlong = 0}) {
    if (points.isEmpty) {
      return null;
    }
    if (points.length == 1) {
      return PolylineProjection(point: points.first, along: 0, distance: metersBetween(position, points.first));
    }

    // Local flat projection around the position: precise enough at city scale
    final cosLat = math.cos(_radians(position.latitude));
    double x(LatLng p) => _radians(p.longitude - position.longitude) * cosLat * _earthRadius;
    double y(LatLng p) => _radians(p.latitude - position.latitude) * _earthRadius;

    PolylineProjection? best;
    for (var i = 0; i < points.length - 1; i++) {
      if (cumulative[i + 1] < minAlong) {
        continue;
      }
      final ax = x(points[i]), ay = y(points[i]);
      final bx = x(points[i + 1]), by = y(points[i + 1]);
      final dx = bx - ax, dy = by - ay;
      final lengthSquared = dx * dx + dy * dy;
      var t = lengthSquared == 0 ? 0.0 : ((-ax) * dx + (-ay) * dy) / lengthSquared;
      t = t.clamp(0.0, 1.0);
      final px = ax + t * dx, py = ay + t * dy;
      final distance = math.sqrt(px * px + py * py);
      if (best == null || distance < best.distance) {
        final along = cumulative[i] + t * (cumulative[i + 1] - cumulative[i]);
        best = PolylineProjection(
          point: LatLng(
            points[i].latitude + t * (points[i + 1].latitude - points[i].latitude),
            points[i].longitude + t * (points[i + 1].longitude - points[i].longitude),
          ),
          along: along,
          distance: distance,
        );
      }
    }
    return best;
  }

  /// Point [along] meters from the start
  LatLng pointAt(double along) {
    if (points.length < 2 || along <= 0) {
      return points.first;
    }
    for (var i = 1; i < points.length; i++) {
      if (cumulative[i] >= along) {
        final segment = cumulative[i] - cumulative[i - 1];
        final t = segment == 0 ? 0.0 : (along - cumulative[i - 1]) / segment;
        return LatLng(
          points[i - 1].latitude + t * (points[i].latitude - points[i - 1].latitude),
          points[i - 1].longitude + t * (points[i].longitude - points[i - 1].longitude),
        );
      }
    }
    return points.last;
  }

  /// The line cut at [along] meters: the part before and the part after
  (List<LatLng>, List<LatLng>) split(double along) {
    if (points.length < 2 || along <= 0) {
      return (const [], points);
    }
    if (along >= length) {
      return (points, const []);
    }
    final cut = pointAt(along);
    final index = cumulative.indexWhere((distance) => distance >= along);
    return ([...points.sublist(0, index), cut], [cut, ...points.sublist(index)]);
  }
}
