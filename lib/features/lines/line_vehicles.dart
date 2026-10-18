import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../app/theme.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/utils/colors.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/refresh.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';

/// Vehicles of a line and when they were fetched, refreshed every minute while shown (the backend keeps them a
/// minute: the estimated-timetable quota is small)
final lineVehiclesProvider = FutureProvider.autoDispose.family<({List<Vehicle> vehicles, DateTime fetchedAt}), String>((ref, lineId) async {
  ref.refreshEvery(const Duration(seconds: 60));
  final vehicles = await ref.watch(mobilityApiProvider).lineVehicles(lineId);
  return (vehicles: vehicles, fetchedAt: DateTime.now());
});

/// Ticks every second while a line's vehicles are shown, so that they glide along their path
final vehicleClockProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);

/// Longest trail drawn behind a moving vehicle, in meters
const maxTrailLength = 500.0;

/// Where a vehicle is on its branch's path
///
/// [heading]: its direction of travel, in degrees clockwise from north; [trail]: the path it just ran since the stop
/// it left (at most [maxTrailLength]), empty when it is waiting at a stop
typedef VehiclePlacement = ({LatLng point, double heading, List<LatLng> trail});

/// Progress of a vehicle between its two stops at [now]: it keeps moving between two fetches, at the pace given by
/// the progress and the expected time at the next stop when fetched
double vehicleProgress(Vehicle vehicle, DateTime fetchedAt, DateTime now) {
  if (vehicle.fromStopId == null || vehicle.progress >= 1) {
    return 1;
  }
  final remainingAtFetch = vehicle.expectedAt.difference(fetchedAt).inMilliseconds;
  if (remainingAtFetch <= 0) {
    return 1;
  }
  final segment = remainingAtFetch / (1 - vehicle.progress);
  final remaining = vehicle.expectedAt.difference(now).inMilliseconds;
  return (1 - remaining / segment).clamp(vehicle.progress, 1.0);
}

/// Path of a branch with the distance of each of its stops along it, to place vehicles
class BranchPath {
  BranchPath(LineBranch branch)
      : line = MeasuredPolyline(branch.shape.isNotEmpty
            ? [for (final point in branch.shape) LatLng(point[1], point[0])]
            : [for (final stop in branch.stops) LatLng(stop.lat, stop.lon)]),
        stopIds = [for (final stop in branch.stops) stop.id] {
    var minAlong = 0.0;
    for (final stop in branch.stops) {
      final along = line.project(LatLng(stop.lat, stop.lon), minAlong: minAlong)?.along ?? minAlong;
      stopAlongs.add(along);
      minAlong = along;
    }
  }

  final MeasuredPolyline line;
  final List<String> stopIds;
  final List<double> stopAlongs = [];

  /// Where [vehicle] is at [progress] between its two stops, null when they are not on this branch
  LatLng? position(Vehicle vehicle, double progress) => place(vehicle, progress)?.point;

  /// Where [vehicle] is at [progress] between its two stops, which way it goes and the path it just ran; null when
  /// they are not on this branch
  VehiclePlacement? place(Vehicle vehicle, double progress) {
    final to = stopIds.indexOf(vehicle.toStopId);
    if (to < 0 || line.isEmpty) {
      return null;
    }
    // Stop just left: in this branch when the vehicle serves it, the previous stop otherwise
    final left = vehicle.fromStopId == null ? -1 : stopIds.lastIndexOf(vehicle.fromStopId!, to);
    final from = vehicle.fromStopId == null ? to : left >= 0 ? left : math.max(0, to - 1);
    final along = stopAlongs[from] + (stopAlongs[to] - stopAlongs[from]) * progress;
    // The way ahead around it (the branch's direction at a stop where it waits)
    const around = 20.0;
    final ahead = math.min(along + around, line.length);
    final behind = math.max(ahead - 2 * around, 0.0);
    final moving = from != to && progress < 1;
    return (
      point: line.pointAt(along),
      heading: bearingBetween(line.pointAt(behind), line.pointAt(ahead)),
      trail: moving ? line.between(math.max(stopAlongs[from], along - maxTrailLength), along) : const <LatLng>[],
    );
  }
}

/// Vehicles on the stop list of [branch], by the stop they are closest to, with their offset from it (between -0.5
/// and 0.5): their fractional stop index between the stop they left and the next one. Vehicles of other branches
/// are shown where they run on this one: the stop they left must be on it too, so that a train coming from another
/// branch to where both merge is not drawn on this one's last segment.
Map<int, List<({double offset, Vehicle vehicle})>> stopListPositions(
  LineBranch? branch,
  List<({Vehicle vehicle, double progress})> vehicles,
) {
  final positions = <int, List<({double offset, Vehicle vehicle})>>{};
  final stopIds = [for (final stop in branch?.stops ?? const <StopRef>[]) stop.id];
  for (final (:vehicle, :progress) in vehicles) {
    final to = stopIds.indexOf(vehicle.toStopId);
    if (to < 0) {
      continue;
    }
    // The stop left may be several stops back (stops it doesn't serve)
    final from = vehicle.fromStopId == null ? to : stopIds.lastIndexOf(vehicle.fromStopId!, to);
    if (from < 0) {
      continue;
    }
    final position = from + (to - from) * progress;
    positions.putIfAbsent(position.round(), () => []).add((offset: position - position.round(), vehicle: vehicle));
  }
  return positions;
}

IconData vehicleIcon(TransportMode mode) => switch (mode) {
      TransportMode.metro => Icons.subway,
      TransportMode.rer || TransportMode.transilien || TransportMode.ter => Icons.train,
      TransportMode.tram => Icons.tram,
      _ => Icons.directions_bus,
    };

/// How on time a vehicle is, for the ring of its marker
enum Punctuality {
  /// No delay given
  unknown,
  onTime,
  late;

  /// Late from a minute, like the delays shown in the vehicle sheet
  static Punctuality of(Vehicle vehicle) => switch (vehicle.delaySeconds) {
        null => unknown,
        final delay when delay >= 60 => late,
        _ => onTime,
      };
}

/// Round marker in the line's color, its ring telling how on time it is (white when unknown). With a [heading] (degrees
/// clockwise from the top of the screen), a pointer shows which way it goes; [stale] (missing from the latest real
/// time) fades it.
class VehicleMarker extends StatelessWidget {
  const VehicleMarker({
    super.key,
    required this.line,
    this.size = 22,
    this.heading,
    this.punctuality = Punctuality.unknown,
    this.stale = false,
  });

  final LineSummary line;
  final double size;
  final double? heading;
  final Punctuality punctuality;
  final bool stale;

  /// Box of a marker with a pointer: the pointer goes beyond the circle
  static double boxSize(double size) => size + 22;

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(line.color, Colors.grey.shade700);
    final ring = switch (punctuality) {
      Punctuality.unknown => Colors.white,
      Punctuality.onTime => context.colors.live,
      Punctuality.late => context.colors.delayed,
    };
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: punctuality == Punctuality.unknown ? 2 : 2.5),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
      ),
      child: Icon(vehicleIcon(line.mode), size: size * 0.6, color: parseHexColor(line.textColor, Colors.white)),
    );
    final heading = this.heading;
    final marker = heading == null
        ? circle
        : SizedBox.square(
            dimension: boxSize(size),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: heading * math.pi / 180,
                  child: CustomPaint(size: Size.square(boxSize(size)), painter: _PointerPainter(radius: size / 2)),
                ),
                circle,
              ],
            ),
          );
    return stale ? Opacity(opacity: 0.45, child: marker) : marker;
  }
}

/// A dark triangle pointing up, just outside a circle of [radius] at the center: dark, since it points along the line
/// drawn in the line's color
class _PointerPainter extends CustomPainter {
  const _PointerPainter({required this.radius});

  static const color = Color(0xFF1F2933);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final tip = center.dy - radius - 10;
    final base = center.dy - radius + 1;
    final path = Path()
      ..moveTo(center.dx, tip)
      ..lineTo(center.dx - 7, base)
      ..lineTo(center.dx + 7, base)
      ..close();
    // With a white edge, like the circle
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.radius != radius;
}

/// `→ Saint-Denis - Pleyel · Madeleine dans 2 min`
String vehicleLabel(Vehicle vehicle, DateTime now) {
  final minutes = vehicle.expectedAt.difference(now).inSeconds / 60;
  final next = vehicle.toStopName ?? '';
  final when = minutes < 0.5
      ? currentL10n.vehicleAtStop
      : minutes < 60
          ? currentL10n.inMinutes(minutes.ceil())
          : formatClock(vehicle.expectedAt);
  return '→ ${vehicle.destination ?? ''} · $next $when';
}
