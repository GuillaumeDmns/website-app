import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/l10n.dart';
import '../api/models.dart';
import '../utils/time_format.dart';

/// Time until a departure, Citymapper-like: the minutes in large figures, "min" small beside, green with the
/// real-time signal when it comes from real time, plain from the schedule; `À quai` (`À l'arrêt` for a bus), a clock
/// time or `Supprimé` as text.
class DepartureTime extends StatelessWidget {
  const DepartureTime(this.departure, {super.key, required this.now, this.mode, this.emphasized = false});

  final Departure departure;
  final DateTime now;

  /// Of the line: whether it stops "à quai"
  final TransportMode? mode;

  /// First departure of a row: bigger
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final live = departure.realtime && !departure.cancelled;
    final color = departure.cancelled
        ? colors.cancelled
        : departure.delayed
        ? colors.delayed
        : live
        ? colors.live
        : emphasized
        ? scheme.onSurface
        : colors.muted;

    final label = departureLabel(departure, now, mode: mode);
    // "12 min": the figure large, the unit small
    final minutes = RegExp(r'^(\d+)\s*(min)$').firstMatch(label.replaceAll(' ', ' '));
    final size = emphasized ? 22.0 : 15.0;
    final figures = TextStyle(
      color: color,
      fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
      fontSize: minutes == null ? size * 0.75 : size,
      height: 1.1,
      decoration: departure.cancelled ? TextDecoration.lineThrough : null,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Semantics(
      label: live ? '$label, ${context.l10n.realtime.toLowerCase()}' : label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (minutes != null) ...[
            Text(minutes.group(1)!, style: figures),
            Padding(
              padding: EdgeInsets.only(left: 2, top: emphasized ? 9 : 4),
              child: Text(
                minutes.group(2)!,
                style: TextStyle(color: color, fontSize: emphasized ? 12 : 11, fontWeight: FontWeight.w500, height: 1),
              ),
            ),
          ] else
            Text(label, style: figures),
          if (live)
            Padding(
              padding: const EdgeInsets.only(left: 1),
              child: Transform.rotate(angle: 0.785, child: Icon(Icons.rss_feed, size: emphasized ? 11 : 9, color: color)),
            ),
        ],
      ),
    );
  }
}

/// A clock time the real time moved, like a station's board: the planned time struck through and the new one beside
/// it, in the delay's color when late and blue when early, so that nothing is left to add up; the time alone when it
/// moved less than a minute. [stacked] puts the new time over the planned one, for narrow columns.
class RetimedClock extends StatelessWidget {
  const RetimedClock({super.key, required this.time, required this.planned, this.style, this.stacked = false});

  /// When it leaves (or gets there) now
  final DateTime time;

  /// When it was planned to, null when unknown
  final DateTime? planned;
  final TextStyle? style;
  final bool stacked;

  /// Minutes [time] moved from [planned]: late above 0, early below, 0 within a minute
  static int moved(DateTime time, DateTime? planned) => planned == null ? 0 : time.difference(planned).roundedMinutes;

  /// The color of a time moved by [minutes]: the delay's when late, blue when early, null on time
  static Color? colorOf(BuildContext context, int minutes) => switch (minutes) {
        > 0 => context.colors.delayed,
        < 0 => Theme.of(context).colorScheme.secondary,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final minutes = moved(time, planned);
    if (minutes == 0) {
      return Text(formatClock(time), style: base);
    }
    final muted = context.colors.muted;
    final now = Text(formatClock(time), style: base.copyWith(color: colorOf(context, minutes)));
    final was = Text(
      formatClock(planned!),
      style: base.copyWith(
        color: muted,
        fontWeight: FontWeight.w400,
        fontSize: (base.fontSize ?? 14) * 0.87,
        decoration: TextDecoration.lineThrough,
        decorationColor: muted,
      ),
    );
    return Semantics(
      label: context.l10n.retimedClock(formatClock(time), formatClock(planned!)),
      excludeSemantics: true,
      child: stacked
          ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [now, was])
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [was, const SizedBox(width: 5), now],
            ),
    );
  }
}
