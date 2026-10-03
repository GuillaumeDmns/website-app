import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/models.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/colors.dart';
import '../../core/location/location_providers.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/departure_time.dart';
import '../../core/widgets/line_badge.dart';
import '../traffic/disruption_widgets.dart';
import '../traffic/traffic_providers.dart';
import 'journey_providers.dart';
import 'widgets/journey_card.dart';
import 'widgets/journey_map.dart';

/// Step by step view of a journey option.
class JourneyDetailScreen extends ConsumerWidget {
  const JourneyDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journey = ref.watch(selectedJourneyProvider);
    final theme = Theme.of(context);

    void back() => context.canPop() ? context.pop() : context.go(Routes.home);

    if (journey == null) {
      // Reloaded page (web): the option was only in memory
      return Column(
        children: [
          Align(alignment: Alignment.centerLeft, child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: back)),
          const Padding(padding: EdgeInsets.all(24), child: Text('Itinéraire expiré, relancez la recherche')),
        ],
      );
    }

    return MapOverlayScope(
      overlay: journeyOverlay(context, journey),
      child: ListView(
        controller: PanelScrollScope.of(context),
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 32),
        children: [
          Row(
            children: [
              IconButton(tooltip: 'Retour', icon: const Icon(Icons.arrow_back), onPressed: back),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatDuration(journey.duration), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      [
                        '${formatClock(journey.departure)} → ${formatClock(journey.arrival)}',
                        journeyTypeLabel(journey.type),
                        if (journey.fare != null && journey.fare! > 0) formatFare(journey.fare!),
                        if (journey.co2 != null) '${journey.co2!.round()} g CO₂',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, section) in journey.sections.indexed)
                  _SectionTile(section: section, isFirst: index == 0),
                if (journey.sections.lastOrNull?.to case final end?)
                  _TimelineRow(
                    color: theme.colorScheme.error,
                    time: formatClock(journey.arrival),
                    dot: true,
                    isLast: true,
                    child: Text(end.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section, required this.isFirst});

  final JourneySection section;

  /// Only the first section shows where it starts: the others start where the previous one ended
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    switch (section.kind) {
      case SectionKind.transit:
        return _RideTile(section: section);
      case SectionKind.wait:
        return _TimelineRow(
          color: muted,
          dotted: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('Attendre ${formatDuration(section.duration)}', style: TextStyle(color: muted)),
          ),
        );
      case SectionKind.walk || SectionKind.transfer || SectionKind.bike || SectionKind.car || SectionKind.other:
        final verb = switch (section.kind) {
          SectionKind.bike => 'Pédaler',
          SectionKind.car => 'Rouler',
          SectionKind.transfer => 'Correspondance à pied',
          _ => 'Marcher',
        };
        final distance = section.length == null || section.length == 0 ? '' : ' (${formatDistance(section.length!)})';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (section.from != null && isFirst)
              _TimelineRow(
                color: muted,
                time: formatClock(section.departure),
                dot: true,
                child: Text(section.from!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            _TimelineRow(
              color: muted,
              dotted: true,
              child: section.steps.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('$verb ${formatDuration(section.duration)}$distance', style: TextStyle(color: muted)),
                    )
                  : Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('$verb ${formatDuration(section.duration)}$distance', style: TextStyle(color: muted)),
                        children: [
                          for (final step in section.steps)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.turn_right, size: 18),
                              title: Text(step.instruction),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        );
    }
  }
}

class _RideTile extends StatelessWidget {
  const _RideTile({required this.section});

  final JourneySection section;

  @override
  Widget build(BuildContext context) {
    final lineId = section.line?.id;
    final hasLine = lineId != null && lineId.isNotEmpty;
    final theme = Theme.of(context);
    final line = section.line;
    final color = parseHexColor(line?.color, theme.colorScheme.primary);
    final intermediate = section.stops.length > 2 ? section.stops.sublist(1, section.stops.length - 1) : const <JourneyStop>[];
    final delay = section.delay ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TimelineRow(
          color: color,
          time: formatClock(section.departure),
          dot: true,
          child: InkWell(
            onTap: section.from?.stopAreaId == null ? null : () => context.push(Routes.stop(section.from!.stopAreaId!)),
            child: Text(section.from?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        _TimelineRow(
          color: color,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (line != null)
                      InkWell(
                        onTap: line.id.isEmpty ? null : () => context.push(Routes.line(line.id)),
                        child: LineBadge(line, size: 26),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Direction ${section.headsign ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (section.realtime == true)
                      _Tag(
                        icon: Icons.rss_feed,
                        color: delay >= 120 ? Colors.orange.shade700 : Colors.green.shade600,
                        text: delay >= 60 ? 'Retard ${(delay / 60).round()} min' : 'Temps réel',
                      ),
                    if (section.boardingPositions.isNotEmpty)
                      _Tag(icon: Icons.train, color: theme.colorScheme.primary, text: _boardingLabel(section.boardingPositions)),
                  ],
                ),
                if (hasLine) _RideDisruptions(lineId: lineId),
                if (hasLine && section.from?.stopAreaId != null)
                  _NextDepartures(section: section, stopAreaId: section.from!.stopAreaId!, lineId: lineId),
                if (intermediate.isNotEmpty)
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        '${intermediate.length} arrêt${intermediate.length > 1 ? 's' : ''} · ${formatDuration(section.duration)}',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      children: [
                        for (final stop in intermediate)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(stop.name),
                            trailing: stop.time == null ? null : Text(formatClock(stop.time!)),
                          ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(formatDuration(section.duration), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
        ),
        _TimelineRow(
          color: color,
          time: formatClock(section.arrival),
          dot: true,
          child: InkWell(
            onTap: section.to?.stopAreaId == null ? null : () => context.push(Routes.stop(section.to!.stopAreaId!)),
            child: Text('Descendre à ${section.to?.name ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  static String _boardingLabel(List<String> positions) {
    String name(String position) => switch (position) {
          'front' => 'à l\'avant',
          'middle' => 'au milieu',
          'back' => 'à l\'arrière',
          _ => position,
        };
    return positions.length >= 3 ? 'Montez n\'importe où' : 'Montez ${positions.map(name).join(' ou ')}';
  }
}

/// Active disruptions of the ride's line (information messages left out)
class _RideDisruptions extends ConsumerWidget {
  const _RideDisruptions({required this.lineId});

  final String lineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disruptions = (ref.watch(lineDisruptionsProvider(lineId)).value ?? const <Disruption>[])
        .where((disruption) => disruption.active && disruption.severity != DisruptionSeverity.info)
        .toList();
    if (disruptions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final disruption in disruptions.take(3)) DisruptionLine(disruption: disruption)],
      ),
    );
  }
}

/// Next departures of the line at the boarding stop, towards the ride's direction when the destinations match:
/// what to take if the planned one is missed. Only for rides leaving within the next 90 min.
class _NextDepartures extends ConsumerWidget {
  const _NextDepartures({required this.section, required this.stopAreaId, required this.lineId});

  final JourneySection section;
  final String stopAreaId;
  final String lineId;

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final minutesAway = section.departure.difference(now).inMinutes;
    if (minutesAway > 90 || minutesAway < -5) {
      return const SizedBox.shrink();
    }
    final departures = ref.watch(rideDeparturesProvider((stopAreaId: stopAreaId, lineId: lineId))).value;
    final rows = departures?.lines.where((row) => row.departures.isNotEmpty).toList() ?? const <LineDepartures>[];
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final headsign = _normalize(section.headsign ?? '');
    final matching = headsign.isEmpty
        ? const <LineDepartures>[]
        : rows.where((row) {
            final destination = _normalize(row.destination);
            return destination.isNotEmpty && (destination.contains(headsign) || headsign.contains(destination));
          }).toList();
    final shown = (matching.isNotEmpty ? matching : rows).take(2).toList();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prochains départs', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            for (final row in shown)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    if (matching.isEmpty)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(row.destination, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                        ),
                      ),
                    for (final (index, departure) in row.departures.take(4).indexed) ...[
                      if (index > 0) const SizedBox(width: 12),
                      DepartureTime(departure, now: now, emphasized: index == 0),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Row of the timeline: time on the left, a vertical line (solid or dotted) with an optional stop dot, content
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.color, required this.child, this.time, this.dot = false, this.dotted = false, this.isLast = false});

  final Color color;
  final Widget child;
  final String? time;
  final bool dot;
  final bool dotted;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: time == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(time!, style: theme.textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
          ),
          SizedBox(
            width: 24,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (!(dot && isLast))
                  Positioned.fill(
                    top: dot ? 8 : 0,
                    child: Center(
                      child: dotted
                          ? _DottedLine(color: color)
                          : Container(width: 5, color: color),
                    ),
                  ),
                if (dot)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 14,
                    height: 14,
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
          Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 4), child: child)),
        ],
      ),
    );
  }
}

/// Vertical dotted line (walking); painted, since the timeline rows are sized with IntrinsicHeight
class _DottedLine extends StatelessWidget {
  const _DottedLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(4, double.infinity), painter: _DotsPainter(color));
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = 2.0; y < size.height; y += 8) {
      canvas.drawCircle(Offset(size.width / 2, y), 2, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => oldDelegate.color != color;
}
