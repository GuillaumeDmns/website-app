import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/api/models.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/departure_time.dart';
import '../../../core/widgets/line_badge.dart';

/// Next departures of a stop area, one row per line and destination (Citymapper "nearby" card).
class StopDeparturesCard extends StatelessWidget {
  const StopDeparturesCard({super.key, required this.departures, required this.now, this.maxRows = 6});

  final StopDepartures departures;
  final DateTime now;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stop = departures.stop;
    final rows = departures.lines.where((line) => line.departures.isNotEmpty).toList();
    final hidden = rows.length - maxRows;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.stop(stop.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(stop.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (stop.distance != null)
                    Text(formatDistance(stop.distance!), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              if (!departures.realtimeAvailable)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Temps réel indisponible, horaires prévus',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange.shade700)),
                ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Aucun départ dans les 2 prochaines heures',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              for (final row in rows.take(maxRows)) LineDeparturesRow(row: row, now: now),
              if (hidden > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text('+ $hidden autres directions',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Line badge, destination and the next departures
class LineDeparturesRow extends StatelessWidget {
  const LineDeparturesRow({super.key, required this.row, required this.now, this.onTap});

  final LineDepartures row;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final departures = row.departures;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          LineBadge(row.line, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(row.destination, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          if (departures.isNotEmpty) DepartureTime(departures.first, now: now, emphasized: true),
          for (final departure in departures.skip(1).take(2)) ...[
            const SizedBox(width: 10),
            DepartureTime(departure, now: now),
          ],
        ],
      ),
    );
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}
