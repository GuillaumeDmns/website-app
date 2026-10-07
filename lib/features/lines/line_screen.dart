import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/map/map_overlay.dart';
import '../../core/platform/share.dart';
import '../../core/utils/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/line_badge.dart';
import '../../core/location/location_providers.dart';
import '../../l10n/l10n.dart';
import '../favorites/favorite_widgets.dart';
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
  int _direction = 0;
  int _branch = 0;

  /// Measured path of each branch, computed once
  final _paths = Expando<BranchPath>();

  BranchPath _pathOf(LineBranch branch) => _paths[branch] ??= BranchPath(branch);

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

    // Vehicles of the direction shown, moved along between two fetches
    final fetched = ref.watch(lineVehiclesProvider(widget.lineId)).value;
    final now = ref.watch(nowProvider).value ?? DateTime.now();
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

  MapOverlay _overlay(LineDetail detail, LineDirection? direction, LineBranch? branch,
      List<({Vehicle vehicle, double progress})> vehicles, DateTime now) {
    final line = detail.line;
    final color = parseHexColor(line.color, Colors.grey);
    List<LatLng> points(LineBranch b) => b.shape.isNotEmpty
        ? [for (final point in b.shape) LatLng(point[1], point[0])]
        : [for (final stop in b.stops) LatLng(stop.lat, stop.lon)];

    final selected = branch == null ? const <LatLng>[] : points(branch);
    return MapOverlay(
      paths: [
        for (final other in direction?.branches ?? const <LineBranch>[])
          if (other != branch) MapPath(points: points(other), color: color.withValues(alpha: 0.35), width: 4),
        if (selected.isNotEmpty) MapPath(points: selected, color: color, width: 6),
      ],
      pins: [
        for (final stop in branch?.stops ?? const <StopRef>[])
          MapPin(
            point: LatLng(stop.lat, stop.lon),
            color: color,
            size: 10,
            label: stop.name,
            onTap: () => context.push(Routes.stop(stop.id)),
          ),
        for (final (:vehicle, :progress) in vehicles)
          if (vehicle.direction < detail.directions.length &&
              vehicle.branch < detail.directions[vehicle.direction].branches.length)
            if (_pathOf(detail.directions[vehicle.direction].branches[vehicle.branch]).position(vehicle, progress)
                case final point?)
              MapPin(
                point: point,
                color: color,
                label: vehicleLabel(vehicle, now),
                onTap: () => showVehicleSheet(context, line: line, vehicle: vehicle),
                childSize: const Size(24, 24),
                child: VehicleMarker(line: line),
              ),
      ],
      fit: selected,
    );
  }

  Widget _content(BuildContext context, LineDetail detail, LineDirection? direction, LineBranch? branch,
      List<({Vehicle vehicle, double progress})> vehicles) {
    // Vehicles on the stop list: fractional stop index in the branch shown (vehicles of other branches too, where
    // they run on it)
    final positions = <int, List<({double offset, Vehicle vehicle})>>{};
    final stopIds = [for (final stop in branch?.stops ?? const <StopRef>[]) stop.id];
    for (final (:vehicle, :progress) in vehicles) {
      final to = stopIds.indexOf(vehicle.toStopId);
      if (to < 0) {
        continue;
      }
      final left = vehicle.fromStopId == null ? to : stopIds.lastIndexOf(vehicle.fromStopId!, to);
      if (vehicle.fromStopId != null && left < 0 && to == 0) {
        continue;
      }
      final from = left >= 0 ? left : to - 1;
      final position = from + (to - from) * progress;
      positions.putIfAbsent(position.round(), () => []).add((offset: position - position.round(), vehicle: vehicle));
    }

    final theme = Theme.of(context);
    final line = detail.line;
    final color = parseHexColor(line.color, theme.colorScheme.primary);

    return ListView(
      controller: PanelScrollScope.of(context),
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
      children: [
        Row(
          children: [
            IconButton(tooltip: context.l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
            LineBadge(line, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${line.mode.label} ${line.name ?? ''}',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  if (line.longName != null && line.longName != line.name)
                    Text(line.longName!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            FavoriteLineButton(lineId: line.id),
            IconButton(
              tooltip: context.l10n.share,
              icon: const Icon(Icons.share_outlined),
              onPressed: () => shareLink(context, title: '${line.mode.label} ${line.name ?? ''}'.trim(), location: Routes.line(line.id)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
          child: _LineDisruptions(line: line),
        ),
        if (detail.directions.length > 1)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (var i = 0; i < detail.directions.length; i++)
                  ButtonSegment(value: i, label: Text(_directionLabel(detail.directions[i]), maxLines: 2, textAlign: TextAlign.center)),
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
        const SizedBox(height: 12),
        if (branch != null)
          for (var i = 0; i < branch.stops.length; i++)
            _StopTimelineTile(
              stop: branch.stops[i],
              color: color,
              isFirst: i == 0,
              isLast: i == branch.stops.length - 1,
              line: line,
              vehicles: positions[i] ?? const [],
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
                Text(severityLabel(null), style: TextStyle(color: severityColor(null, theme.colorScheme), fontWeight: FontWeight.w600)),
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
  });

  static const _height = 44.0;

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
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => context.push(Routes.stop(stop.id)),
      child: SizedBox(
        height: _height,
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
                      color: theme.colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 3),
                    ),
                  ),
                  for (final (:offset, :vehicle) in vehicles)
                    Positioned(
                      top: _height / 2 + offset * _height - 10,
                      left: 14,
                      child: GestureDetector(
                        onTap: () => showVehicleSheet(context, line: line, vehicle: vehicle),
                        child: MouseRegion(cursor: SystemMouseCursors.click, child: VehicleMarker(line: line, size: 20)),
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
                style: TextStyle(fontWeight: terminus ? FontWeight.w700 : FontWeight.w400),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
