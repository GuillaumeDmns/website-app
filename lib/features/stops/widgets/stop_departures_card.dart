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
import '../../go/go_instruction.dart';

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
            DepartureTime(departure, now: now),
            const SizedBox(width: 10),
          ],
          if (departures.isNotEmpty) DepartureTime(departures.first, now: now, emphasized: true),
        ],
      ),
    );
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}
