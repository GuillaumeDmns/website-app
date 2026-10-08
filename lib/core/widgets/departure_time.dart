import 'package:flutter/material.dart';

import '../api/models.dart';
import '../utils/time_format.dart';
import '../../l10n/l10n.dart';

/// Time until a departure, with the real-time signal icon (real time), or plain (schedule).
class DepartureTime extends StatelessWidget {
  const DepartureTime(this.departure, {super.key, required this.now, this.emphasized = false});

  final Departure departure;
  final DateTime now;

  /// First departure of a row: bigger
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = departure.cancelled
        ? scheme.error
        : departure.delayed
        ? Colors.orange.shade700
        : departure.realtime
        ? Colors.green.shade600
        : scheme.onSurfaceVariant;

    final label = departureLabel(departure, now);
    return Semantics(
      label: departure.realtime && !departure.cancelled ? '$label, ${context.l10n.realtime.toLowerCase()}' : label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (departure.realtime && !departure.cancelled)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(Icons.rss_feed, size: emphasized ? 12 : 10, color: color),
            ),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
              fontSize: emphasized ? 15 : 13,
              decoration: departure.cancelled ? TextDecoration.lineThrough : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
