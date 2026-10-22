import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/models.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/ui.dart';
import '../../../l10n/l10n.dart';
import '../../traffic/disruption_widgets.dart';
import '../journey_labels.dart';
import '../journey_providers.dart';
import '../journey_retime.dart';
import '../../traffic/traffic_providers.dart';
import '../../../app/theme.dart';
import 'journey_time_bar.dart';

/// Result row: the duration in large figures, when to leave (green with real time) and the arrival on one line, then
/// the journey as a bar on the time axis shared by the results ([JourneyTimeBar]: waits, walks and connections compare
/// at a glance), the next departures of its first ride and the details. Without an axis, the chain of lines.
class JourneyCard extends ConsumerWidget {
  const JourneyCard({
    super.key,
    required this.journey,
    required this.now,
    required this.onTap,
    this.axis,
    this.selected = false,
    this.onOpen,
    this.onHover,
  });

  final JourneyOption journey;
  final DateTime now;
  final VoidCallback onTap;

  /// Shared by the results shown together
  final TimeAxis? axis;

  /// Shown on the map
  final bool selected;

  /// Opens the detail ("Détails" button)
  final VoidCallback? onOpen;

  /// Mouse over the card (desktop / web)
  final VoidCallback? onHover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.colors;
    final firstRide = journey.rides.firstOrNull;
    final later = _laterDepartures(ref, firstRide);
    final leaveIn = journey.departure.difference(now);
    final live = firstRide?.realtime == true;

    final details = [
      if (firstRide != null)
        context.l10n.firstRide(firstRide.line?.name ?? '', formatClock(firstRide.departure), firstRide.from?.name ?? ''),
      if (journey.transfers > 0) context.l10n.transfersShort(journey.transfers),
      if ((journey.walkingDuration ?? 0) >= 60) context.l10n.walkingDuration(formatDuration(journey.walkingDuration!)),
      if (journey.fare != null && journey.fare! > 0) formatFare(journey.fare!),
    ].join(' · ');
    final minutes = (journey.duration / 60).round();

    final duration = theme.textTheme.headlineSmall?.copyWith(fontSize: 22, height: 1, letterSpacing: -0.4);
    final card = AppCard(
      onTap: onTap,
      border: selected ? scheme.primary : null,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Like Citymapper: the duration in large figures
              if (minutes < 60)
                Text.rich(TextSpan(children: [
                  TextSpan(text: '$minutes', style: duration),
                  TextSpan(text: '\u00a0min', style: theme.textTheme.labelMedium),
                ]))
              else
                Text(formatDuration(journey.duration), style: duration),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  // Short, beside the duration: `Dans 2 min`
                  switch (leaveIn.inMinutes) {
                    <= 0 => context.l10n.leaveNowCompact,
                    final minutes when minutes < 60 => context.l10n.leaveInMinutes(minutes),
                    _ => leaveInLabel(leaveIn),
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontSize: 14, color: live ? colors.live : null),
                ),
              ),
              const Spacer(),
              Text('${context.l10n.arrivalShort} ', style: theme.textTheme.bodySmall),
              Text(formatClock(journey.arrival), style: theme.textTheme.titleSmall?.copyWith(fontSize: 16)),
              if (onOpen != null)
                SizedBox(
                  width: 28,
                  height: 20,
                  child: IconButton(
                    tooltip: context.l10n.details,
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    icon: Icon(Icons.chevron_right, color: colors.muted),
                    onPressed: onOpen,
                  ),
                ),
            ],
          ),
          if (axis case final axis?)
            Padding(padding: const EdgeInsets.fromLTRB(0, 12, 0, 8), child: JourneyTimeBar(journey: journey, axis: axis))
          else
            Padding(padding: const EdgeInsets.only(top: 10, bottom: 2), child: SectionsStrip(journey: journey)),
          if (details.isNotEmpty)
            Text(details, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5, height: 1.4)),
          if (later.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.update, size: 16, color: colors.muted),
                const SizedBox(width: 6),
                Text(context.l10n.alsoAt(later.map(formatClock).join(' · ')), style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5)),
              ],
            ),
          ],
        ],
      ),
    );
    return onHover == null ? card : MouseRegion(onEnter: (_) => onHover!(), child: card);
  }

  /// The next two departures of the first ride after the one of this option, from its line's departures
  List<DateTime> _laterDepartures(WidgetRef ref, JourneySection? firstRide) {
    if (firstRide == null) {
      return const [];
    }
    final key = rideKey(firstRide, firstRide.departure.subtract(const Duration(minutes: 1)), now);
    if (key == null) {
      return const [];
    }
    return (ref.watch(rideOptionsProvider(key)).value ?? const <Ride>[])
        .map((ride) => ride.departure.time)
        .where((time) => time.isAfter(firstRide.departure.add(const Duration(seconds: 30))))
        .take(2)
        .toList();
  }
}

/// Walk / line badges chain: 🚶 3 › (14) › (9) › 🚶 17, disrupted lines marked
class SectionsStrip extends ConsumerWidget {
  const SectionsStrip({super.key, required this.journey});

  final JourneyOption journey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final severities = ref.watch(lineSeveritiesProvider);
    final items = <Widget>[];

    for (final section in journey.sections) {
      final Widget? item = switch (section.kind) {
        SectionKind.transit when section.line != null => WithSeverity(
            severity: switch (severities[section.line!.id]) {
              DisruptionSeverity.info => null,
              final severity => severity,
            },
            dotSize: 12,
            child: LineBadge(section.line!, size: 24),
          ),
        SectionKind.walk || SectionKind.bike when section.duration >= 60 => MoveMinutes(section: section),
        _ => null,
      };
      if (item != null) {
        if (items.isNotEmpty) {
          items.add(Icon(Icons.chevron_right, size: 16, color: scheme.outline));
        }
        items.add(item);
      }
    }

    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, runSpacing: 6, children: items);
  }
}

/// A move in a chain of steps: its icon and its minutes (at least 1)
class MoveMinutes extends StatelessWidget {
  const MoveMinutes({super.key, required this.section});

  final JourneySection section;

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(moveIcon(section.kind), size: 20, color: muted),
        Text('${math.max(1, (section.duration / 60).round())}', style: TextStyle(fontSize: 12, color: muted)),
      ],
    );
  }
}
