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

  /// Opens the vehicles of a mark of the stop list: its sheet for one, a choice between them for several
  Future<void> _openMark(LineSummary line, List<Vehicle> vehicles, DateTime now) async {
    if (vehicles.length == 1) {
      return _open(line, vehicles.single);
    }
    final chosen = await showVehicleChooser(context, line: line, vehicles: vehicles, now: now);
    if (chosen != null && mounted) {
      await _open(line, chosen);
    }
  }

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

    // Both ways: a bus's two ways often take other streets, every direction's branches are drawn. A train's or a
    // metro's run side by side, the direction listed alone is drawn, with the stretches where the other ones serve
    // stops it doesn't (a loop run one way, the metro 10 at Auteuil)
    final everyWay = _direction == null && !line.mode.hasPlatforms;
    final shown = everyWay
        ? [for (final direction in detail.directions) ...direction.branches]
        : _shownBranches(detail);
    final served = {
      for (final branch in shown)
        for (final stop in branch.stops) stop.id,
    };
    final otherWay = [
      if (_direction == null && !everyWay)
        for (final direction in detail.directions)
          if (direction != _listedDirection(detail))
            for (final branch in direction.branches) ..._pathOf(branch).partsOff(served),
    ];
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
    // Both ways, the stops of every direction (those only the other one serves too)
    final stops = <String, StopRef>{
      for (final branch in _direction == null ? [for (final direction in detail.directions) ...direction.branches] : shown)
        for (final stop in branch.stops) stop.id: stop,
    };
    return MapOverlay(
      // The branches as one path each way they are drawn: their edges under all of them, where they part or meet
      paths: [
        if (faded.isNotEmpty)
          MapPath(
            points: points(faded.first),
            parts: [for (final branch in faded.skip(1)) points(branch)],
            color: color.withValues(alpha: 0.35),
            width: 4,
          ),
        if (shown.isNotEmpty)
          MapPath(
            points: points(shown.first),
            parts: [for (final branch in shown.skip(1)) points(branch), ...otherWay],
            color: color,
            width: 6,
          ),
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
                  // One lane more for an unfolded other way running beside its parent's stops
                  width: railWidth(treeDepth(trunk) + (treeNodes(trunk).any((node) => node.spurs.any((spur) => spur.rejoin != null)) ? 1 : 0)),
                  unfolded: _unfolded,
                  onToggle: (id) => setState(() => _unfolded.contains(id) ? _unfolded.remove(id) : _unfolded.add(id)),
                  onOpen: (vehicles) => _openMark(line, vehicles, now),
                  scale: MediaQuery.textScalerOf(context).scale,
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
                    rows.build(trunk),
                  ],
                );
              }),
            ),
          ),
      ],
    );
  }
}

/// The rows of the stop list for a tree of branches: each node's stops on its lane, the branches off it folded on a
/// row (unfolded: their own stops on the next lane), and over them the vehicles on the rail ([LineVehicleMark]),
/// never on rows of their own: standing at a stop over its dot, running between two stops where they are between
/// them; several the same way between the same stops are one mark with how many they are, and when both ways run
/// there, each way's mark stands back to back with the other's, each against the stop it goes to.
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
    required this.scale,
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
  final ValueChanged<List<Vehicle>> onOpen;

  /// The text size's scale of a row height
  final double Function(double) scale;

  final _standing = <LineTreeNode, Map<int, List<TreePlacement>>>{};
  final _running = <LineTreeNode, Map<int, List<TreePlacement>>>{};
  final _counts = <LineTreeNode, int>{};

  final _rows = <Widget>[];

  /// Height of the rows added so far
  double _y = 0;

  /// The lane of each node drawn
  final _lanes = <LineTreeNode, int>{};

  /// The middle of each stop's dot, by node and index in its stops
  final _stopAt = <LineTreeNode, Map<int, Offset>>{};

  /// The middle of a branch's own row, on its lane: where it leaves or joins its parent
  final _headerAt = <LineSpur, Offset>{};

  /// Where an unfolded other way comes back into its parent, on its lane
  final _rejoinAt = <LineSpur, Offset>{};

  int _countIn(LineTreeNode node) => (_counts[node] ?? 0) + node.spurs.fold(0, (count, spur) => count + _countIn(spur));

  RailSpec _rail(int lane, Set<int> passing, {bool top = true, bool bottom = true}) =>
      RailSpec(color: color, lane: lane, passing: passing, top: top, bottom: bottom, width: width);

  /// Adds [row], [height] high before the text size; returns the middle of its height
  double _add(Widget row, double height) {
    final scaled = scale(height);
    final middle = _y + scaled / 2;
    _rows.add(row);
    _y += scaled;
    return middle;
  }

  /// The rows of [trunk]'s tree, the vehicles over them
  Widget build(LineTrunk trunk) {
    _of(trunk, lane: 0, passing: const {});
    // Wider than the capsule, for the finger; as long as it, so that two back to back stay apart
    final tapWidth = math.max(LineVehicleMark.size, 40.0);
    const box = LineVehicleMark.length;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _rows),
        for (final (:at, :mark) in _marks())
          Positioned(left: at.dx - tapWidth / 2, top: at.dy - box / 2, width: tapWidth, height: box, child: mark),
      ],
    );
  }

  /// [node]'s rows on [lane], the lanes [passing] by drawn across them
  void _of(LineTreeNode node, {required int lane, required Set<int> passing}) {
    _lanes[node] = lane;
    final spur = node is LineSpur ? node : null;
    final fork = spur != null && !spur.merges;
    final count = node.stops.length;
    // Other ways unfolded and not back yet: their lane goes on beside this node's stops until the stop they rejoin
    final open = <String, ({int lane, LineSpur spur})>{};
    for (var i = 0; i < count; i++) {
      final stop = node.stops[i];
      final top = i > 0 || fork;
      final bottom = i < count - 1 || (spur?.merges ?? false) || spur?.rejoin != null;
      Set<int> here() => {...passing, for (final way in open.values) way.lane};
      for (final merging in node.spurs.where((other) => other.merges && other.attach.id == stop.id)) {
        _spur(merging, lane: lane + 1 + open.length, parentLane: lane, passing: {...here(), if (top) lane});
      }
      final back = open.remove(stop.id);
      final middle = _add(
        LineStopTile(
          stop: stop,
          rail: RailSpec(
            color: color,
            lane: lane,
            passing: here(),
            top: top,
            bottom: bottom,
            joinFrom: {?back?.lane},
            width: width,
          ),
          terminus: spur == null ? i == 0 || i == count - 1 : stop.id == spur.end.id,
          closed: closed.contains(stop.id),
        ),
        LineStopTile.height,
      );
      (_stopAt[node] ??= {})[i] = Offset(laneX(lane), middle);
      if (back != null) {
        _rejoinAt[back.spur] = Offset(laneX(back.lane), middle);
      }
      for (final forking in node.spurs.where((other) => !other.merges && other.attach.id == stop.id)) {
        final spurLane = lane + 1 + open.length;
        _spur(forking, lane: spurLane, parentLane: lane, passing: {...here(), if (bottom) lane});
        // Unfolded, another way back to a later stop of this node: its lane goes on until then
        final rejoin = forking.rejoin;
        if (rejoin != null &&
            unfolded.contains(forking.id) &&
            node.stops.skip(i + 1).any((later) => later.id == rejoin.id)) {
          open[rejoin.id] = (lane: spurLane, spur: forking);
        }
      }
    }
  }

  /// A branch off its parent: its row, and when unfolded its stops on its own [lane] (after the row when it leaves
  /// the parent, before it when it joins it)
  void _spur(LineSpur spur, {required int lane, required int parentLane, required Set<int> passing}) {
    _lanes[spur] = lane;
    final expanded = unfolded.contains(spur.id);
    void header() => _headerAt[spur] = Offset(
          laneX(lane),
          _add(
            LineSpurTile(
              title: switch (spur) {
                LineSpur(otherWay: true) => currentL10n.lineBranchOtherWay(spur.stops.first.name),
                LineSpur(rejoin: _?) => currentL10n.lineBranchVia(spur.stops.first.name),
                _ => null,
              },
              loop: spur.rejoin != null,
              end: spur.end,
              merges: spur.merges,
              stopCount: spur.stopCount,
              vehicleCount: _countIn(spur),
              mode: line.mode,
              expanded: expanded,
              rail: _rail(lane, passing.difference({lane})),
              parentLane: parentLane,
              onToggle: () => onToggle(spur.id),
            ),
            LineSpurTile.height,
          ),
        );
    if (!expanded) {
      // Folded, its vehicles stand on its row
      header();
    } else if (spur.merges) {
      _of(spur, lane: lane, passing: passing);
      header();
    } else {
      header();
      _of(spur, lane: lane, passing: passing);
    }
  }

  /// Where the stop [index] of [node]'s sequence (with the stop a branch is attached at) is drawn: its dot; the
  /// branch's own row for the stop it is attached at, or for any of its stops while it is folded
  Offset? _sequenceAt(LineTreeNode node, int index) {
    final header = node is LineSpur ? _headerAt[node] : null;
    final stops = _stopAt[node];
    if (node is LineSpur) {
      if (!unfolded.contains(node.id) || stops == null) {
        return header;
      }
      if (node.merges) {
        return index >= node.stops.length ? header : stops[index];
      }
      if (index == 0) {
        return header;
      }
      return index - 1 < node.stops.length ? stops[index - 1] : _rejoinAt[node] ?? header;
    }
    return stops?[index];
  }

  /// The marks of the vehicles: standing at stops, then running between them
  List<({Offset at, Widget mark})> _marks() {
    final marks = <({Offset at, Widget mark})>[];
    // From the middle of a capsule to the dot it goes to: its nose just on the dot's edge
    const reach = LineVehicleMark.length / 2 + 2;
    void add(List<TreePlacement> placements, Offset at, {required bool atStop}) => marks.add((
          at: at,
          mark: LineVehicleMark(
            line: line,
            vehicles: [for (final placement in placements) placement.vehicle],
            reverse: placements.first.reverse,
            atStop: atStop,
            label: _label(placements),
            onOpen: onOpen,
          ),
        ));

    for (final MapEntry(key: node, value: stops) in _standing.entries) {
      for (final MapEntry(key: index, value: placements) in stops.entries) {
        final at = _stopAt[node]?[index];
        if (at == null) {
          // A folded branch: its vehicles on its row
          if (node case final LineSpur spur when _headerAt[spur] != null) {
            add(placements, _headerAt[spur]!, atStop: true);
          }
          continue;
        }
        final up = [for (final placement in placements) if (placement.reverse) placement];
        final down = [for (final placement in placements) if (!placement.reverse) placement];
        if (up.isNotEmpty && down.isNotEmpty) {
          // Both ways at the same stop: back to back over its dot
          add(up, at.translate(0, -LineVehicleMark.length / 2), atStop: true);
          add(down, at.translate(0, LineVehicleMark.length / 2), atStop: true);
        } else {
          add(placements, at, atStop: true);
        }
      }
    }

    for (final MapEntry(key: node, value: gaps) in _running.entries) {
      final x = laneX(_lanes[node] ?? 0);
      for (final MapEntry(key: gap, value: placements) in gaps.entries) {
        final from = _sequenceAt(node, gap);
        final to = _sequenceAt(node, gap + 1);
        if (from == null || to == null) {
          continue;
        }
        final top = math.min(from.dy, to.dy);
        final bottom = math.max(from.dy, to.dy);
        final up = [for (final placement in placements) if (placement.reverse) placement];
        final down = [for (final placement in placements) if (!placement.reverse) placement];
        if (bottom - top < 2 * reach) {
          // A folded branch's row: its vehicles side by side on it, back to back
          if (up.isEmpty || down.isEmpty) {
            add(placements, Offset(x, (top + bottom) / 2), atStop: false);
          } else {
            add(up, Offset(x, (top + bottom) / 2 - LineVehicleMark.length / 2), atStop: false);
            add(down, Offset(x, (top + bottom) / 2 + LineVehicleMark.length / 2), atStop: false);
          }
        } else if (up.isNotEmpty && down.isNotEmpty) {
          // Both ways: back to back, each against the stop it goes to
          add(up, Offset(x, top + reach), atStop: false);
          add(down, Offset(x, bottom - reach), atStop: false);
        } else {
          // One way: where the one ahead is between the two stops
          final ahead = placements.reduce((a, b) => (a.reverse ? a.position < b.position : a.position > b.position) ? a : b);
          final share = (ahead.position - gap).clamp(0.0, 1.0);
          final y = from.dy + (to.dy - from.dy) * share;
          add(placements, Offset(x, y.clamp(top + reach, bottom - reach)), atStop: false);
        }
      }
    }
    return marks;
  }

  /// What a screen reader says of a mark: its vehicle, or how many and the one ahead
  String _label(List<TreePlacement> placements) {
    final first = vehicleLabel(placements.first.vehicle, now, line.mode);
    return placements.length == 1 ? first : '${vehiclesCount(line.mode, placements.length)} · $first';
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
