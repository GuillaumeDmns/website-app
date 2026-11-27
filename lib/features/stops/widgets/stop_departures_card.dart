import 'package:material_ui/material_ui.dart';
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
            if (index > 0) const Divider(indent: 48),
            LineDeparturesRow(row: row, now: now, realtimeAvailable: departures.realtimeAvailable),
          ],
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6, left: 48),
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

/// `puis 12 et 47 min`: the departures after the first one (cancelled ones left out), at most [count]; null without
/// any. Minutes are counted once (`12 et 47 min`), other labels said whole (`puis 58 min et 14:05`).
String? followingDepartures(List<Departure> departures, DateTime now, {TransportMode? mode, int count = 2}) {
  final labels = [
    for (final departure in departures.skip(1).where((departure) => !departure.cancelled).take(count))
      departureLabel(departure, now, mode: mode),
  ];
  if (labels.isEmpty) {
    return null;
  }
  final unit = RegExp(r'^(\d+)[\s\u00a0]*min$');
  final allMinutes = labels.every(unit.hasMatch);
  final items = allMinutes ? [for (final label in labels) unit.firstMatch(label)!.group(1)!] : labels;
  final joined = items.length == 1
      ? items.single
      : '${items.sublist(0, items.length - 1).join(', ')} ${currentL10n.and} ${items.last}';
  return currentL10n.thenDepartures(allMinutes ? '$joined min' : joined);
}

/// Line badge, the destination in clear, the next departure large on the right; the following ones under the
/// destination (`puis 12 et 47 min`), with what there is to know about the first one: only scheduled, its platform
class LineDeparturesRow extends StatelessWidget {
  const LineDeparturesRow({
    super.key,
    required this.row,
    required this.now,
    this.realtimeAvailable = true,
    this.onTap,
    this.onLongPress,
    this.showBadge = true,
    this.approach,
  });

  final LineDepartures row;
  final DateTime now;

  /// False under its line's header (a stop's page): its place kept, the destinations in line with the header's text
  final bool showBadge;

  /// Where the vehicle of its next departure is, `à 2 arrêts d'ici`, before the following departures
  final String? approach;

  /// False when the whole stop only has scheduled times, already said above its rows
  final bool realtimeAvailable;
  final VoidCallback? onTap;

  /// Long press: following its next departure
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final departures = row.departures;
    final first = departures.firstOrNull;
    // Large text: fewer times, so that the line stays readable
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final following = followingDepartures(departures, now, mode: row.line.mode, count: textScale >= 1.3 ? 1 : 2);
    final notes = [
      ?approach,
      ?following,
      if (first != null && !first.realtime && !first.cancelled && realtimeAvailable) context.l10n.goScheduled,
      ?platformLabel(row.line, first?.platform),
    ].join(' · ');
    // `puis 12 et 47 min · voie 2` goes on from the departure on the right; alone, a note starts its own line
    final details = (following != null && approach == null) || notes.isEmpty ? notes : '${notes[0].toUpperCase()}${notes.substring(1)}';
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 48, child: showBadge ? Align(alignment: Alignment.centerLeft, child: LineBadge(row.line, size: 28)) : null),
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
                if (details.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.colors.muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (first != null) DepartureTime(first, now: now, mode: row.line.mode, emphasized: true),
        ],
      ),
    );
    return onTap == null && onLongPress == null ? content : InkWell(onTap: onTap, onLongPress: onLongPress, child: content);
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
  const TrainDepartureRow({super.key, required this.line, required this.departure, required this.destination, required this.now, this.onTap, this.onLongPress});

  final LineSummary line;
  final Departure departure;
  final String destination;
  final DateTime now;
  final VoidCallback? onTap;

  /// Long press: following this departure
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    const figures = [FontFeature.tabularFigures()];
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 48, child: Align(alignment: Alignment.centerLeft, child: LineBadge(line, size: 28))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (departure.cancelled)
                  Text(
                    formatClock(departure.aimedTime ?? departure.time),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      fontFeatures: figures,
                      decoration: TextDecoration.lineThrough,
                    ),
                  )
                else
                  // Delayed or early: the planned time struck through, the new one beside it
                  RetimedClock(
                    time: departure.time,
                    planned: departure.aimedTime,
                    delayed: departure.delayed,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
    return onTap == null && onLongPress == null ? content : InkWell(onTap: onTap, onLongPress: onLongPress, child: content);
  }
}
