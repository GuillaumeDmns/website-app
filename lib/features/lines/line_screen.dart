import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../app/shell.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/map/map_overlay.dart';
import '../../core/platform/share.dart';
import '../../core/utils/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/line_badge.dart';
import '../../core/widgets/ui.dart';
import '../../core/location/location_providers.dart';
import '../../l10n/l10n.dart';
import '../favorites/favorite_widgets.dart';
import '../service_hours/service_hours.dart';
import '../traffic/disruption_widgets.dart';
import '../traffic/traffic_providers.dart';
import 'line_tree.dart';
import 'line_vehicles.dart';
import 'vehicle_sheet.dart';
import 'widgets/line_stop_tile.dart';

final lineDetailProvider = FutureProvider.autoDispose.family<LineDetail, String>(
  (ref, lineId) => ref.mobilityApi.line(lineId),
);

class LineScreen extends ConsumerStatefulWidget {
  const LineScreen({super.key, required this.lineId});

  final String lineId;

  @override
  ConsumerState<LineScreen> createState() => _LineScreenState();
}

class _LineScreenState extends ConsumerState<LineScreen> {
  /// Direction shown, null for both ways (the default: the whole line, every vehicle)
  int? _direction;

  /// Destination shown in that direction (a branch's headsign), null for all of them
  String? _destination;

  /// Branches unfolded in the stop list, by [LineSpur.id]
  final _unfolded = <String>{};

  /// Measured path of each branch, computed once
  final _paths = Expando<BranchPath>();

  BranchPath _pathOf(LineBranch branch) => _paths[branch] ??= BranchPath(branch);

  /// Vehicle the map keeps in view ("Suivre" in its sheet), until stopped or gone
  String? _followed;

  void _follow(Vehicle vehicle) => setState(() => _followed = vehicle.id);

  /// Vehicle whose sheet is open, shown selected on the map like the one followed
  String? _opened;

  /// Opens [vehicle]'s sheet, the vehicle selected on the map while it is open
  Future<void> _open(LineSummary line, Vehicle vehicle) async {
    setState(() => _opened = vehicle.id);
    await showVehicleSheet(context, line: line, vehicle: vehicle, onFollow: () => _follow(vehicle));
    if (mounted && _opened == vehicle.id) {
      setState(() => _opened = null);
    }
  }

  /// The direction the stop list follows: the one chosen, else the first one (both ways, the other direction's
  /// vehicles run up the list)
  LineDirection? _listedDirection(LineDetail detail) =>
      detail.directions.isEmpty ? null : detail.directions[(_direction ?? 0).clamp(0, detail.directions.length - 1)];

  /// The branches the filter shows: those of the direction listed, to the destination chosen
  List<LineBranch> _shownBranches(LineDetail detail) => [
        for (final branch in _listedDirection(detail)?.branches ?? const <LineBranch>[])
          if (_destination == null || branch.headsign == _destination) branch,
      ];

  /// Whether [vehicle] is in the filter: both ways every vehicle, else the direction's, to the destination chosen
  bool _matches(LineDetail detail, Vehicle vehicle) {
    final direction = _direction;
    if (direction == null) {
      return true;
    }
    return vehicle.direction == direction && (_destination == null || headsignOf(detail, vehicle) == _destination);
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(lineDetailProvider(widget.lineId));
    final value = detail.value;

    // The vehicles move every second: only the map and the stop list follow them, the rest of the page is kept
    return Consumer(
      builder: (context, ref, content) {
        final (:vehicles, :now) = _vehicles(ref, value);
        return MapOverlayScope(
          overlay: value == null ? MapOverlay.empty : _overlay(value, vehicles, now),
          child: content!,
        );
      },
      child: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(lineDetailProvider(widget.lineId)),
        page: true,
        data: (detail) => _content(context, detail),
      ),
    );
  }

  /// Every vehicle of the line, moved along between two fetches (every second while there are some): on their
  /// segment, standing at the stop, then on to the following stops of their branch
  ({List<({Vehicle vehicle, double progress})> vehicles, DateTime now}) _vehicles(WidgetRef ref, LineDetail? detail) {
    final fetched = ref.watch(lineVehiclesProvider(widget.lineId)).value;
    final now = (fetched?.vehicles.isNotEmpty ?? false)
        ? ref.watch(vehicleClockProvider).value ?? DateTime.now()
        : ref.watch(nowProvider).value ?? DateTime.now();
    if (fetched == null || detail == null) {
      return (vehicles: const [], now: now);
    }
    return (
      vehicles: [
        for (final vehicle in fetched.vehicles)
          vehicleAt(
            vehicle,
            fetched.fetchedAt,
            now,
            detail.line.mode,
            serves: _branchStops(detail, vehicle)?.contains,
          ),
      ],
      now: now,
    );
  }

  /// The path of the branch [vehicle] runs on, null when the line has no such branch
  BranchPath? _vehiclePath(LineDetail detail, Vehicle vehicle) {
    if (vehicle.direction >= detail.directions.length) {
      return null;
    }
    final branches = detail.directions[vehicle.direction].branches;
    return vehicle.branch < branches.length ? _pathOf(branches[vehicle.branch]) : null;
  }

  /// Stop areas of the branch [vehicle] runs on, null when the line has no such branch
  static Set<String>? _branchStops(LineDetail detail, Vehicle vehicle) {
    if (vehicle.direction >= detail.directions.length) {
      return null;
    }
    final branches = detail.directions[vehicle.direction].branches;
    return vehicle.branch < branches.length ? {for (final stop in branches[vehicle.branch].stops) stop.id} : null;
  }

  /// The whole line by default: every branch and every vehicle. A filter draws what it leaves out faded, the camera
  /// framing what it keeps.
  MapOverlay _overlay(LineDetail detail, List<({Vehicle vehicle, double progress})> vehicles, DateTime now) {
    final line = detail.line;
    final color = parseHexColor(line.color, Colors.grey);
    List<LatLng> points(LineBranch branch) => _pathOf(branch).line.points;

    // Both ways, every direction's branches: a bus's two ways often take different streets
    final shown = _direction == null
        ? [for (final direction in detail.directions) ...direction.branches]
        : _shownBranches(detail);
    final faded = [
      if (_direction != null)
        for (final branch in _listedDirection(detail)?.branches ?? const <LineBranch>[])
          if (!shown.contains(branch)) branch,
    ];
    final chosen = _followed ?? _opened;
    final placed = [
      for (final (:vehicle, :progress) in vehicles)
        if (vehicle.direction < detail.directions.length &&
            vehicle.branch < detail.directions[vehicle.direction].branches.length)
          if (_pathOf(detail.directions[vehicle.direction].branches[vehicle.branch])
                  .place(vehicle, progress)
              case final place?)
            (vehicle: vehicle, place: place, atStop: isAtStop(vehicle, progress), faded: !_matches(detail, vehicle)),
    ]
      // The ones the filter leaves out under the others, the selected one on top
      ..sort((a, b) => _layer(a.vehicle, a.faded, chosen).compareTo(_layer(b.vehicle, b.faded, chosen)));
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final stops = <String, StopRef>{
      for (final branch in shown)
        for (final stop in branch.stops) stop.id: stop,
    };
    return MapOverlay(
      paths: [
        for (final branch in faded) MapPath(points: points(branch), color: color.withValues(alpha: 0.35), width: 4),
        for (final branch in shown) MapPath(points: points(branch), color: color, width: 6),
      ],
      pins: [
        for (final stop in stops.values)
          MapPin(
            point: LatLng(stop.lat, stop.lon),
            color: color,
            size: 8,
            label: stop.name,
            onTap: () => context.push(Routes.stop(stop.id)),
          ),
        for (final (:vehicle, :place, :atStop, :faded) in placed) ...[
          // The whole capsule turned the way it goes, with the map
          MapPin(
            point: place.point,
            color: color,
            rotation: place.heading,
            label: vehicleLabel(vehicle, now, line.mode),
            onTap: () => _open(line, vehicle),
            childSize: Size.square(VehicleCapsule.boxSize(selected: vehicle.id == chosen)),
            image: VehicleCapsule.imageName(line, atStop: atStop, selected: vehicle.id == chosen, faded: faded),
            child: VehicleCapsule(line: line, atStop: atStop, selected: vehicle.id == chosen, faded: faded),
          ),
          if (vehicle.id == chosen) _callout(vehicle, now, line.mode, atStop: atStop, at: place.point, fontFamily: fontFamily),
        ],
      ],
      fit: [for (final branch in shown) ...points(branch)],
    ).withFollow(_followView(placed));
  }

  /// Drawing order on the map: left out by the filter, then the others, then the selected one
  static int _layer(Vehicle vehicle, bool faded, String? chosen) => vehicle.id == chosen ? 2 : faded ? 0 : 1;

  /// Over the selected vehicle: its next stop, when it gets there and its delay
  static MapPin _callout(
    Vehicle vehicle,
    DateTime now,
    TransportMode mode, {
    required bool atStop,
    required LatLng at,
    String? fontFamily,
  }) {
    final stop = vehicle.toStopName ?? '';
    final when = vehicleWhen(vehicle, now, mode, atStop: atStop);
    final delay = vehicleDelay(vehicle);
    final callout = VehicleCallout(stop: stop, when: when, delay: delay, fontFamily: fontFamily);
    return MapPin(
      point: at,
      color: Colors.black,
      above: true,
      childSize: VehicleCallout.sizeOf(stop: stop, when: when, delay: delay, fontFamily: fontFamily),
      image: callout.imageName,
      child: callout,
    );
  }

  /// The camera on the vehicle followed, north up; it stops when the vehicle is gone
  MapFollow? _followView(List<({Vehicle vehicle, VehiclePlacement place, bool atStop, bool faded})> placed) {
    final followed = _followed;
    if (followed == null) {
      return null;
    }
    final place = placed.where((entry) => entry.vehicle.id == followed).firstOrNull?.place;
    if (place == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _followed = null);
        }
      });
      return null;
    }
    return MapFollow.overhead(place.point);
  }

  Widget _content(BuildContext context, LineDetail detail) {
    final closed = ref.watch(lineClosedStopsProvider(detail.line.id)).value ?? const <String>{};
    final theme = Theme.of(context);
    final line = detail.line;
    final color = parseHexColor(line.color, theme.colorScheme.primary);
    final shown = _shownBranches(detail);
    final direction = _direction == null ? null : _listedDirection(detail);
    final destinations = direction == null ? const <String>[] : destinationsOf(direction);

    return ListView(
      controller: PanelScrollScope.of(context),
      padding: const EdgeInsets.fromLTRB(4, 0, 16, 32),
      children: [
        Row(
          children: [
            IconButton(tooltip: context.l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
            const Spacer(),
            FavoriteLineButton(line: line),
            IconButton(
              tooltip: context.l10n.share,
              icon: const Icon(Icons.ios_share),
              onPressed: () => shareLink(
                context,
                title: line.label,
                location: Routes.line(line.id),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              LineBadge(line, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.label, style: theme.textTheme.headlineSmall),
                    if (line.longName != null && line.longName != line.name && line.longName != line.label)
                      Text(line.longName!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 0, 0),
          child: _LineDisruptions(line: line),
        ),
        // Both ways, then each direction (design: direction, then destination)
        if (detail.directions.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 0, 0),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              segments: [
                ButtonSegment(value: -1, label: Text(context.l10n.lineBothDirections, maxLines: 2, textAlign: TextAlign.center)),
                for (var i = 0; i < detail.directions.length; i++)
                  ButtonSegment(
                    value: i,
                    label: Text(directionLabel(detail.directions[i]), maxLines: 2, textAlign: TextAlign.center),
                  ),
              ],
              selected: {_direction ?? -1},
              onSelectionChanged: (selection) => setState(() {
                _direction = selection.first < 0 ? null : selection.first;
                _destination = null;
                _unfolded.clear();
              }),
            ),
          ),
        // Its destinations, when it has several (the branches of a fork)
        if (direction != null && destinations.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
            child: Consumer(builder: (context, ref, _) {
              final fetched = ref.watch(lineVehiclesProvider(widget.lineId)).value?.vehicles ?? const <Vehicle>[];
              int count(String destination) => fetched
                  .where((vehicle) => vehicle.direction == _direction && headsignOf(detail, vehicle) == destination)
                  .length;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(context.l10n.lineAllDestinations),
                    selected: _destination == null,
                    onSelected: (_) => setState(() {
                      _destination = null;
                      _unfolded.clear();
                    }),
                  ),
                  for (final destination in destinations)
                    ChoiceChip(
                      label: Text(count(destination) == 0 ? destination : '$destination · ${count(destination)}'),
                      selected: _destination == destination,
                      onSelected: (_) => setState(() {
                        _destination = _destination == destination ? null : destination;
                        _unfolded.clear();
                      }),
                    ),
                ],
              );
            }),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
          child: LineServiceHoursSummary(lineId: line.id, direction: (_direction ?? 0).clamp(0, math.max(0, detail.directions.length - 1))),
        ),
        if (_followed != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.my_location, size: 18),
                label: Text(context.l10n.vehicleFollowing),
                deleteButtonTooltipMessage: context.l10n.vehicleStopFollowing,
                onDeleted: () => setState(() => _followed = null),
              ),
            ),
          ),
        if (shown.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: Consumer(builder: (context, ref, _) {
                final (:vehicles, :now) = _vehicles(ref, detail);
                final listed = [
                  for (final entry in vehicles)
                    if (_matches(detail, entry.vehicle)) entry,
                ];
                // Both ways, the stops only the other direction serves too (a bus taking other streets back)
                final trunk = lineTree(
                  shown,
                  otherWay: _direction != null
                      ? const []
                      : [
                          for (final other in detail.directions.skip(1)) ...other.branches,
                        ],
                );
                final fetchedAt = ref.watch(lineVehiclesProvider(widget.lineId)).value?.fetchedAt;
                final rows = _TreeRows(
                  line: line,
                  color: color,
                  now: now,
                  closed: closed,
                  placements: treeVehicles(trunk, listed, pathOf: (vehicle) => _vehiclePath(detail, vehicle)),
                  width: railWidth(treeDepth(trunk)),
                  unfolded: _unfolded,
                  onToggle: (id) => setState(() => _unfolded.contains(id) ? _unfolded.remove(id) : _unfolded.add(id)),
                  onOpen: (vehicle) => _open(line, vehicle),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (fetchedAt != null && listed.isNotEmpty)
                      _LiveVehiclesHeader(
                        count: listed.length,
                        mode: line.mode,
                        destination: direction == null ? null : _destination ?? termini(direction).join(' / '),
                        fetchedAt: fetchedAt,
                        now: now,
                      ),
                    ...rows.of(trunk, lane: 0, passing: const {}),
                  ],
                );
              }),
            ),
          ),
      ],
    );
  }
}

/// The rows of the stop list for a tree of branches: each node's stops on its lane, its vehicles standing at them or
/// running between them, the branches off it folded on a row (unfolded: their own stops on the next lane)
class _TreeRows {
  _TreeRows({
    required this.line,
    required this.color,
    required this.now,
    required this.closed,
    required List<TreePlacement> placements,
    required this.width,
    required this.unfolded,
    required this.onToggle,
    required this.onOpen,
  }) {
    for (final placement in placements) {
      if (placement.stop case final stop?) {
        (_standing[placement.node] ??= {}).putIfAbsent(stop, () => []).add(placement);
      } else {
        (_running[placement.node] ??= {}).putIfAbsent(placement.gap!, () => []).add(placement);
      }
      _counts[placement.node] = (_counts[placement.node] ?? 0) + 1;
    }
  }

  final LineSummary line;
  final Color color;
  final DateTime now;
  final Set<String> closed;
  final double width;
  final Set<String> unfolded;
  final ValueChanged<String> onToggle;
  final ValueChanged<Vehicle> onOpen;

  final _standing = <LineTreeNode, Map<int, List<TreePlacement>>>{};
  final _running = <LineTreeNode, Map<int, List<TreePlacement>>>{};
  final _counts = <LineTreeNode, int>{};

  int _countIn(LineTreeNode node) => (_counts[node] ?? 0) + node.spurs.fold(0, (count, spur) => count + _countIn(spur));

  RailSpec _rail(int lane, Set<int> passing, {bool top = true, bool bottom = true}) =>
      RailSpec(color: color, lane: lane, passing: passing, top: top, bottom: bottom, width: width);

  List<Widget> _runningIn(LineTreeNode node, int gap, int lane, Set<int> passing, {bool rail = true}) => [
        for (final placement in _running[node]?[gap] ?? const <TreePlacement>[])
          LineVehicleTile(
            vehicle: placement.vehicle,
            rail: _rail(lane, passing, top: rail, bottom: rail),
            line: line,
            now: now,
            reverse: placement.reverse,
            onOpen: onOpen,
          ),
      ];

  /// [node]'s rows on [lane], the lanes [passing] by drawn across them
  List<Widget> of(LineTreeNode node, {required int lane, required Set<int> passing}) {
    final spur = node is LineSpur ? node : null;
    final fork = spur != null && !spur.merges;
    // A fork's sequence starts with the stop it leaves: its stop i is the sequence's i + 1
    final offset = fork ? 1 : 0;
    final rows = <Widget>[];
    final count = node.stops.length;
    for (var i = 0; i < count; i++) {
      final stop = node.stops[i];
      final top = i > 0 || fork;
      final bottom = i < count - 1 || (spur?.merges ?? false) || spur?.rejoin != null;
      for (final merging in node.spurs.where((other) => other.merges && other.attach.id == stop.id)) {
        rows.addAll(_spur(merging, lane: lane + 1, parentLane: lane, passing: {...passing, if (top) lane}));
      }
      final standing = _standing[node]?[i] ?? const <TreePlacement>[];
      rows.add(LineStopTile(
        stop: stop,
        rail: _rail(lane, passing, top: top, bottom: bottom),
        line: line,
        terminus: spur == null ? i == 0 || i == count - 1 : stop.id == spur.end.id,
        vehicle: standing.firstOrNull?.vehicle,
        reverse: standing.firstOrNull?.reverse ?? false,
        closed: closed.contains(stop.id),
        onOpen: onOpen,
      ));
      // Another vehicle standing there (rare) on a row of its own
      for (final other in standing.skip(1)) {
        rows.add(LineVehicleTile(
          vehicle: other.vehicle,
          rail: _rail(lane, passing, bottom: bottom),
          line: line,
          now: now,
          reverse: other.reverse,
          onOpen: onOpen,
        ));
      }
      for (final forking in node.spurs.where((other) => !other.merges && other.attach.id == stop.id)) {
        rows.addAll(_spur(forking, lane: lane + 1, parentLane: lane, passing: {...passing, if (bottom) lane}));
      }
      if (bottom) {
        rows.addAll(_runningIn(node, i + offset, lane, passing));
      }
    }
    return rows;
  }

  /// A branch off its parent: its row, and when unfolded its stops on its own [lane] (after the row when it leaves
  /// the parent, before it when it joins it)
  List<Widget> _spur(LineSpur spur, {required int lane, required int parentLane, required Set<int> passing}) {
    final expanded = unfolded.contains(spur.id);
    final header = LineSpurTile(
      title: switch (spur) {
        LineSpur(otherWay: true) => currentL10n.lineBranchOtherWay(spur.stops.first.name),
        LineSpur(rejoin: _?) => currentL10n.lineBranchVia(spur.stops.first.name),
        _ => null,
      },
      end: spur.end,
      merges: spur.merges,
      stopCount: spur.stopCount,
      vehicleCount: _countIn(spur),
      mode: line.mode,
      expanded: expanded,
      rail: _rail(lane, passing.difference({lane})),
      parentLane: parentLane,
      onToggle: () => onToggle(spur.id),
    );
    if (!expanded) {
      // Folded, the vehicles between it and its parent still show: under its row, beside the parent's lane (which a
      // branch joining it reaches under its row)
      final junctions = spur.merges ? [spur.stops.length - 1] : [0, if (spur.rejoin != null) spur.stops.length];
      return [
        header,
        for (final junction in junctions)
          ..._runningIn(spur, junction, lane, {...passing, if (spur.merges) parentLane}, rail: false),
      ];
    }
    if (spur.merges) {
      return [...of(spur, lane: lane, passing: passing), header];
    }
    // Vehicles between the stop it leaves and its first stop
    return [header, ..._runningIn(spur, 0, lane, passing), ...of(spur, lane: lane, passing: passing)];
  }
}

/// How deep [node]'s branches go: 0 for a trunk alone
int treeDepth(LineTreeNode node) => node.spurs.fold(0, (depth, spur) => math.max(depth, 1 + treeDepth(spur)));

/// The headsign of the branch [vehicle] runs on, null when the line has no such branch
String? headsignOf(LineDetail detail, Vehicle vehicle) {
  if (vehicle.direction >= detail.directions.length) {
    return null;
  }
  final branches = detail.directions[vehicle.direction].branches;
  return vehicle.branch < branches.length ? branches[vehicle.branch].headsign : null;
}

/// The destinations of [direction]'s branches, the busiest first
List<String> destinationsOf(LineDirection direction) {
  final trips = <String, int>{};
  for (final branch in direction.branches) {
    trips[branch.headsign] = (trips[branch.headsign] ?? 0) + branch.tripCount;
  }
  return trips.keys.toList()..sort((a, b) => trips[b]!.compareTo(trips[a]!));
}

/// [direction]'s termini, the busiest first
List<String> termini(LineDirection direction) => destinationsOf(direction);

/// `Vers Gare Montparnasse`, `Vers Aéroport CDG 2 / Mitry - Claye`, `Vers Mantes-la-Jolie +2`
String directionLabel(LineDirection direction) {
  final all = termini(direction);
  return switch (all.length) {
    0 => '',
    1 || 2 => currentL10n.towards(all.join(' / ')),
    _ => currentL10n.lineDirectionMore(all.first, all.length - 1),
  };
}

/// Traffic state of the line, then its disruptions
class _LineDisruptions extends ConsumerWidget {
  const _LineDisruptions({required this.line});

  final LineSummary line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disruptions = ref.watch(lineDisruptionsProvider(line.id));
    final theme = Theme.of(context);
    // Disruptions are a bonus: a failure only shows a short line
    return switch (disruptions) {
      AsyncValue(:final value?) when value.where((d) => d.active).isEmpty => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(severityIcon(null), size: 18, color: severityColor(null, theme.colorScheme)),
              const SizedBox(width: 6),
              Text(
                severityLabel(null),
                style: TextStyle(color: severityColor(null, theme.colorScheme), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (value.isNotEmpty) DisruptionList(disruptions: value),
        ],
      ),
      AsyncValue(:final value?) => DisruptionList(disruptions: value),
      AsyncValue(:final error?) => Text(context.l10n.trafficUnavailable('$error'), style: theme.textTheme.bodySmall),
      _ => const LinearProgressIndicator(),
    };
  }
}

/// Over the stop list: how many vehicles run this way and how fresh their positions are, `9 trains vers Pont de Sèvres
/// · relevé il y a 20 s` (design 2c)
class _LiveVehiclesHeader extends StatelessWidget {
  const _LiveVehiclesHeader({
    required this.count,
    required this.mode,
    required this.destination,
    required this.fetchedAt,
    required this.now,
  });

  final int count;
  final TransportMode mode;

  /// Where they go, null for both ways
  final String? destination;
  final DateTime fetchedAt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final destination = this.destination;
    final vehicles = switch (mode) {
      TransportMode.tram when destination == null => l10n.liveTramsCount(count),
      TransportMode.bus || TransportMode.noctilien when destination == null => l10n.liveBusesCount(count),
      _ when destination == null => l10n.liveTrainsCount(count),
      TransportMode.tram => l10n.liveTrams(count, destination),
      TransportMode.bus || TransportMode.noctilien => l10n.liveBuses(count, destination),
      _ => l10n.liveTrains(count, destination),
    };
    final seconds = math.max(0, now.difference(fetchedAt).inSeconds);
    final ago = seconds < 60 ? l10n.liveFetchedSecondsAgo(seconds) : l10n.liveFetchedMinutesAgo(seconds ~/ 60);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 0, 8),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: context.colors.live, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: vehicles, style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: ' · $ago', style: TextStyle(color: context.colors.muted)),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
