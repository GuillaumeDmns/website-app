import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/line_badge.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/l10n.dart';
import '../../app/theme.dart';

/// First and last departures of the lines of a stop area today, and their frequency (GTFS: no real-time call)
final stopServiceHoursProvider = FutureProvider.autoDispose.family<StopServiceHours, String>(
  (ref, stopAreaId) => ref.watch(mobilityApiProvider).stopServiceHours(stopAreaId),
);

/// First and last departures of each direction of a line today, and its frequency
final lineServiceHoursProvider = FutureProvider.autoDispose.family<LineServiceHours, String>(
  (ref, lineId) => ref.watch(mobilityApiProvider).lineServiceHours(lineId),
);

/// A last departure this close is announced
const lastDepartureWarning = Duration(minutes: 60);

/// `toutes les 4 min`, `toutes les 2–4 min`, `toutes les 1 h 05`; the number of departures for a single one
String frequencyLabel(Frequency frequency) {
  final min = frequency.minMinutes;
  final max = frequency.maxMinutes ?? min;
  if (min == null || max == null) {
    return currentL10n.departuresCount(frequency.departures);
  }
  final interval = min == max
      ? formatDuration(min * 60)
      : max < 60
      ? '$min\u2060–\u2060${formatDuration(max * 60)}'
      : '${formatDuration(min * 60)}\u2060–\u2060${formatDuration(max * 60)}';
  return currentL10n.frequencyEvery(interval);
}

String periodLabel(ServicePeriod period) => switch (period) {
  ServicePeriod.earlyMorning => currentL10n.periodEarlyMorning,
  ServicePeriod.morningPeak => currentL10n.periodMorningPeak,
  ServicePeriod.daytime => currentL10n.periodDaytime,
  ServicePeriod.eveningPeak => currentL10n.periodEveningPeak,
  ServicePeriod.evening => currentL10n.periodEvening,
  ServicePeriod.night => currentL10n.periodNight,
};

/// What matters now about a direction's service: its last departure soon, the service over or not started yet,
/// else how often it leaves
({String text, bool warning}) serviceStatus(ServiceDirection direction, DateTime now) {
  if (now.isAfter(direction.last)) {
    return (text: currentL10n.serviceOver, warning: true);
  }
  if (now.isBefore(direction.first)) {
    return (text: currentL10n.serviceNotStarted(formatClock(direction.first)), warning: false);
  }
  final untilLast = direction.last.difference(now);
  if (untilLast <= lastDepartureWarning) {
    return (text: currentL10n.lastDepartureIn(formatDuration(untilLast.inSeconds)), warning: true);
  }
  final frequency = direction.frequencyAt(now);
  return (text: frequency == null ? '' : currentL10n.frequencyNow(frequencyLabel(frequency)), warning: false);
}

/// Today's first and last departures of each line of a stop, per direction; a row unfolds its frequencies
class StopServiceHoursSection extends ConsumerWidget {
  const StopServiceHoursSection({super.key, required this.stopAreaId});

  final String stopAreaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hours = ref.watch(stopServiceHoursProvider(stopAreaId));
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final theme = Theme.of(context);
    // A bonus of the stop page: nothing while loading, a short line on failure
    return switch (hours) {
      AsyncData(:final value) when value.lines.isNotEmpty => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(context.l10n.serviceHoursTitle),
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, (line, direction)) in [
                  for (final line in value.lines)
                    for (final direction in line.directions) (line.line, direction),
                ].indexed) ...[
                  if (index > 0) const Divider(indent: 36),
                  ServiceDirectionTile(line: line, direction: direction, now: now, onLine: () => context.push(Routes.line(line.id))),
                ],
              ],
            ),
          ),
        ],
      ),
      AsyncError() when !hours.hasValue => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
        child: Text(context.l10n.serviceHoursUnavailable, style: theme.textTheme.bodySmall),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// A direction's first and last departures and what matters now; tapped, its frequency over the day
class ServiceDirectionTile extends StatefulWidget {
  const ServiceDirectionTile({super.key, this.line, required this.direction, required this.now, this.onLine});

  /// Shown as a badge (stop pages); null on a line's page
  final LineSummary? line;
  final ServiceDirection direction;
  final DateTime now;
  final VoidCallback? onLine;

  @override
  State<ServiceDirectionTile> createState() => _ServiceDirectionTileState();
}

class _ServiceDirectionTileState extends State<ServiceDirectionTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final direction = widget.direction;
    final status = serviceStatus(direction, widget.now);
    final line = widget.line;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                if (line != null) ...[
                  InkWell(onTap: widget.onLine, child: LineBadge(line, size: 26)),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line == null ? context.l10n.serviceFirstLast(formatClock(direction.first), formatClock(direction.last))
                            : context.l10n.towards(direction.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (status.text.isNotEmpty)
                        Text(
                          status.text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: status.warning ? context.colors.warning : muted,
                            fontWeight: status.warning ? FontWeight.w600 : null,
                          ),
                        ),
                    ],
                  ),
                ),
                if (line != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.serviceFirstLast(formatClock(direction.first), formatClock(direction.last)),
                    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ],
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20, color: muted),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: EdgeInsets.only(left: line == null ? 0 : 36, bottom: 8),
            child: FrequencyTable(direction: direction, now: widget.now),
          ),
      ],
    );
  }
}

/// Frequency of each period of the day, the current one raised
class FrequencyTable extends StatelessWidget {
  const FrequencyTable({super.key, required this.direction, required this.now});

  final ServiceDirection direction;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = direction.frequencyAt(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final frequency in direction.frequencies)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontWeight: frequency == current ? FontWeight.w600 : null,
                color: frequency == current ? null : theme.colorScheme.onSurfaceVariant,
              ),
              child: Wrap(
                spacing: 12,
                children: [
                  SizedBox(
                    width: MediaQuery.textScalerOf(context).scale(120),
                    child: Text(periodLabel(frequency.period)),
                  ),
                  Text(
                    '${formatClock(frequency.start)}–${formatClock(frequency.end)}',
                    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                  Text(frequencyLabel(frequency)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Today's first and last departures of a direction of a line (index [direction] of its detail), what matters now,
/// and its frequencies unfolded on demand
class LineServiceHoursSummary extends ConsumerWidget {
  const LineServiceHoursSummary({super.key, required this.lineId, required this.direction});

  final String lineId;
  final int direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hours = ref.watch(lineServiceHoursProvider(lineId)).value;
    final service = hours?.directions.where((candidate) => candidate.direction == direction).firstOrNull;
    if (service == null) {
      return const SizedBox.shrink();
    }
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [context.l10n.serviceHoursTitle, if (service.at case final at?) context.l10n.serviceCountedAt(at.name)].join(' '),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          ServiceDirectionTile(direction: service, now: now),
        ],
      ),
    );
  }
}
