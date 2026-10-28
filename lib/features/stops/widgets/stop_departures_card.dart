import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/departure_time.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/ui.dart';
import '../../../l10n/l10n.dart';
import '../../journey/journey_labels.dart';

/// Minutes on foot for [meters] (about 80 m a minute)
int walkingMinutes(int meters) => (meters / 80).ceil().clamp(1, 999);

/// Next departures of a stop area, one row per line and destination (Citymapper's "nearby" card).
class StopDeparturesCard extends StatelessWidget {
  const StopDeparturesCard({super.key, required this.departures, required this.now, this.maxRows = 6, this.onLongPress});

  final StopDepartures departures;
  final DateTime now;
  final int maxRows;

  /// Long press (right click): saving the stop, around
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final stop = departures.stop;
    final rows = departures.lines.where((line) => line.departures.isNotEmpty).toList();
    final hidden = rows.length - maxRows;

    return AppCard(
      onTap: () => context.push(Routes.stop(stop.id)),
      onLongPress: onLongPress,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(stop.name, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (stop.distance != null) ...[
                Icon(Icons.directions_walk, size: 16, color: colors.muted),
                Text(
                  context.l10n.minutesShort(walkingMinutes(stop.distance!)),
                  style: theme.textTheme.bodySmall,
                  semanticsLabel: formatDistance(stop.distance!),
                ),
              ],
            ],
          ),
          if (!departures.realtimeAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: NoticeLine(icon: Icons.schedule, text: context.l10n.realtimeUnavailable),
            ),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(context.l10n.noDepartureTwoHours, style: theme.textTheme.bodySmall),
            ),
          for (final (index, row) in rows.take(maxRows).indexed) ...[
            if (index > 0) const Divider(indent: 40),
            LineDeparturesRow(row: row, now: now),
          ],
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6, left: 40),
              child: Text(
                context.l10n.otherDirections(hidden),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

/// Line badge, destination, then the next departures: the first one large, the following ones beside
class LineDeparturesRow extends StatelessWidget {
  const LineDeparturesRow({super.key, required this.row, required this.now, this.onTap});

  final LineDepartures row;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final departures = row.departures;
    // Large text: fewer times, so that the destination stays readable
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final more = textScale >= 1.6
        ? 0
        : textScale >= 1.25
        ? 1
        : 2;
    final platform = departures.firstOrNull?.platform;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 40, child: Align(alignment: Alignment.centerLeft, child: LineBadge(row.line, size: 28))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.destination,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                ),
                if (platformLabel(row.line, platform) case final label? when textScale < 1.3)
                  Text('${label[0].toUpperCase()}${label.substring(1)}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          for (final departure in departures.skip(1).take(more).toList().reversed) ...[
            DepartureTime(departure, now: now, mode: row.line.mode),
            const SizedBox(width: 10),
          ],
          if (departures.isNotEmpty) DepartureTime(departures.first, now: now, mode: row.line.mode, emphasized: true),
        ],
      ),
    );
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}

/// A train line's departures from a stop as one board in time order, its destinations mixed, like a station's (and
/// Citymapper's): up to where every destination's departures are known, since the feed gives [perDestination] of each
/// and a frequent destination's run out sooner
List<({Departure departure, String destination})> trainBoard(List<LineDepartures> rows, {required int perDestination}) {
  DateTime? horizon;
  for (final row in rows) {
    if (row.departures.length >= perDestination) {
      final last = row.departures.last.time;
      horizon = horizon == null || last.isBefore(horizon) ? last : horizon;
    }
  }
  return [
    for (final row in rows)
      for (final departure in row.departures)
        if (horizon == null || !departure.time.isAfter(horizon)) (departure: departure, destination: row.destination),
  ]..sort((a, b) => a.departure.time.compareTo(b.departure.time));
}

/// A train of a station's board: its time and delay, mission code and destination, then the time until it leaves
/// and its platform on the right
class TrainDepartureRow extends StatelessWidget {
  const TrainDepartureRow({super.key, required this.line, required this.departure, required this.destination, required this.now, this.onTap});

  final LineSummary line;
  final Departure departure;
  final String destination;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final late = departure.aimedTime == null ? 0 : departure.time.difference(departure.aimedTime!).roundedMinutes;
    const figures = [FontFeature.tabularFigures()];
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 40, child: Align(alignment: Alignment.centerLeft, child: LineBadge(line, size: 28))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      formatClock(departure.aimedTime ?? departure.time),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        fontFeatures: figures,
                        decoration: departure.cancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (late >= 1 && !departure.cancelled)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          context.l10n.delayedTo(formatClock(departure.time)),
                          style: TextStyle(color: colors.delayed, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    if (departure.mission case final mission?)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(mission, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                      ),
                    Expanded(child: Text(destination, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DepartureTime(departure, now: now, mode: line.mode, emphasized: true),
              if (platformLabel(line, departure.platform) case final label?)
                Text('${label[0].toUpperCase()}${label.substring(1)}', style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
            ],
          ),
        ],
      ),
    );
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}
