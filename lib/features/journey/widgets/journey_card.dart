import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/models.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/line_badge.dart';
import '../../traffic/disruption_widgets.dart';
import '../../traffic/traffic_providers.dart';

/// User-facing name of a Navitia journey type
String journeyTypeLabel(String? type) => switch (type) {
      'best' => 'Suggéré',
      'rapid' => 'Le plus rapide',
      'comfort' => 'Moins de correspondances',
      'less_fallback_walk' => 'Moins de marche',
      'non_pt_walk' => 'À pied',
      'non_pt_bike' || 'non_pt_bss' => 'À vélo',
      'car' => 'En voiture',
      _ => 'Autre option',
    };

/// Result row: duration, the chain of lines, times, and when to leave.
class JourneyCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final firstRide = journey.rides.firstOrNull;
    final leaveIn = journey.departure.difference(now);

    final details = [
      '${formatClock(journey.departure)} → ${formatClock(journey.arrival)}',
      if (journey.transfers > 0) '${journey.transfers} corresp.',
      if ((journey.walkingDuration ?? 0) >= 60) '${formatDuration(journey.walkingDuration!)} à pied',
      if (journey.fare != null && journey.fare! > 0) formatFare(journey.fare!),
    ].join(' · ');

    final card = Card(
      clipBehavior: Clip.antiAlias,
      shape: selected
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.primary, width: 2))
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: SectionsStrip(journey: journey)),
                  const SizedBox(width: 12),
                  Text(formatDuration(journey.duration),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  if (onOpen != null)
                    IconButton(
                      tooltip: 'Détails',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chevron_right),
                      onPressed: onOpen,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(details, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              if (firstRide != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (firstRide.realtime == true)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.rss_feed, size: 13, color: Colors.green.shade600),
                      ),
                    Expanded(
                      child: Text(
                        '${leaveIn.inMinutes <= 0 ? 'Partez maintenant' : 'Partez dans ${formatDuration(leaveIn.inSeconds)}'}'
                        ' · ${firstRide.line?.name ?? ''} à ${formatClock(firstRide.departure)} de ${firstRide.from?.name ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: firstRide.realtime == true ? Colors.green.shade700 : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return onHover == null ? card : MouseRegion(onEnter: (_) => onHover!(), child: card);
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
        SectionKind.walk || SectionKind.bike when section.duration >= 60 => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(section.kind == SectionKind.bike ? Icons.pedal_bike : Icons.directions_walk,
                  size: 20, color: scheme.onSurfaceVariant),
              Text('${(section.duration / 60).round()}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
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
