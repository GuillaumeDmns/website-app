import 'package:flutter/material.dart';

import '../../../core/api/models.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/departure_time.dart';

/// Next departures for a ride, like Citymapper: one row per departure with its times at both stops, mission code,
/// destination and platform. The [selected] one is raised and scrolled into view when it changes.
class RideDepartureList extends StatefulWidget {
  const RideDepartureList({
    super.key,
    required this.rides,
    required this.now,
    this.selected,
    this.onSelect,
    this.onAllDepartures,
  });

  final List<Ride> rides;
  final DateTime now;
  final Ride? selected;

  /// Choosing another departure; rows are not tappable without it
  final ValueChanged<Ride>? onSelect;

  /// Opens the boarding stop's departures
  final VoidCallback? onAllDepartures;

  /// The departure planned at [planned]: closest scheduled time, a few minutes off at most
  static Ride? planned(List<Ride> rides, DateTime planned) {
    Ride? best;
    var bestGap = const Duration(minutes: 4);
    for (final ride in rides) {
      final gap = (ride.departure.aimedTime ?? ride.departure.time).difference(planned).abs();
      if (gap <= bestGap) {
        bestGap = gap;
        best = ride;
      }
    }
    return best;
  }

  @override
  State<RideDepartureList> createState() => _RideDepartureListState();
}

class _RideDepartureListState extends State<RideDepartureList> {
  static const _rowHeight = 62.0;

  /// Rows visible at once; the half row shows the list goes on
  static const _visibleRows = 3.5;

  final _scroll = ScrollController();

  /// Selection last scrolled to, so that refreshes don't move the list under the user's finger
  Object? _scrolledTo;

  static Object _key(Ride ride) => ride.departure.trainNumber ?? ride.departure.aimedTime ?? ride.departure.time;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected(animate: false));
  }

  @override
  void didUpdateWidget(RideDepartureList oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected(animate: true));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToSelected({required bool animate}) {
    final selected = widget.selected;
    if (!mounted || selected == null || !_scroll.hasClients || _key(selected) == _scrolledTo) {
      return;
    }
    final index = widget.rides.indexWhere((ride) => _key(ride) == _key(selected));
    if (index < 0) {
      return;
    }
    _scrolledTo = _key(selected);
    // The row before stays visible: the departure just missed
    final offset = ((index - 1) * _rowHeight).clamp(0.0, _scroll.position.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(offset, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    } else {
      _scroll.jumpTo(offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rides = widget.rides;
    final selected = widget.selected;
    final height = (rides.length < _visibleRows ? rides.length : _visibleRows) * _rowHeight + 8;

    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? theme.colorScheme.surfaceContainerLow
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemExtent: _rowHeight,
              itemCount: rides.length,
              itemBuilder: (context, i) {
                final ride = rides[i];
                final isSelected = selected != null && _key(ride) == _key(selected);
                return _RideRow(
                  ride: ride,
                  now: widget.now,
                  selected: isSelected,
                  onTap: widget.onSelect == null || isSelected || ride.departure.cancelled
                      ? null
                      : () => widget.onSelect!(ride),
                );
              },
            ),
          ),
          if (widget.onAllDepartures != null) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            InkWell(
              onTap: widget.onAllDepartures,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(child: Text('Tous les départs', style: theme.textTheme.labelLarge)),
                    Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `20:56 → 21:03 (6 min)` / `PEBU Paris Saint-Lazare`, time until it leaves and platform on the right
class _RideRow extends StatelessWidget {
  const _RideRow({required this.ride, required this.now, required this.selected, this.onTap});

  final Ride ride;
  final DateTime now;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final departure = ride.departure;
    final arrival = ride.arrivalAt;
    final late = departure.aimedTime == null ? 0 : (departure.time.difference(departure.aimedTime!).inSeconds / 60).round();
    final minutes = arrival == null ? null : (arrival.difference(departure.time).inSeconds / 60).round();
    const figures = [FontFeature.tabularFigures()];

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      formatClock(departure.time),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        fontFeatures: figures,
                        decoration: departure.cancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (late.abs() >= 1 && !departure.cancelled)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          late > 0 ? '+$late' : '$late',
                          style: TextStyle(
                            color: late > 0 ? Colors.orange.shade800 : Colors.blue.shade700,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (arrival != null && !departure.cancelled) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward, size: 14, color: muted),
                      ),
                      Text(
                        '${ride.arrivalSource == ArrivalSource.typical ? '~' : ''}${formatClock(arrival)}',
                        style: TextStyle(color: muted, fontSize: 15, fontFeatures: figures),
                      ),
                      if (minutes != null && minutes > 0)
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text('$minutes\u00a0min',
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(color: muted, fontSize: 12, fontFeatures: figures)),
                          ),
                        ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (departure.mission != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(departure.mission!,
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      ),
                    Expanded(
                      child: Text(ride.destination,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DepartureTime(departure, now: now, emphasized: true),
              if (departure.platform != null)
                Text('Voie ${departure.platform}', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
          ),
        ],
      ),
    );

    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Material(
        color: selected
            ? (dark ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.surfaceContainerLowest)
            : Colors.transparent,
        elevation: selected ? 3 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selected ? BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5)) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
