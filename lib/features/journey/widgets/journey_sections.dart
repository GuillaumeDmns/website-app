import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/api/models.dart';
import '../../../core/location/location_providers.dart';
import '../../../core/utils/colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/departure_time.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../l10n/l10n.dart';
import '../../bikes/bike_widgets.dart';
import '../../daily_trips/daily_trip_widgets.dart';
import '../journey_labels.dart';
import '../journey_providers.dart';
import '../journey_retime.dart';
import 'journey_timeline.dart';
import 'ride_alerts.dart';
import 'ride_departures.dart';

/// A section in the journey detail's timeline: a ride, a wait, a Vélib ride or a move (its turns folded)
class JourneySectionTile extends StatelessWidget {
  const JourneySectionTile({super.key, 
    required this.section,
    required this.isFirst,
    this.ride,
    required this.onChoose,
    required this.focused,
    required this.onFocus,
  });

  final JourneySection section;

  /// A ride's departures and the one taken
  final RidePlan? ride;
  final ValueChanged<Ride> onChoose;

  /// Only the first section shows where it starts: the others start where the previous one ended
  final bool isFirst;

  /// Its stops shown, framed on the map
  final bool focused;
  final ValueChanged<bool> onFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    switch (section.kind) {
      case SectionKind.transit:
        return _RideTile(section: section, plan: ride, onChoose: onChoose, focused: focused, onFocus: onFocus);
      case SectionKind.wait:
        return TimelineRow(
          color: muted,
          dotted: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(context.l10n.waitFor(formatDuration(section.duration)), style: TextStyle(color: muted)),
          ),
        );
      case SectionKind.bike when section.from?.name.startsWith('Station Vélib') ?? false:
        return _BikeShareTile(section: section);
      case SectionKind.walk || SectionKind.transfer || SectionKind.bike || SectionKind.car || SectionKind.other:
        final verb = switch (section.kind) {
          SectionKind.bike => context.l10n.sectionBike,
          SectionKind.car => context.l10n.sectionCar,
          SectionKind.transfer => context.l10n.sectionTransfer,
          _ => context.l10n.sectionWalk,
        };
        // `Marche · 6 min · 450 m`, its icon first
        final label = [
          verb,
          formatDuration(section.duration),
          if ((section.length ?? 0) > 0) formatDistance(section.length!),
        ].join(' · ');
        final icon = section.kind == SectionKind.transfer ? Icons.transfer_within_a_station : moveIcon(section.kind);
        final title = Row(
          children: [
            Icon(icon, size: 18, color: muted),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (section.from != null && isFirst)
              TimelineRow(
                color: theme.colorScheme.onSurface,
                time: formatClock(section.departure),
                dot: true,
                dotted: true,
                child: Text(section.from!.name, style: theme.textTheme.titleSmall),
              ),
            TimelineRow(
              color: muted,
              dotted: true,
              child: section.steps.isEmpty
                  ? Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: title)
                  : Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: title,
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

/// Vélib ride: the stations with their live availability (bikes where it starts, free docks where it ends)
class _BikeShareTile extends ConsumerWidget {
  const _BikeShareTile({required this.section});

  final JourneySection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    BikeStation? station(JourneyPoint? point) => point == null
        ? null
        : ref.watch(nearbyBikesProvider((lat: point.lat, lon: point.lon, radius: 60, limit: 1))).value?.firstOrNull;
    final take = station(section.from);
    final leave = station(section.to);
    final distance = section.length == null || section.length == 0 ? '' : ' (${formatDistance(section.length!)})';

    Widget stationRow(JourneyPoint? point, BikeStation? live, {required bool start}) => TimelineRow(
      color: velibColor,
      time: formatClock(start ? section.departure : section.arrival),
      dot: true,
      child: InkWell(
        onTap: live == null ? null : () => showBikeStationSheet(context, live),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (start ? context.l10n.bikePickUp : context.l10n.bikeDropOff)(
                point?.name.replaceFirst('Station Vélib ', '') ?? '',
              ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (live != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: BikeCounts(station: live, bikes: start, docks: !start),
              ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        stationRow(section.from, take, start: true),
        TimelineRow(
          color: velibColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              context.l10n.bikeRideEstimated(formatDuration(section.duration), distance),
              style: TextStyle(color: muted),
            ),
          ),
        ),
        stationRow(section.to, leave, start: false),
      ],
    );
  }
}

/// A ride: where to board, the line and its direction with one small icon when something goes wrong (its alerts in a
/// sheet), its tags and departures, the stops between (folded), where to get off. Where to board along the train and
/// the platform are GO's and the departures' (each row has its platform).
class _RideTile extends StatelessWidget {
  const _RideTile({required this.section, required this.plan, required this.onChoose, required this.focused, required this.onFocus});

  final JourneySection section;
  final RidePlan? plan;
  final ValueChanged<Ride> onChoose;

  /// Its stops shown in the timeline, and the ride framed on the map
  final bool focused;
  final ValueChanged<bool> onFocus;

  @override
  Widget build(BuildContext context) {
    final lineId = section.line?.id;
    final hasLine = lineId != null && lineId.isNotEmpty;
    final theme = Theme.of(context);
    final line = section.line;
    final color = parseHexColor(line?.color, theme.colorScheme.primary);
    final intermediate = section.stops.length > 2
        ? section.stops.sublist(1, section.stops.length - 1)
        : const <JourneyStop>[];
    final delay = section.delay ?? 0;
    final planned = section.departure.subtract(Duration(seconds: delay));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TimelineRow(
          color: color,
          time: formatClock(section.departure),
          // Late or early by the real time, its clock printing another minute: the planned time struck through under
          // the new one, as in its departures below
          clock: RetimedClock.moved(section.departure, planned) != 0
              ? RetimedClock(time: section.departure, planned: planned, stacked: true)
              : null,
          dot: true,
          child: InkWell(
            onTap: section.from?.stopAreaId == null ? null : () => context.push(Routes.stop(section.from!.stopAreaId!)),
            child: Text(section.from?.name ?? '', style: theme.textTheme.titleSmall),
          ),
        ),
        TimelineRow(
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
                      child: Text(
                        context.l10n.direction(section.headsign ?? ''),
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (hasLine) RideAlertsButton(section: section),
                  ],
                ),
                // The real time shows in its departures (their minutes in green, with its signal): no tag for it here
                if (hasLine) Padding(padding: const EdgeInsets.only(top: 6), child: LastRideTag(ride: section)),
                if (plan != null) _RideDepartures(plan: plan!, mode: section.line?.mode, onChoose: onChoose),
                if (intermediate.isNotEmpty)
                  // The stops between, like Citymapper: below, on the line
                  InkWell(
                    onTap: () => onFocus(!focused),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${context.l10n.stopsCount(intermediate.length)} · ${formatDuration(section.duration)}',
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          Icon(focused ? Icons.expand_less : Icons.expand_more, color: theme.colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      formatDuration(section.duration),
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (focused)
          for (final stop in intermediate)
            TimelineRow(
              color: color,
              time: stop.time == null ? null : formatClock(stop.time!),
              stopDot: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(stop.name, style: theme.textTheme.bodyMedium),
              ),
            ),
        TimelineRow(
          color: color,
          time: formatClock(section.arrival),
          dot: true,
          child: InkWell(
            onTap: section.to?.stopAreaId == null ? null : () => context.push(Routes.stop(section.to!.stopAreaId!)),
            child: Text(context.l10n.getOffAt(section.to?.name ?? ''), style: theme.textTheme.titleSmall),
          ),
        ),
      ],
    );
  }
}

/// Departures of the ride's line at the boarding stop that stop at the alighting one, from when the traveller can
/// be there: the one taken is highlighted, choosing another one moves the journey to it.
class _RideDepartures extends ConsumerWidget {
  const _RideDepartures({required this.plan, this.mode, required this.onChoose});

  final RidePlan plan;
  final TransportMode? mode;
  final ValueChanged<Ride> onChoose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final rides = ref.watch(rideOptionsProvider(plan.key)).value ?? const <Ride>[];
    if (rides.isEmpty) {
      return const SizedBox.shrink();
    }
    final taken = plan.ride;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RideDepartureList(
            rides: rides,
            now: now,
            mode: mode,
            selected: taken,
            earliest: plan.earliest,
            onSelect: onChoose,
            onAllDepartures: () => context.push(Routes.stop(plan.key.from)),
          ),
          // If it is missed: the next one
          IfMissedLine(rides: rides, taken: taken),
        ],
      ),
    );
  }
}
