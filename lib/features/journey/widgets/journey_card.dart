import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/models.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/ui.dart';
import '../../../l10n/l10n.dart';
import '../../traffic/disruption_widgets.dart';
import '../journey_labels.dart';
import '../../traffic/traffic_providers.dart';
import '../../../app/theme.dart';

/// What the journey planner says of [journey] among the options it gives, for its card; null when it says nothing
/// that sets it apart. Navitia's own words, never worked out here: its tags first (`asap`, `less_transfers`,
/// `less_fallbacks`, `proposal`: IDFM's), then its type for a way without public transport or an older planner. Tags
/// most options carry (`walking`, `ecologic`, `reliable`) and the types `rapid` and `comfort`, given to several
/// options at once, say nothing.
String? journeyTag(JourneyOption journey) {
  final l10n = currentL10n;
  for (final (tag, label) in [
    ('asap', l10n.journeyAsap),
    ('less_transfers', l10n.journeyComfort),
    ('less_fallbacks', l10n.journeyLessWalk),
    ('proposal', l10n.journeyBest),
  ]) {
    if (journey.tags.contains(tag)) {
      return label;
    }
  }
  return switch (journey.type) {
    'best' => l10n.journeyBest,
    'fastest' => l10n.journeyRapid,
    'less_fallback_walk' => l10n.journeyLessWalk,
    'non_pt_walk' => l10n.journeyWalk,
    'non_pt_bike' || 'non_pt_bss' => l10n.journeyBike,
    'bike_share' => l10n.journeyBikeShare,
    'car' => l10n.journeyCar,
    _ => null,
  };
}

/// Whether the fare is worth a place on the cards of [journeys]: only when they don't all cost the same
bool faresDiffer(List<JourneyOption> journeys) => {for (final journey in journeys) journey.fare ?? 0}.length > 1;

/// Result row in two lines: the chain of lines and walks with the duration in large figures (the fare by it when the
/// options don't cost the same); when to leave (green), the arrival and what sets the option apart ([tag]). A third line only when one of its lines is disrupted, written in
/// clear. The first ride's next departures and where it leaves from are in the detail.
class JourneyCard extends ConsumerWidget {
  const JourneyCard({
    super.key,
    required this.journey,
    required this.now,
    required this.onTap,
    this.selected = false,
    this.tag,
    this.showFare = false,
    this.onHover,
  });

  final JourneyOption journey;
  final DateTime now;
  final VoidCallback onTap;

  /// Shown on the map
  final bool selected;

  /// What sets it apart among the results ([journeyTag])
  final String? tag;

  /// See [faresDiffer]
  final bool showFare;

  /// Mouse over the card (desktop / web)
  final VoidCallback? onHover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.colors;
    final leaveIn = journey.departure.difference(now);
    final minutes = (journey.duration / 60).round();
    final fare = journey.fare;
    final severities = ref.watch(lineSeveritiesProvider);
    // Its lines that go wrong, the interrupted ones first
    final troubles = <({LineSummary line, DisruptionSeverity severity})>[
      for (final severity in [DisruptionSeverity.blocking, DisruptionSeverity.disrupted])
        for (final line in {for (final ride in journey.rides) ?ride.line})
          if (severities[line.id] == severity) (line: line, severity: severity),
    ];

    final card = AppCard(
      onTap: onTap,
      border: selected ? scheme.primary : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: SectionsStrip(journey: journey)),
              const SizedBox(width: 8),
              // Only when the options don't cost the same: by the duration, what is weighed against it
              if (showFare && fare != null && fare > 0) ...[
                Text(formatFare(fare), style: theme.textTheme.bodySmall?.copyWith(color: colors.muted, letterSpacing: 0)),
                const SizedBox(width: 10),
              ],
              // Like Citymapper: the duration in large figures
              if (minutes < 60) ...[
                Text('$minutes', style: theme.textTheme.headlineSmall?.copyWith(fontSize: 28, height: 1.05)),
                Padding(
                  padding: const EdgeInsets.only(left: 2, top: 10),
                  child: Text('min', style: theme.textTheme.labelMedium),
                ),
              ] else
                Text(formatDuration(journey.duration), style: theme.textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 6),
          // The departure is said by when to leave, the arrival alone after it; the planner's tag beside them when it
          // fits, under them otherwise (`Moins de correspondances`): never cutting the times in two
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: leaveInLabel(leaveIn),
                      style: theme.textTheme.titleSmall?.copyWith(color: colors.live, fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: ' ·\u00a0${context.l10n.arrivalAt(formatClock(journey.arrival)).replaceAll(' ', '\u00a0')}'),
                  ]),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.muted,
                    letterSpacing: 0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (tag case final tag?)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: colors.subtle, borderRadius: BorderRadius.circular(6)),
                    child: Text(tag, style: theme.textTheme.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          if (troubles.isNotEmpty) ...[
            const SizedBox(height: 9),
            Divider(height: 1, color: scheme.outline),
            const SizedBox(height: 3),
            for (final trouble in troubles.take(2))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: NoticeLine(
                  icon: severityIcon(trouble.severity),
                  // `N16 : trafic interrompu`
                  text: context.l10n.lineSeverity(trouble.line.name ?? trouble.line.label, severityLabel(trouble.severity).toLowerCase()),
                  color: severityColor(trouble.severity, scheme),
                ),
              ),
          ],
        ],
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
