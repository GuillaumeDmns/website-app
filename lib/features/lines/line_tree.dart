import 'dart:math' as math;

import '../../core/api/models.dart';
import 'line_vehicles.dart';

/// A stretch of the stop list: the trunk, or a spur hanging from it (or from another spur), its stops in travel order
sealed class LineTreeNode {
  LineTreeNode(this.stops);

  final List<StopRef> stops;

  /// Spurs attached to its stops, nested ones hanging from their own spur
  final List<LineSpur> spurs = [];

  /// Its stops in travel order with the stop it is attached at (a spur), to place vehicles running in or out
  List<StopRef> get sequenceStops;

  List<String> get sequence => [for (final stop in sequenceStops) stop.id];
}

/// The line's main stretch: the stops of its busiest branch
class LineTrunk extends LineTreeNode {
  LineTrunk(super.stops);

  @override
  List<StopRef> get sequenceStops => stops;
}

/// Stops of other branches off the trunk, attached at [attach]: running into it ([merges], a branch from further out,
/// listed before it) or out of it (a branch to its own terminus, after it). Another way between two listed stops
/// leaves [attach] and comes back at [rejoin].
class LineSpur extends LineTreeNode {
  LineSpur({
    required List<StopRef> stops,
    required this.attach,
    required this.merges,
    this.rejoin,
    this.otherWay = false,
  }) : super(stops);

  final StopRef attach;
  final bool merges;

  /// The listed stop it comes back to, for another way between two listed stops
  final StopRef? rejoin;

  /// Stops only the other direction serves (a bus taking other streets back), listed both ways
  final bool otherWay;

  /// Stable while the line's data is: what it is attached at and where it leads
  String get id => '${merges ? 'from' : 'to'}-${attach.id}-${(merges ? stops.first : stops.last).id}';

  /// The stop at its far end: where it comes from when it [merges], where it goes otherwise
  StopRef get end => merges ? stops.first : stops.last;

  @override
  List<StopRef> get sequenceStops => merges ? [...stops, attach] : [attach, ...stops, ?rejoin];

  /// Its stops and those of the spurs hanging from it
  int get stopCount => stops.length + spurs.fold(0, (count, spur) => count + spur.stopCount);
}

/// The stop list of [branches] (one direction, or the branches to one destination) as a tree: the trunk is the
/// busiest branch; each other branch adds the runs of stops not listed yet as spurs, attached where they leave or join
/// what is listed (a run in the middle of a branch, another way between two listed stops, hangs from the stop before
/// it, back at the stop after it). The branches of the [otherWay] (both ways: the other directions' branches) add the
/// stops only they serve the same way, read against their direction.
LineTrunk lineTree(List<LineBranch> branches, {List<LineBranch> otherWay = const []}) {
  final ordered = [...branches]..sort((a, b) => b.tripCount.compareTo(a.tripCount));
  if (ordered.isEmpty) {
    return LineTrunk(const []);
  }
  final trunk = LineTrunk(stopsOnce(ordered.first));
  // Where each listed stop is, to attach spurs to the right node
  final listed = <String, LineTreeNode>{for (final stop in trunk.stops) stop.id: trunk};
  final others = [...otherWay]..sort((a, b) => b.tripCount.compareTo(a.tripCount));
  for (final (branch, reversed) in [
    for (final branch in ordered.skip(1)) (branch, false),
    for (final branch in others) (branch, true),
  ]) {
    final stops = reversed ? stopsOnce(branch).reversed.toList() : stopsOnce(branch);
    var i = 0;
    while (i < stops.length) {
      if (listed.containsKey(stops[i].id)) {
        i++;
        continue;
      }
      final start = i;
      while (i < stops.length && !listed.containsKey(stops[i].id)) {
        i++;
      }
      final run = stops.sublist(start, i);
      // Before the branch's first listed stop: it runs into it; else out of the listed stop before it
      final merges = start == 0;
      if (merges && i >= stops.length) {
        // Nothing in common with what is listed: leave it out (another line's pattern)
        break;
      }
      final attach = merges ? stops[i] : stops[start - 1];
      final spur = LineSpur(
        stops: run,
        attach: attach,
        merges: merges,
        rejoin: merges || i >= stops.length ? null : stops[i],
        otherWay: reversed,
      );
      listed[attach.id]!.spurs.add(spur);
      for (final stop in run) {
        listed[stop.id] = spur;
      }
    }
  }
  return trunk;
}

/// Every node of the tree, the trunk first, then the spurs depth first
List<LineTreeNode> treeNodes(LineTrunk trunk) {
  final nodes = <LineTreeNode>[];
  void visit(LineTreeNode node) {
    nodes.add(node);
    node.spurs.forEach(visit);
  }

  visit(trunk);
  return nodes;
}

/// Where a vehicle is in the tree: standing at [stop] of [node] (an index in its stops), or running in the gap
/// [gap] of its [LineTreeNode.sequence] (between `sequence[gap]` and `sequence[gap + 1]`); [reverse] when it runs
/// against the list's order (the other direction); [direct] when it runs past listed stops without stopping (a train
/// not stopping everywhere)
typedef TreePlacement = ({
  LineTreeNode node,
  int? stop,
  int? gap,
  bool reverse,
  bool direct,
  double position,
  Vehicle vehicle,
});

/// The vehicles in [trunk]'s tree, each in the first node (the trunk first) holding the stop it goes to and the one it
/// left; a vehicle standing at a stop goes to that stop's own node. Vehicles of the other direction are placed too,
/// [TreePlacement.reverse]. Vehicles coming from a stop not listed are left out.
///
/// A vehicle running past listed stops it doesn't serve (a direct train) is placed among them where it is on its own
/// path ([pathOf], the map's place): after the last one it has passed, by distance; without its path, as far through
/// them as it is through its ride in time.
List<TreePlacement> treeVehicles(
  LineTrunk trunk,
  List<({Vehicle vehicle, double progress})> vehicles, {
  BranchPath? Function(Vehicle vehicle)? pathOf,
}) {
  final nodes = treeNodes(trunk);
  final placed = <TreePlacement>[];
  for (final (:vehicle, :progress) in vehicles) {
    for (final node in nodes) {
      final sequence = node.sequence;
      final to = sequence.indexOf(vehicle.toStopId);
      if (to < 0) {
        continue;
      }
      final from = vehicle.fromStopId == null ? -1 : sequence.indexOf(vehicle.fromStopId!);
      if (isAtStop(vehicle, progress) || from == to) {
        final stop = node.stops.indexWhere((stop) => stop.id == vehicle.toStopId);
        if (stop < 0) {
          // The stop a spur is attached at: listed in its own node
          continue;
        }
        placed.add((
          node: node,
          stop: stop,
          gap: null,
          reverse: _runsUp(sequence, vehicle, from, to),
          direct: false,
          position: to.toDouble(),
          vehicle: vehicle,
        ));
        break;
      }
      if (from < 0) {
        continue;
      }
      final reverse = from > to;
      final direct = (to - from).abs() > 1;
      var position = from + (to - from) * progress;
      if (direct) {
        final path = pathOf?.call(vehicle);
        final along = path?.alongOf(vehicle, progress);
        if (path != null && along != null) {
          position = _alongPosition(node.sequenceStops, from, to, path, along) ?? position;
        }
      }
      final gap = position.floor().clamp(math.min(from, to), math.max(from, to) - 1).toInt();
      placed.add((
        node: node,
        stop: null,
        gap: gap,
        reverse: reverse,
        direct: direct,
        position: position,
        vehicle: vehicle,
      ));
      break;
    }
  }
  placed.sort((a, b) => a.position.compareTo(b.position));
  return placed;
}

/// Whether [vehicle], standing at `sequence[to]`, runs up the list: it came from a later stop, else its next stop
/// listed is an earlier one; down the list without either
bool _runsUp(List<String> sequence, Vehicle vehicle, int from, int to) {
  if (from >= 0 && from != to) {
    return from > to;
  }
  for (final call in vehicle.calls) {
    final next = sequence.indexOf(call.stopId);
    if (next >= 0 && next != to) {
      return next < to;
    }
  }
  return false;
}

/// Where a vehicle running from `stops[from]` to `stops[to]` is among the stops between, as a fractional index: the
/// stops between projected on its own [path], it is after the last one it has passed, as far to the next one as it is
/// in meters ([at]: where it is, and where the stops it left and goes to are, along its path); null when a stop between
/// is off its path
double? _alongPosition(List<StopRef> stops, int from, int to, BranchPath path, ({double along, double from, double to}) at) {
  final step = to > from ? 1 : -1;
  var previous = at.from;
  for (var k = from; k != to; k += step) {
    final last = k + step == to;
    final next = last ? at.to : path.alongStop(stops[k + step], minAlong: previous);
    if (next == null) {
      return null;
    }
    if (at.along < next || last) {
      final share = next <= previous ? 0.0 : ((at.along - previous) / (next - previous)).clamp(0.0, 1.0);
      return k + step * share;
    }
    previous = next;
  }
  return to.toDouble();
}
