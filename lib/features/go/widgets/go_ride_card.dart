import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/location/location_providers.dart';
import '../../../core/utils/colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/ui.dart';
import '../../../l10n/l10n.dart';
import '../../journey/journey_labels.dart';
import '../../journey/journey_providers.dart';
import '../../journey/journey_retime.dart';
import '../../journey/widgets/ride_departures.dart';
import '../../traffic/disruption_widgets.dart';
import '../go_controller.dart';
import '../go_state.dart';
import '../go_tracker.dart';
import 'go_card_parts.dart';

/// A ride: waiting for it (countdown, where to board, departures, the next one if missed), on board
/// (the stops left with their times, where to get off), or to come (its departures)
class GoRideCard extends ConsumerWidget {
  const GoRideCard({super.key, required this.state, required this.index, this.compact = false});

  final GoState state;
  final int index;

  /// The step in progress under the banner and [GoNowCard], which tell what to do, the countdown and where to board:
  /// only the departures or the stops left, and what follows
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracker = state.tracker;
    final progress = state.progress;
    final step = tracker.steps[index];
    final section = step.section;
    final isLive = index == progress.step && progress.phase != GoPhase.arrived;
    final isDone = index < progress.step || progress.phase == GoPhase.arrived;
    final onBoard = isLive && progress.phase == GoPhase.onBoard;
    final lineLabel = section.line?.label ?? '';
    final stopCount = math.max(0, section.stops.length - 1);

    final String title;
    final String detail;
    var urgent = false;
    if (onBoard) {
      final left = tracker.stopsLeft(progress);
      urgent = left <= 1;
      title = left <= 1 ? context.l10n.goGetOffNext : context.l10n.goGetOffIn(left);
      detail = context.l10n.goAtStop(section.to?.name ?? '');
    } else {
      title = '$lineLabel → ${section.headsign ?? ''}';
      detail = [
        context.l10n.goFromTo(section.from?.name ?? '', section.to?.name ?? ''),
        if (stopCount > 0) context.l10n.stopsCount(stopCount),
      ].join(' · ');
    }
    final positions = section.boardingPositions;
    final now = DateTime.now();
    final waiting = isLive && progress.phase == GoPhase.waiting;
    final countdown = waiting ? tracker.expectedDeparture(step, progress, state.currentVehicle).difference(now) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact)
        GoCardTitle(
          leading: section.line != null ? LineBadge(section.line!, size: 36) : const Icon(Icons.directions_transit, size: 34),
          title: title,
          detail: detail,
          trailing: countdown == null
              ? null
              : _Countdown(
                  until: countdown,
                  color: countdown <= const Duration(minutes: 1) ? Theme.of(context).colorScheme.error : AppTheme.brand,
                ),
          done: isDone,
          urgent: urgent,
        ),
        if (waiting && !compact) GoPills(state: state, now: now),
        if (onBoard) ...[
          if (!compact) const SizedBox(height: 12),
          _StopsLeft(state: state, step: step),
        ] else if (!isDone) ...[
          if (positions.isNotEmpty && positions.length < 3 && !compact) ...[
            const SizedBox(height: 12),
            TrainPositions(positions: positions, color: parseHexColor(section.line?.color, Theme.of(context).colorScheme.primary)),
          ],
          if (!compact) const SizedBox(height: 14),
          _RideDepartures(state: state, step: step, index: index),
        ],
        if (!isDone) RideDisruptions(lineId: section.line?.id, max: 1, top: 10),
        if (!isDone && index + 1 < tracker.steps.length) GoNextStep(state: state, index: index + 1),
        const SizedBox(height: 8),
        // Manual corrections, kept discreet
        if (compact)
          const SizedBox.shrink()
        else if (isLive && progress.phase == GoPhase.waiting)
          GoSmallAction(label: context.l10n.goImOnBoard, onPressed: () => ref.read(goControllerProvider.notifier).next())
        else if (!isLive && !isDone)
          GoSmallAction(label: context.l10n.goImAtThisStep, onPressed: () => ref.read(goControllerProvider.notifier).jumpTo(index)),
      ],
    );
  }
}

/// Where to board along the train: its cars from the front, the ones to board highlighted
class TrainPositions extends StatelessWidget {
  const TrainPositions({super.key, required this.positions, required this.color});

  /// `front`, `middle`, `back`
  final List<String> positions;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.colors.subtle;
    bool boarded(int car) => switch (car) {
          0 || 1 => positions.contains('front'),
          2 => positions.contains('middle'),
          _ => positions.contains('back'),
        };
    return Semantics(
      label: boardingLabel(positions),
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(Icons.arrow_back, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          for (var car = 0; car < 5; car++)
            Expanded(
              child: Container(
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: boarded(car) ? color : muted,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(car == 0 ? 9 : 3),
                    right: const Radius.circular(3),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 10),
          Text(boardingLabel(positions),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// On board: the stops left with their times, a dot on the next one, where to get off marked
class _StopsLeft extends StatelessWidget {
  const _StopsLeft({required this.state, required this.step});

  final GoState state;
  final GoStep step;

  /// More stops left than this: the ones in between folded
  static const _maxShown = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = state.progress;
    final stops = step.section.stops;
    final color = parseHexColor(step.section.line?.color, theme.colorScheme.primary);
    final first = math.min(progress.stopIndex + 1, stops.length - 1);
    final indexes = [for (var k = first; k < stops.length; k++) k];
    final folded = indexes.length > _maxShown ? indexes.length - (_maxShown - 1) : 0;
    final shown = folded == 0 ? indexes : [...indexes.take(_maxShown - 2), -1, indexes.last];

    return Column(
      children: [
        for (final (row, k) in shown.indexed)
          if (k < 0)
            _StopRow(color: color, name: context.l10n.stopsCount(folded), time: null, first: false, last: false, folded: true)
          else
            _StopRow(
              color: color,
              name: stops[k].name,
              // Where to get off: the ride's arrival (a stop's time is its departure)
              time: (k == stops.length - 1 ? step.section.arrival : step.stopTime(k)).add(progress.shift),
              first: row == 0,
              last: k == stops.length - 1,
            ),
      ],
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.color, required this.name, required this.time, required this.first, required this.last, this.folded = false});

  final Color color;
  final String name;
  final DateTime? time;

  /// The next stop
  final bool first;

  /// Where to get off
  final bool last;
  final bool folded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emphasis = first || last;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(time == null ? '' : formatClock(time!),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: emphasis ? FontWeight.w600 : null)),
            ),
          ),
          SizedBox(
            width: 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(children: [
                  Expanded(child: Container(width: 5, color: color)),
                  Expanded(child: Container(width: 5, color: last ? Colors.transparent : color)),
                ]),
                if (!folded)
                  Container(
                    width: emphasis ? 16 : 10,
                    height: emphasis ? 16 : 10,
                    decoration: BoxDecoration(
                      color: last ? color : context.colors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: folded
                          ? theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)
                          : (emphasis ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium),
                    ),
                  ),
                  if (first && !last) ...[
                    const SizedBox(width: 8),
                    PillTag(text: context.l10n.goNextStopLabel, color: theme.colorScheme.primary),
                  ],
                  if (last) ...[
                    const SizedBox(width: 8),
                    PillTag(text: context.l10n.goGetOffHere, color: theme.colorScheme.error),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Departures of the ride's line stopping where it gets off, from when the traveller gets to its stop, with their
/// times at both stops; the one followed is highlighted, and the next one told in case it is missed. Choosing another
/// one moves the journey to it.
class _RideDepartures extends ConsumerWidget {
  const _RideDepartures({required this.state, required this.step, required this.index});

  final GoState state;
  final GoStep step;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = state.progress;
    final planned = state.tracker.plannedDeparture(step, progress);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    // At the stop already for the step in progress; else after the steps before it
    final earliest = index == progress.step ? now : earliestBoarding(state.journey, step.sectionIndex, now).add(progress.shift);
    final key = rideKey(step.section, earliest, now);

    final rides = key == null
        ? const <Ride>[]
        : (ref.watch(rideOptionsProvider(key)).value ?? const <Ride>[])
              .where((ride) => ride.departure.time.isAfter(now.subtract(const Duration(minutes: 1))))
              .toList();

    if (rides.isEmpty) {
      return Text(context.l10n.goPlannedDeparture(formatClock(planned)), style: theme.textTheme.titleMedium);
    }
    final selected = plannedRide(rides, planned);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RideDepartureList(
          rides: rides,
          now: now,
          selected: selected,
          earliest: earliest,
          onSelect: (ride) => ref.read(goControllerProvider.notifier).choose(index, ride),
          onAllDepartures: () => context.push(Routes.stop(key!.from)),
        ),
        IfMissedLine(rides: rides, taken: selected),
      ],
    );
  }
}

/// Minutes until the vehicle leaves, large, with a ring emptying over the last ten minutes
class _Countdown extends StatelessWidget {
  const _Countdown({required this.until, required this.color});

  final Duration until;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Like the departure lists: whole minutes left, "now" within 30 s
    final minutes = math.min(minutesLeft(until), 999);
    final theme = Theme.of(context);
    return SizedBox.square(
      dimension: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: (until.inSeconds / 600).clamp(0.0, 1.0),
              strokeWidth: 4,
              color: color,
              backgroundColor: color.withValues(alpha: 0.2),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                minutes <= 0 ? context.l10n.now : '$minutes',
                style: (minutes <= 0 ? theme.textTheme.labelLarge : theme.textTheme.titleLarge)
                    ?.copyWith(color: color, fontWeight: FontWeight.w700, height: 1),
              ),
              if (minutes > 0) Text(context.l10n.minutesUnit, style: theme.textTheme.labelSmall?.copyWith(color: color, height: 1)),
            ],
          ),
        ],
      ),
    );
  }
}
