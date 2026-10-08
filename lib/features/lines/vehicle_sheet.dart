import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/utils/colors.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import 'line_vehicles.dart';

/// Mission of a vehicle: its next stops with their times, kept up to date while open
Future<void> showVehicleSheet(BuildContext context, {required LineSummary line, required Vehicle vehicle}) {
  final router = GoRouter.of(context);
  return showModalBottomSheet<void>(
    context: context,
    // Above the whole app, not inside the panel or the bottom sheet
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => _VehicleSheet(line: line, vehicle: vehicle, router: router),
  );
}

/// [vehicle] in a new fetch: same id, or (vehicles found from passages per stop have no lasting id) the one of the
/// same direction expected at one of its stops at about the same time
Vehicle? sameVehicle(Vehicle vehicle, List<Vehicle> vehicles) {
  for (final other in vehicles) {
    if (other.id == vehicle.id) {
      return other;
    }
  }
  final times = {for (final call in vehicle.calls) call.stopId: call.expectedAt};
  Vehicle? best;
  var bestGap = 91;
  for (final other in vehicles.where((other) => other.direction == vehicle.direction)) {
    for (final call in other.calls) {
      final time = times[call.stopId];
      final gap = time == null ? null : call.expectedAt.difference(time).inSeconds.abs();
      if (gap != null && gap < bestGap) {
        best = other;
        bestGap = gap;
      }
    }
  }
  return best;
}

class _VehicleSheet extends ConsumerStatefulWidget {
  const _VehicleSheet({required this.line, required this.vehicle, required this.router});

  final LineSummary line;
  final Vehicle vehicle;
  final GoRouter router;

  @override
  ConsumerState<_VehicleSheet> createState() => _VehicleSheetState();
}

class _VehicleSheetState extends ConsumerState<_VehicleSheet> {
  late Vehicle _vehicle = widget.vehicle;

  @override
  Widget build(BuildContext context) {
    ref.listen(lineVehiclesProvider(widget.line.id), (_, next) {
      final found = next.value == null ? null : sameVehicle(_vehicle, next.value!.vehicles);
      if (found != null) {
        setState(() => _vehicle = found);
      }
    });
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final theme = Theme.of(context);
    final color = parseHexColor(widget.line.color, theme.colorScheme.primary);
    final calls = [
      for (final call in _vehicle.calls)
        if (call.expectedAt.isAfter(now.subtract(const Duration(seconds: 30)))) call,
    ];
    final subtitle = [
      '${widget.line.mode.label} ${widget.line.name ?? ''}'.trim(),
      if (_vehicle.name != null) _vehicle.name!,
    ].join(' · ');

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  VehicleMarker(line: widget.line, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.towards(_vehicle.destination ?? '?'),
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(subtitle, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                            ),
                            if (_DelayLabel.shown(_vehicle.delaySeconds)) ...[
                              const SizedBox(width: 8),
                              _DelayLabel(_vehicle.delaySeconds!),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.close,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (calls.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(context.l10n.nextStopsUnavailable, style: theme.textTheme.bodyMedium),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: calls.length,
                  itemBuilder: (context, i) => _CallRow(
                    call: calls[i],
                    now: now,
                    color: color,
                    isFirst: i == 0,
                    isLast: i == calls.length - 1,
                    onTap: () {
                      Navigator.pop(context);
                      widget.router.push(Routes.stop(calls[i].stopId));
                    },
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                context.l10n.vehicleTimesNotice,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A next stop: time, then the stop on the vehicle's line
class _CallRow extends StatelessWidget {
  const _CallRow({
    required this.call,
    required this.now,
    required this.color,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  static const _height = 48.0;

  final VehicleCall call;
  final DateTime now;
  final Color color;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seconds = call.expectedAt.difference(now).inSeconds;
    final until = seconds <= 30
        ? context.l10n.vehicleAtStop
        : seconds < 3600
        ? context.l10n.minutesShort((seconds / 60).ceil())
        : null;

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        // Taller with a larger text size
        height: MediaQuery.textScalerOf(context).scale(_height),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatClock(call.expectedAt),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                    if (until != null)
                      Text(until, style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade700)),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    children: [
                      Expanded(child: Container(width: 4, color: isFirst ? Colors.transparent : color)),
                      Expanded(child: Container(width: 4, color: isLast ? Colors.transparent : color)),
                    ],
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                call.stopName ?? call.stopId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: isFirst ? FontWeight.w600 : FontWeight.w400),
              ),
            ),
            if (_DelayLabel.shown(call.delaySeconds)) ...[_DelayLabel(call.delaySeconds!), const SizedBox(width: 8)],
            if (call.platform != null)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(context.l10n.platform(call.platform!), style: theme.textTheme.bodySmall),
              )
            else
              const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

/// `+3 min` (late) or `-2 min` (early), from a minute off
class _DelayLabel extends StatelessWidget {
  const _DelayLabel(this.seconds);

  final int seconds;

  static bool shown(int? seconds) => seconds != null && seconds.abs() >= 60;

  @override
  Widget build(BuildContext context) {
    final minutes = (seconds / 60).round();
    return Text(
      minutes > 0 ? '+${context.l10n.minutesShort(minutes)}' : context.l10n.minutesShort(minutes),
      style: TextStyle(
        color: minutes > 0 ? Colors.orange.shade800 : Colors.blue.shade700,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );
  }
}
