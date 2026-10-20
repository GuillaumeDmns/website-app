import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
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
import 'line_vehicles.dart';
import 'vehicle_sheet.dart';

final lineDetailProvider = FutureProvider.autoDispose.family<LineDetail, String>(
  (ref, lineId) => ref.watch(mobilityApiProvider).line(lineId),
);

class LineScreen extends ConsumerStatefulWidget {
  const LineScreen({super.key, required this.lineId});

  final String lineId;

  @override
  ConsumerState<LineScreen> createState() => _LineScreenState();
}

class _LineScreenState extends ConsumerState<LineScreen> {
  /// Vehicle markers on the map, in logical pixels
  static const _vehicleSize = 24.0;

  int _direction = 0;
  int _branch = 0;

  /// Measured path of each branch, computed once
  final _paths = Expando<BranchPath>();

  BranchPath _pathOf(LineBranch branch) => _paths[branch] ??= BranchPath(branch);

  /// Vehicle the map keeps in view ("Suivre" in its sheet), until stopped or gone
  String? _followed;

  void _follow(Vehicle vehicle) => setState(() => _followed = vehicle.id);

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(lineDetailProvider(widget.lineId));
    final value = detail.value;

    LineDirection? direction;
    LineBranch? branch;
    if (value != null && value.directions.isNotEmpty) {
      direction = value.directions[_direction.clamp(0, value.directions.length - 1)];
      if (direction.branches.isNotEmpty) {
        branch = direction.branches[_branch.clamp(0, direction.branches.length - 1)];
      }
    }

    // Vehicles of the direction shown, moved along between two fetches (every second while there are some)
    final fetched = ref.watch(lineVehiclesProvider(widget.lineId)).value;
    final now = (fetched?.vehicles.isNotEmpty ?? false)
        ? ref.watch(vehicleClockProvider).value ?? DateTime.now()
        : ref.watch(nowProvider).value ?? DateTime.now();
    final vehicles = [
      if (fetched != null)
        for (final vehicle in fetched.vehicles)
          if (vehicle.direction == _direction.clamp(0, (value?.directions.length ?? 1) - 1))
            (vehicle: vehicle, progress: vehicleProgress(vehicle, fetched.fetchedAt, now)),
    ];

    return MapOverlayScope(
      overlay: value == null ? MapOverlay.empty : _overlay(value, direction, branch, vehicles, now),
      child: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(lineDetailProvider(widget.lineId)),
        data: (detail) => _content(context, detail, direction, branch, vehicles),
      ),
    );
  }

  MapOverlay _overlay(
    LineDetail detail,
    LineDirection? direction,
    LineBranch? branch,
    List<({Vehicle vehicle, double progress})> vehicles,
    DateTime now,
  ) {
    final line = detail.line;
    final color = parseHexColor(line.color, Colors.grey);
    List<LatLng> points(LineBranch branch) => _pathOf(branch).line.points;

    final selected = branch == null ? const <LatLng>[] : points(branch);
    final placed = [
      for (final (:vehicle, :progress) in vehicles)
        if (vehicle.direction < detail.directions.length &&
            vehicle.branch < detail.directions[vehicle.direction].branches.length)
          if (_pathOf(detail.directions[vehicle.direction].branches[vehicle.branch])
                  .place(vehicle, progress)
              case final place?)
            (vehicle: vehicle, place: place),
    ];
    return MapOverlay(
      paths: [
        for (final other in direction?.branches ?? const <LineBranch>[])
          if (other != branch) MapPath(points: points(other), color: color.withValues(alpha: 0.35), width: 4),
        if (selected.isNotEmpty) MapPath(points: selected, color: color, width: 6),
      ],
      pins: [
        for (final stop in branch == null ? const <StopRef>[] : stopsOnce(branch))
          MapPin(
            point: LatLng(stop.lat, stop.lon),
            color: color,
            size: 10,
            label: stop.name,
            onTap: () => context.push(Routes.stop(stop.id)),
          ),
        for (final (:vehicle, :place) in placed)
          MapPin(
            point: place.point,
            color: color,
            label: vehicleLabel(vehicle, now),
            onTap: () => showVehicleSheet(context, line: line, vehicle: vehicle, onFollow: () => _follow(vehicle)),
            childSize: Size.square(VehicleMarker.boxSize(_vehicleSize)),
            child: VehicleMarker(
              line: line,
              size: _vehicleSize,
              // The map of a line's page is north up
              heading: place.heading,
              punctuality: Punctuality.of(vehicle),
              stale: vehicle.stale,
            ),
          ),
      ],
      fit: selected,
    ).withFollow(_followView(placed));
  }

  /// The camera on the vehicle followed, north up; it stops when the vehicle is gone
  MapFollow? _followView(List<({Vehicle vehicle, VehiclePlacement place})> placed) {
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
    return MapFollow(position: place.point, bearing: 0, zoom: 15);
  }

  Widget _content(
    BuildContext context,
    LineDetail detail,
    LineDirection? direction,
    LineBranch? branch,
    List<({Vehicle vehicle, double progress})> vehicles,
  ) {
    // A stop area served twice in a row (two of its quays) shows once
    final shown = branch?.copyWith(stops: stopsOnce(branch));
    final positions = stopListPositions(shown, vehicles);
    final closed = ref.watch(lineClosedStopsProvider(detail.line.id)).value ?? const <String>{};

    final theme = Theme.of(context);
    final line = detail.line;
    final color = parseHexColor(line.color, theme.colorScheme.primary);

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
        if (detail.directions.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 0, 0),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              segments: [
                for (var i = 0; i < detail.directions.length; i++)
                  ButtonSegment(
                    value: i,
                    label: Text(_directionLabel(detail.directions[i]), maxLines: 2, textAlign: TextAlign.center),
                  ),
              ],
              selected: {_direction.clamp(0, detail.directions.length - 1)},
              onSelectionChanged: (selection) => setState(() {
                _direction = selection.first;
                _branch = 0;
              }),
            ),
          ),
        if (direction != null && direction.branches.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < direction.branches.length; i++)
                  ChoiceChip(
                    label: Text(_branchLabel(direction.branches[i])),
                    selected: direction.branches[i] == branch,
                    onSelected: (_) => setState(() => _branch = i),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
          child: LineServiceHoursSummary(lineId: line.id, direction: _direction.clamp(0, detail.directions.length - 1)),
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
        if (shown != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: Column(
                children: [
                  for (var i = 0; i < shown.stops.length; i++)
                    _StopTimelineTile(
                      stop: shown.stops[i],
                      color: color,
                      isFirst: i == 0,
                      isLast: i == shown.stops.length - 1,
                      line: line,
                      vehicles: positions[i] ?? const [],
                      closed: closed.contains(shown.stops[i].id),
                      onFollow: _follow,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _directionLabel(LineDirection direction) {
    final termini = direction.branches.map((branch) => branch.headsign).toSet();
    return currentL10n.towards('${termini.take(3).join(' / ')}${termini.length > 3 ? '…' : ''}');
  }

  static String _branchLabel(LineBranch branch) =>
      branch.stops.isEmpty ? branch.headsign : '${branch.stops.first.name} → ${branch.headsign}';
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

/// Stop of the line drawn on a vertical line of the line's color
class _StopTimelineTile extends StatelessWidget {
  const _StopTimelineTile({
    required this.stop,
    required this.color,
    required this.isFirst,
    required this.isLast,
    required this.line,
    this.vehicles = const [],
    this.closed = false,
    required this.onFollow,
  });

  /// "Suivre" in a vehicle's sheet
  final ValueChanged<Vehicle> onFollow;

  static const _height = 44.0;

  /// The line doesn't stop there now (station closed, stop not served)
  final bool closed;

  final StopRef stop;
  final Color color;
  final bool isFirst;
  final bool isLast;
  final LineSummary line;

  /// Vehicles around this stop, offset in stops (-0.5: halfway from the previous one, 0: at the stop)
  final List<({double offset, Vehicle vehicle})> vehicles;

  @override
  Widget build(BuildContext context) {
    final terminus = isFirst || isLast;
    // Taller with a larger text size
    final height = MediaQuery.textScalerOf(context).scale(_height);

    return InkWell(
      onTap: () => context.push(Routes.stop(stop.id)),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Column(
                    children: [
                      Expanded(child: Container(width: 6, color: isFirst ? Colors.transparent : color)),
                      Expanded(child: Container(width: 6, color: isLast ? Colors.transparent : color)),
                    ],
                  ),
                  Container(
                    width: terminus ? 16 : 12,
                    height: terminus ? 16 : 12,
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 3),
                    ),
                  ),
                  for (final (:offset, :vehicle) in vehicles)
                    Positioned(
                      top: height / 2 + offset * height - 10,
                      left: 14,
                      child: GestureDetector(
                        onTap: () => showVehicleSheet(context, line: line, vehicle: vehicle, onFollow: () => onFollow(vehicle)),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: VehicleMarker(line: line, size: 20, punctuality: Punctuality.of(vehicle), stale: vehicle.stale),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                stop.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: terminus ? FontWeight.w600 : FontWeight.w400,
                  color: closed ? context.colors.muted : null,
                  decoration: closed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (closed) PillTag(icon: Icons.block, color: Theme.of(context).colorScheme.error, text: context.l10n.notServed),
          ],
        ),
      ),
    );
  }
}
