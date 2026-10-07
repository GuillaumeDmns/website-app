import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/models.dart';
import '../../core/map/map_overlay.dart';
import '../../core/platform/share.dart';
import '../../core/location/location_providers.dart';
import '../../core/utils/colors.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/line_badge.dart';
import '../../l10n/l10n.dart';
import '../bikes/bike_widgets.dart';
import '../go/go_controller.dart';
import '../traffic/disruption_widgets.dart';
import '../traffic/traffic_providers.dart';
import 'journey_providers.dart';
import 'journey_request.dart';
import 'journey_retime.dart';
import 'widgets/journey_card.dart';
import 'widgets/journey_map.dart';
import 'widgets/ride_departures.dart';

/// Step by step view of a journey option. Each ride lists its departures; choosing another one moves the journey
/// to it, the following connections included (see [retimeJourney]).
class JourneyDetailScreen extends ConsumerStatefulWidget {
  const JourneyDetailScreen({super.key, this.query = ''});

  /// Search, departure time and lines of the option (`Routes.journeyDetailOf`): the option is found again from them
  /// when it is not in memory (web reload, shared link)
  final String query;

  @override
  ConsumerState<JourneyDetailScreen> createState() => _JourneyDetailScreenState();
}

class _JourneyDetailScreenState extends ConsumerState<JourneyDetailScreen> {
  /// Departures chosen by section index, for [_choicesOf]
  Map<int, Ride> _choices = const {};
  JourneyOption? _choicesOf;

  void _choose(int index, Ride ride) => setState(() {
        // The following rides go back to the first departure they can catch
        _choices = {
          for (final entry in _choices.entries)
            if (entry.key < index) entry.key: entry.value,
          index: ride,
        };
      });

  @override
  Widget build(BuildContext context) {
    final params = Uri.splitQueryString(widget.query);
    final departure = DateTime.tryParse(params['dep'] ?? '');
    final selected = ref.watch(selectedJourneyProvider);
    // The option in memory when it is the one of the URL
    final inMemory = selected != null && (departure == null || selected.departure.isAtSameMomentAs(departure));
    final shared = inMemory || departure == null ? null : ref.watch(sharedJourneyProvider(widget.query));
    final planned = inMemory ? selected : shared?.value;
    final request = inMemory ? ref.read(selectedJourneyProvider.notifier).request : JourneyRequest.fromQuery(params);
    final theme = Theme.of(context);

    void back() => context.canPop() ? context.pop() : context.go(request == null ? Routes.home : Routes.journey(request));

    if (planned == null) {
      return Column(
        children: [
          Align(alignment: Alignment.centerLeft, child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: back)),
          if (shared != null && shared.isLoading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(context.l10n.journeyNotFound, textAlign: TextAlign.center),
                  if (request != null && request.isComplete)
                    TextButton(
                      onPressed: () => context.go(Routes.journey(request.copyWith(datetime: () => null))),
                      child: Text(context.l10n.searchAgain),
                    ),
                ],
              ),
            ),
        ],
      );
    }

    if (_choicesOf != planned) {
      _choicesOf = planned;
      _choices = const {};
    }
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final retimed = retimeJourney(planned, lookup: watchRides(ref, now), now: now, choices: _choices);
    final journey = retimed.journey;

    return MapOverlayScope(
      overlay: journeyOverlay(context, journey),
      child: ListView(
        controller: PanelScrollScope.of(context),
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 32),
        children: [
          Row(
            children: [
              IconButton(tooltip: context.l10n.back, icon: const Icon(Icons.arrow_back), onPressed: back),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatDuration(journey.duration), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      [
                        '${formatClock(journey.departure)} → ${formatClock(journey.arrival)}',
                        journeyTypeLabel(journey.type),
                        if (journey.fare != null && journey.fare! > 0) formatFare(journey.fare!),
                        if (journey.co2 != null) context.l10n.co2(journey.co2!.round()),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.share,
                icon: const Icon(Icons.share_outlined),
                onPressed: () => shareLink(
                  context,
                  title: context.l10n.journeyShareTitle(
                      journey.sections.firstOrNull?.from?.name ?? '', journey.sections.lastOrNull?.to?.name ?? ''),
                  location: Routes.journeyDetailOf((request ?? const JourneyRequest()).forSharing(planned), planned),
                ),
              ),
              FilledButton.icon(
                // The theme makes filled buttons full width
                style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
                icon: const Icon(Icons.navigation),
                label: Text(context.l10n.go),
                onPressed: () {
                  ref.read(goControllerProvider.notifier).start(journey, request);
                  context.push(Routes.go);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, section) in journey.sections.indexed)
                  _SectionTile(
                    section: section,
                    isFirst: index == 0,
                    ride: retimed.rides[index],
                    onChoose: (ride) => _choose(index, ride),
                  ),
                if (journey.sections.lastOrNull?.to case final end?)
                  _TimelineRow(
                    color: theme.colorScheme.error,
                    time: formatClock(journey.arrival),
                    dot: true,
                    isLast: true,
                    child: Text(end.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section, required this.isFirst, this.ride, required this.onChoose});

  final JourneySection section;

  /// A ride's departures and the one taken
  final RidePlan? ride;
  final ValueChanged<Ride> onChoose;

  /// Only the first section shows where it starts: the others start where the previous one ended
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    switch (section.kind) {
      case SectionKind.transit:
        return _RideTile(section: section, plan: ride, onChoose: onChoose);
      case SectionKind.wait:
        return _TimelineRow(
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
        final distance = section.length == null || section.length == 0 ? '' : ' (${formatDistance(section.length!)})';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (section.from != null && isFirst)
              _TimelineRow(
                color: muted,
                time: formatClock(section.departure),
                dot: true,
                child: Text(section.from!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            _TimelineRow(
              color: muted,
              dotted: true,
              child: section.steps.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('$verb ${formatDuration(section.duration)}$distance', style: TextStyle(color: muted)),
                    )
                  : Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('$verb ${formatDuration(section.duration)}$distance', style: TextStyle(color: muted)),
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

    Widget stationRow(JourneyPoint? point, BikeStation? live, {required bool start}) => _TimelineRow(
          color: velibColor,
          time: formatClock(start ? section.departure : section.arrival),
          dot: true,
          child: InkWell(
            onTap: live == null ? null : () => showBikeStationSheet(context, live),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((start ? context.l10n.bikePickUp : context.l10n.bikeDropOff)(point?.name.replaceFirst('Station Vélib ', '') ?? ''),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
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
        _TimelineRow(
          color: velibColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(context.l10n.bikeRideEstimated(formatDuration(section.duration), distance), style: TextStyle(color: muted)),
          ),
        ),
        stationRow(section.to, leave, start: false),
      ],
    );
  }
}

class _RideTile extends StatelessWidget {
  const _RideTile({required this.section, required this.plan, required this.onChoose});

  final JourneySection section;
  final RidePlan? plan;
  final ValueChanged<Ride> onChoose;

  @override
  Widget build(BuildContext context) {
    final lineId = section.line?.id;
    final hasLine = lineId != null && lineId.isNotEmpty;
    final theme = Theme.of(context);
    final line = section.line;
    final color = parseHexColor(line?.color, theme.colorScheme.primary);
    final intermediate = section.stops.length > 2 ? section.stops.sublist(1, section.stops.length - 1) : const <JourneyStop>[];
    final delay = section.delay ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TimelineRow(
          color: color,
          time: formatClock(section.departure),
          dot: true,
          child: InkWell(
            onTap: section.from?.stopAreaId == null ? null : () => context.push(Routes.stop(section.from!.stopAreaId!)),
            child: Text(section.from?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        _TimelineRow(
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
                      child: Text(context.l10n.direction(section.headsign ?? ''), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (section.realtime == true)
                      _Tag(
                        icon: Icons.rss_feed,
                        color: delay >= 120 ? Colors.orange.shade700 : Colors.green.shade600,
                        text: delay >= 60 ? context.l10n.delayMinutes((delay / 60).round()) : context.l10n.realtime,
                      ),
                    if (section.boardingPositions.isNotEmpty)
                      _Tag(icon: Icons.train, color: theme.colorScheme.primary, text: _boardingLabel(section.boardingPositions)),
                  ],
                ),
                if (hasLine) _RideDisruptions(lineId: lineId),
                // Elevators matter to get on and off: those of both stops
                for (final point in [section.from, section.to])
                  if (point?.stopAreaId case final stopAreaId?) _StopElevators(stopAreaId: stopAreaId, name: point!.name),
                if (plan != null) _Departures(plan: plan!, onChoose: onChoose),
                if (intermediate.isNotEmpty)
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        '${context.l10n.stopsCount(intermediate.length)} · ${formatDuration(section.duration)}',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      children: [
                        for (final stop in intermediate)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(stop.name),
                            trailing: stop.time == null ? null : Text(formatClock(stop.time!)),
                          ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(formatDuration(section.duration), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
        ),
        _TimelineRow(
          color: color,
          time: formatClock(section.arrival),
          dot: true,
          child: InkWell(
            onTap: section.to?.stopAreaId == null ? null : () => context.push(Routes.stop(section.to!.stopAreaId!)),
            child: Text(context.l10n.getOffAt(section.to?.name ?? ''), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  static String _boardingLabel(List<String> positions) {
    String name(String position) => switch (position) {
          'front' => currentL10n.boardFront,
          'middle' => currentL10n.boardMiddle,
          'back' => currentL10n.boardBack,
          _ => position,
        };
    return positions.length >= 3
        ? currentL10n.boardAnywhere
        : currentL10n.boardAt(positions.map(name).join(' ${currentL10n.or} '));
  }
}

/// Elevator outages of a stop of the ride, on one line (a folding card would break the timeline's intrinsic height);
/// tapping it shows the messages
class _StopElevators extends ConsumerWidget {
  const _StopElevators({required this.stopAreaId, required this.name});

  final String stopAreaId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elevators = (ref.watch(stopDisruptionsProvider(stopAreaId)).value ?? const <Disruption>[])
        .where((disruption) => disruption.active && disruption.category == DisruptionCategory.elevator)
        .toList();
    if (elevators.isEmpty) {
      return const SizedBox.shrink();
    }
    final color = Colors.orange.shade800;
    final title = context.l10n.brokenElevatorsAt(elevators.length, name);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final disruption in elevators)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('• ${disruption.message ?? disruption.title ?? ''}'),
                    ),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.close))],
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.elevator_outlined, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
            Icon(Icons.chevron_right, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

/// Active disruptions of the ride's line (information messages left out)
class _RideDisruptions extends ConsumerWidget {
  const _RideDisruptions({required this.lineId});

  final String lineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disruptions = (ref.watch(lineDisruptionsProvider(lineId)).value ?? const <Disruption>[])
        .where((disruption) => disruption.active && disruption.severity != DisruptionSeverity.info)
        .toList();
    if (disruptions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final disruption in disruptions.take(3)) DisruptionLine(disruption: disruption)],
      ),
    );
  }
}

/// Departures of the ride's line at the boarding stop that stop at the alighting one, from when the traveller can
/// be there: the one taken is highlighted, choosing another one moves the journey to it.
class _Departures extends ConsumerWidget {
  const _Departures({required this.plan, required this.onChoose});

  final RidePlan plan;
  final ValueChanged<Ride> onChoose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final rides = ref.watch(rideOptionsProvider(plan.key)).value ?? const <Ride>[];
    if (rides.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: RideDepartureList(
        rides: rides,
        now: now,
        selected: plan.ride,
        earliest: plan.earliest,
        onSelect: onChoose,
        onAllDepartures: () => context.push(Routes.stop(plan.key.from)),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Row of the timeline: time on the left, a vertical line (solid or dotted) with an optional stop dot, content
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.color, required this.child, this.time, this.dot = false, this.dotted = false, this.isLast = false});

  final Color color;
  final Widget child;
  final String? time;
  final bool dot;
  final bool dotted;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: time == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(time!, style: theme.textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
          ),
          SizedBox(
            width: 24,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (!(dot && isLast))
                  Positioned.fill(
                    top: dot ? 8 : 0,
                    child: Center(
                      child: dotted
                          ? _DottedLine(color: color)
                          : Container(width: 5, color: color),
                    ),
                  ),
                if (dot)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 4), child: child)),
        ],
      ),
    );
  }
}

/// Vertical dotted line (walking); painted, since the timeline rows are sized with IntrinsicHeight
class _DottedLine extends StatelessWidget {
  const _DottedLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(4, double.infinity), painter: _DotsPainter(color));
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = 2.0; y < size.height; y += 8) {
      canvas.drawCircle(Offset(size.width / 2, y), 2, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => oldDelegate.color != color;
}
