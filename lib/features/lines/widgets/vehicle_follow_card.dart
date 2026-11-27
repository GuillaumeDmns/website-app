import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/utils/colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../l10n/l10n.dart';
import '../line_vehicles.dart';

/// A vehicle followed on the map, the whole page while it is (design "Suivi d'un véhicule"): the map above shows it,
/// the sheet lowered to this card: where it goes and its delay, its next stop large with when it gets there, the four
/// stops after it on a short rail with their times, how fresh its position is; its stops in its sheet, and stopping.
class VehicleFollowCard extends StatelessWidget {
  const VehicleFollowCard({
    super.key,
    required this.line,
    required this.vehicle,
    required this.atStop,
    required this.now,
    this.fetchedAt,
    required this.onStops,
    required this.onStop,
  });

  final LineSummary line;

  /// As it is now, moved along since the last fetch
  final Vehicle vehicle;

  /// Standing at its next stop
  final bool atStop;
  final DateTime now;

  /// When its position was fetched
  final DateTime? fetchedAt;

  /// Opens its sheet: every stop it has left to serve
  final VoidCallback onStops;
  final VoidCallback onStop;

  /// How many stops after the next one the card shows
  static const _following = 4;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final color = parseHexColor(line.color, theme.colorScheme.primary);
    final delay = vehicleDelay(vehicle);
    final next = vehicle.calls.firstOrNull;
    final following = vehicle.calls.skip(1).take(_following).toList();
    final seconds = fetchedAt == null ? null : math.max(0, now.difference(fetchedAt!).inSeconds);
    final age = seconds == null
        ? null
        : seconds < 60
            ? l10n.liveFetchedSecondsAgo(seconds)
            : l10n.liveFetchedMinutesAgo(seconds ~/ 60);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            LineBadge(line, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                [?vehicle.name, l10n.towards(vehicle.destination ?? '?')].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (delay != null) ...[
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.delayed.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Text(
                    delay,
                    style: theme.textTheme.labelMedium?.copyWith(color: context.colors.delayed, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(l10n.vehicleNextStop, style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                vehicle.toStopName ?? next?.stopName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              vehicleWhen(vehicle, now, line.mode, atStop: atStop),
              style: theme.textTheme.headlineSmall?.copyWith(color: context.colors.live),
            ),
          ],
        ),
        if (following.isNotEmpty) ...[
          const SizedBox(height: 14),
          _FollowingStops(calls: following, color: color),
        ],
        const SizedBox(height: 12),
        Text(
          [
            vehicle.stale ? l10n.vehicleStale : l10n.vehicleFollowPosition,
            ?age,
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: onStops,
                child: Text(l10n.vehicleAllStops, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: onStop, child: Text(l10n.followStop)),
          ],
        ),
      ],
    );
  }
}

/// The stops after the next one, across: on a rail of the line's color, each with its name and its time
class _FollowingStops extends StatelessWidget {
  const _FollowingStops({required this.calls, required this.color});

  final List<VehicleCall> calls;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned(
          left: 5,
          right: 5,
          top: 4,
          child: Container(height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final call in calls)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: context.colors.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 2.5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        call.stopName ?? call.stopId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        formatClock(call.expectedAt),
                        style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            // Room kept for the stops it doesn't have: the same place for each one
            for (var i = calls.length; i < VehicleFollowCard._following; i++) const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }
}
