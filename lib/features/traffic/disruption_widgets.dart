import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/models.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import 'traffic_providers.dart';

Color severityColor(DisruptionSeverity? severity, ColorScheme scheme) {
  final colors = scheme.brightness == Brightness.light ? AppColors.light : AppColors.dark;
  return switch (severity) {
    DisruptionSeverity.blocking => colors.cancelled,
    DisruptionSeverity.disrupted => colors.warning,
    DisruptionSeverity.info => scheme.secondary,
    null => colors.live,
  };
}

IconData severityIcon(DisruptionSeverity? severity) => switch (severity) {
      DisruptionSeverity.blocking => Icons.block,
      DisruptionSeverity.disrupted => Icons.warning_amber_rounded,
      DisruptionSeverity.info => Icons.info_outline,
      null => Icons.check_circle_outline,
    };

String severityLabel(DisruptionSeverity? severity) => switch (severity) {
      DisruptionSeverity.blocking => currentL10n.severityBlocking,
      DisruptionSeverity.disrupted => currentL10n.severityDisrupted,
      DisruptionSeverity.info => currentL10n.severityInfo,
      null => currentL10n.severityNormal,
    };

/// Small round severity marker, drawn on a corner of a line badge
class SeverityDot extends StatelessWidget {
  const SeverityDot({super.key, required this.severity, this.size = 14});

  final DisruptionSeverity severity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: severityColor(severity, scheme),
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 1.5),
      ),
      child: switch (severity) {
        DisruptionSeverity.blocking => Icon(Icons.close, size: size * 0.65, color: Colors.white),
        DisruptionSeverity.disrupted => Icon(Icons.priority_high, size: size * 0.65, color: Colors.white),
        DisruptionSeverity.info => null,
      },
    );
  }
}

/// Line badge (or any child) with a severity dot on its top right corner when disrupted
class WithSeverity extends StatelessWidget {
  const WithSeverity({super.key, required this.severity, required this.child, this.dotSize = 14});

  final DisruptionSeverity? severity;
  final Widget child;
  final double dotSize;

  @override
  Widget build(BuildContext context) {
    if (severity == null) {
      return child;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(top: -dotSize / 3, right: -dotSize / 3, child: SeverityDot(severity: severity!, size: dotSize)),
      ],
    );
  }
}

/// Disruptions of a line or a stop: active ones as cards (tap to read the message), elevator outages grouped,
/// upcoming ones at the end.
class DisruptionList extends StatelessWidget {
  const DisruptionList({super.key, required this.disruptions, this.leading});

  final List<Disruption> disruptions;

  /// Widget shown before each disruption's title (e.g. the line badges), from its line ids
  final Widget? Function(Disruption disruption)? leading;

  @override
  Widget build(BuildContext context) {
    final elevators = disruptions.where((d) => d.category == DisruptionCategory.elevator && d.active).toList();
    final active = disruptions.where((d) => d.active && d.category != DisruptionCategory.elevator).toList();
    final upcoming = disruptions.where((d) => !d.active).toList();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final disruption in active) DisruptionCard(disruption: disruption, leading: leading?.call(disruption)),
        if (elevators.isNotEmpty) _ElevatorCard(disruptions: elevators),
        if (upcoming.isNotEmpty)
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(context.l10n.upcomingDisruptions(upcoming.length),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              children: [
                for (final disruption in upcoming) DisruptionCard(disruption: disruption, leading: leading?.call(disruption)),
              ],
            ),
          ),
      ],
    );
  }
}

class DisruptionCard extends StatelessWidget {
  const DisruptionCard({super.key, required this.disruption, this.leading});

  final Disruption disruption;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = disruption.active ? severityColor(disruption.severity, theme.colorScheme) : theme.colorScheme.onSurfaceVariant;
    final period = _period(disruption, DateTime.now());
    final subtitle = [..._sections(disruption), ?period].join('\n');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: color.withValues(alpha: 0.08),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedAlignment: Alignment.topLeft,
          leading: leading ?? Icon(disruption.category == DisruptionCategory.works ? Icons.construction : severityIcon(disruption.severity), color: color),
          title: Text(disruption.title ?? severityLabel(disruption.severity),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: subtitle.isEmpty ? null : Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          children: [
            if (disruption.message != null) SelectableText(disruption.message!, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  /// "Between Châtelet and Nation", for each impacted section
  static List<String> _sections(Disruption disruption) => [
        for (final section in disruption.sections)
          if (section.fromName != null && section.toName != null) currentL10n.betweenStops(section.fromName!, section.toName!),
      ];

  static String? _period(Disruption disruption, DateTime now) {
    final start = disruption.start;
    final end = disruption.end;
    if (!disruption.active && start != null) {
      return currentL10n.fromDate('${formatDay(start, now)} ${formatClock(start)}');
    }
    // Far away ends (works planned for months, placeholder years) say nothing useful
    if (end != null && end.difference(now).inDays < 60) {
      return currentL10n.untilDate('${formatDay(end, now)} ${formatClock(end)}');
    }
    return null;
  }
}

/// One line per disruption (icon and title), the message in a dialog: compact, and sized correctly inside
/// `IntrinsicHeight` (the journey timeline), unlike the expandable cards.
class DisruptionLine extends StatelessWidget {
  const DisruptionLine({super.key, required this.disruption});

  final Disruption disruption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = severityColor(disruption.severity, theme.colorScheme);
    final title = disruption.title ?? severityLabel(disruption.severity);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(severityIcon(disruption.severity), color: color),
          title: Text(title, style: theme.textTheme.titleMedium),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(child: SelectableText(disruption.message ?? '')),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.close))],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(disruption.category == DisruptionCategory.works ? Icons.construction : severityIcon(disruption.severity),
                size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Active disruptions of a ride's line, information messages left out: the first [max] of them, one line each
class RideDisruptions extends ConsumerWidget {
  const RideDisruptions({super.key, required this.lineId, this.max = 3, this.top = 8});

  /// None for a line the GTFS doesn't know (empty id)
  final String? lineId;
  final int max;

  /// Space above them, when there are some
  final double top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lineId = this.lineId;
    if (lineId == null || lineId.isEmpty) {
      return const SizedBox.shrink();
    }
    final disruptions = (ref.watch(lineDisruptionsProvider(lineId)).value ?? const <Disruption>[])
        .where((disruption) => disruption.active && disruption.severity != DisruptionSeverity.info)
        .take(max)
        .toList();
    if (disruptions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final disruption in disruptions) DisruptionLine(disruption: disruption)],
      ),
    );
  }
}

class _ElevatorCard extends StatelessWidget {
  const _ElevatorCard({required this.disruptions});

  final List<Disruption> disruptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: context.colors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radius)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedAlignment: Alignment.topLeft,
          leading: Icon(Icons.elevator_outlined, color: color),
          title: Text(
            context.l10n.brokenElevators(disruptions.length),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          children: [
            for (final disruption in disruptions)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ${disruption.title ?? ''}', style: theme.textTheme.bodyMedium),
                    // Where it is
                    if (disruption.message != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Text(disruption.message!, style: theme.textTheme.bodySmall?.copyWith(color: color)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
