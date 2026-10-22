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

/// Result row, like Citymapper: when to leave in large and green, the duration in large figures, the
/// chain of lines, the next departures of its first ride, then the details.
class JourneyCard extends ConsumerWidget {
  const JourneyCard({
    super.key,
    required this.journey,
    required this.now,
    required this.onTap,
    this.selected = false,
    this.onOpen,
    this.onHover,
  });

  final JourneyOption journey;
  final DateTime now;
  final VoidCallback onTap;

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

    final details = [
      if (firstRide != null)
        context.l10n.firstRide(firstRide.line?.name ?? '', formatClock(firstRide.departure), firstRide.from?.name ?? ''),
      if (journey.transfers > 0) context.l10n.transfersShort(journey.transfers),
      if ((journey.walkingDuration ?? 0) >= 60) context.l10n.walkingDuration(formatDuration(journey.walkingDuration!)),
      if (journey.fare != null && journey.fare! > 0) formatFare(journey.fare!),
    ].join(' · ');
    final minutes = (journey.duration / 60).round();

    final card = AppCard(
      onTap: onTap,
      border: selected ? scheme.primary : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      leaveInLabel(leaveIn),
                      style: theme.textTheme.titleMedium?.copyWith(color: colors.live, fontWeight: FontWeight.w600),
                    ),
                    Text('${formatClock(journey.departure)} → ${formatClock(journey.arrival)}', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              // Like Citymapper: the duration in large figures
              if (minutes < 60) ...[
                Text('$minutes', style: theme.textTheme.headlineSmall?.copyWith(fontSize: 28, height: 1.05)),
                Padding(
                  padding: const EdgeInsets.only(left: 2, top: 12),
                  child: Text('min', style: theme.textTheme.labelMedium),
                ),
              ] else
                Text(formatDuration(journey.duration), style: theme.textTheme.titleLarge),
              if (onOpen != null)
                IconButton(
                  tooltip: context.l10n.details,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.chevron_right, color: colors.muted),
                  onPressed: onOpen,
                )
              else
                const SizedBox(width: 12),
            ],
          ),
          const SizedBox(height: 10),
          Padding(padding: const EdgeInsets.only(right: 12), child: SectionsStrip(journey: journey)),
          if (later.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.update, size: 16, color: colors.muted),
                const SizedBox(width: 6),
                Text(context.l10n.alsoAt(later.map(formatClock).join(' · ')), style: theme.textTheme.bodySmall),
              ],
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
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
