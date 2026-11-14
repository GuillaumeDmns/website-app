import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/api/models.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/departure_time.dart';
import '../../../l10n/l10n.dart';
import '../journey_retime.dart';
import '../../../app/theme.dart';

/// Next departures for a ride, like Citymapper: one row per departure with its times at both stops, mission code,
/// destination and platform. The [selected] one is raised and scrolled into view when it changes. [compact] (the
/// journey detail, read before leaving) says each thing once: no ride time per row (the same on each, said under the
/// list), no clock time on the right repeating the row's, the destinations only when they differ.
class RideDepartureList extends StatefulWidget {
  const RideDepartureList({
    super.key,
    required this.rides,
    required this.now,
    this.mode,
    this.selected,
    this.earliest,
    this.compact = false,
    this.onSelect,
    this.onAllDepartures,
  });

  final List<Ride> rides;
  final DateTime now;

  /// Of the line: whether it stops "à quai"
  final TransportMode? mode;
  final Ride? selected;

  /// When the traveller can be at the stop: departures before are faded
  final DateTime? earliest;

  /// See [RideDepartureList]
  final bool compact;

  /// Choosing another departure; rows are not tappable without it
  final ValueChanged<Ride>? onSelect;

  /// Opens the boarding stop's departures
  final VoidCallback? onAllDepartures;

  @override
  State<RideDepartureList> createState() => _RideDepartureListState();
}

class _RideDepartureListState extends State<RideDepartureList> {
  static const _rowHeight = 62.0;

  /// Compact rows: the times alone
  static const _timesRowHeight = 46.0;

  /// Rows visible at once; the half row shows the list goes on
  static const _visibleRows = 3.5;

  final _scroll = ScrollController();

  /// Selection last scrolled to, so that refreshes don't move the list under the user's finger
  Ride? _scrolledTo;

  /// Row height with the user's text size
  double _rowExtent = _rowHeight;

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
    final last = _scrolledTo;
    if (!mounted || selected == null || !_scroll.hasClients || (last != null && sameRide(last, selected))) {
      return;
    }
    final index = _selectedIndex(widget.rides, selected);
    if (index < 0) {
      return;
    }
    _scrolledTo = selected;
    // The row before stays visible: the departure just missed
    final offset = ((index - 1) * _rowExtent).clamp(0.0, _scroll.position.maxScrollExtent);
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
    final selectedIndex = _selectedIndex(rides, selected);
    // Compact: a second line only for destinations that differ (the direction is said above the list)
    final destinations = !widget.compact || {for (final ride in rides) ride.destination}.length > 1;
    _rowExtent = MediaQuery.textScalerOf(context).scale(destinations ? _rowHeight : _timesRowHeight);
    final height = (rides.length < _visibleRows ? rides.length : _visibleRows) * _rowExtent + 8;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline, width: 0.5),
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
              itemExtent: _rowExtent,
              itemCount: rides.length,
              itemBuilder: (context, i) {
                final ride = rides[i];
                final isSelected = i == selectedIndex;
                final earliest = widget.earliest;
                return _RideRow(
                  ride: ride,
                  now: widget.now,
                  mode: widget.mode,
                  selected: isSelected,
                  compact: widget.compact,
                  destination: destinations,
                  tooEarly:
                      earliest != null && ride.departure.time.isBefore(earliest.subtract(const Duration(minutes: 1))),
                  onTap: widget.onSelect == null || isSelected || ride.departure.cancelled
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          widget.onSelect!(ride);
                        },
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
                    Expanded(child: Text(context.l10n.allDepartures, style: theme.textTheme.labelLarge)),
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

/// The row of [selected], raised: the departure itself, else the first one like it (a line serving two stops of a stop
/// area lists a vehicle twice, at the same time: one row raised, the other one can be chosen)
int _selectedIndex(List<Ride> rides, Ride? selected) => selected == null
    ? -1
    : rides.contains(selected)
    ? rides.indexOf(selected)
    : rides.indexWhere((ride) => sameRide(ride, selected));

/// `20:56 → 21:03 (6 min)` / `PEBU Paris Saint-Lazare`, time until it leaves and platform on the right
class _RideRow extends StatelessWidget {
  const _RideRow({
    required this.ride,
    required this.now,
    this.mode,
    required this.selected,
    required this.compact,
    required this.destination,
    required this.tooEarly,
    this.onTap,
  });

  final Ride ride;
  final DateTime now;
  final TransportMode? mode;
  final bool selected;

  /// See [RideDepartureList.compact]
  final bool compact;

  /// Its mission and destination on a second line
  final bool destination;

  /// Leaves before the traveller can be at the stop
  final bool tooEarly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final departure = ride.departure;
    final arrival = ride.arrivalAt;
    final minutes = arrival?.difference(departure.time).roundedMinutes;
    const figures = [FontFeature.tabularFigures()];
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    // Over an hour ahead, the time left would be the clock time of the row once more
    final countdown = !compact || departure.cancelled || departure.atStop == true || departure.time.difference(now).inMinutes < 60;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Scaled down rather than cut when the text is large
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      if (departure.cancelled)
                        Text(
                          formatClock(departure.time),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            fontFeatures: figures,
                            decoration: TextDecoration.lineThrough,
                          ),
                        )
                      else
                        // Moved by the real time: the planned time struck through, the new one beside it
                        RetimedClock(
                          time: departure.time,
                          planned: departure.aimedTime,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
                        if (minutes != null && minutes > 0 && !largeText && !compact)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              context.l10n.minutesShort(minutes).replaceAll(' ', '\u00a0'),
                              style: TextStyle(color: muted, fontSize: 12, fontFeatures: figures),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                if (destination) const SizedBox(height: 2),
                if (destination) Row(
                  children: [
                    if (departure.mission != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          departure.mission!,
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        ride.destination,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
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
              if (countdown) DepartureTime(departure, now: now, mode: mode, emphasized: true),
              if (departure.platform != null)
                Text(
                  context.l10n.platform(departure.platform!),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Material(
        color: selected ? theme.colorScheme.primary.withValues(alpha: 0.08) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selected ? BorderSide(color: theme.colorScheme.primary, width: 1.5) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: tooEarly && !selected ? Opacity(opacity: 0.45, child: content) : content,
        ),
      ),
    );
  }
}
