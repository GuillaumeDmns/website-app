import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/utils/colors.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/time_format.dart';

/// Vehicles of a line and when they were fetched, refreshed every 30 s while shown
final lineVehiclesProvider = FutureProvider.autoDispose.family<({List<Vehicle> vehicles, DateTime fetchedAt}), String>((ref, lineId) async {
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final vehicles = await ref.watch(mobilityApiProvider).lineVehicles(lineId);
  return (vehicles: vehicles, fetchedAt: DateTime.now());
});

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
  LatLng? position(Vehicle vehicle, double progress) {
    final to = stopIds.indexOf(vehicle.toStopId);
    if (to < 0 || line.isEmpty) {
      return null;
    }
    // Stop just left: in this branch when the vehicle serves it, the previous stop otherwise
    final left = vehicle.fromStopId == null ? -1 : stopIds.lastIndexOf(vehicle.fromStopId!, to);
    final from = vehicle.fromStopId == null ? to : left >= 0 ? left : math.max(0, to - 1);
    final along = stopAlongs[from] + (stopAlongs[to] - stopAlongs[from]) * progress;
    return line.pointAt(along);
  }
}

IconData vehicleIcon(TransportMode mode) => switch (mode) {
      TransportMode.metro => Icons.subway,
      TransportMode.rer || TransportMode.transilien || TransportMode.ter => Icons.train,
      TransportMode.tram => Icons.tram,
      _ => Icons.directions_bus,
    };

/// Small round marker in the line's color
class VehicleMarker extends StatelessWidget {
  const VehicleMarker({super.key, required this.line, this.size = 22});

  final LineSummary line;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: parseHexColor(line.color, Colors.grey.shade700),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
      ),
      child: Icon(vehicleIcon(line.mode), size: size * 0.6, color: parseHexColor(line.textColor, Colors.white)),
    );
  }
}

/// `→ Saint-Denis - Pleyel · Madeleine dans 2 min`
String vehicleLabel(Vehicle vehicle, DateTime now) {
  final minutes = vehicle.expectedAt.difference(now).inSeconds / 60;
  final next = vehicle.toStopName ?? '';
  final when = minutes < 0.5 ? 'à quai' : minutes < 60 ? 'dans ${minutes.ceil()} min' : formatClock(vehicle.expectedAt);
  return '→ ${vehicle.destination ?? ''} · $next $when';
}
