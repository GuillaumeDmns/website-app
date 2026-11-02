import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/location/location_providers.dart';
import '../../../core/utils/colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/size_reporter.dart';
import '../../../l10n/l10n.dart';
import '../../journey/journey_labels.dart';
import '../../journey/journey_providers.dart';
import '../../journey/journey_retime.dart';
import '../../journey/widgets/ride_departures.dart';
import '../../traffic/disruption_widgets.dart';
import '../go_cards.dart';
import '../go_controller.dart';
import '../go_glance.dart';
import '../go_guidance.dart';
import '../go_state.dart';
import '../go_tracker.dart';
import 'go_card_parts.dart';

/// A ride's departures, like Citymapper's card before boarding: the departure followed in the header (its time and
/// punctuality, mission and destination, the minutes left and the platform), the transfer walked to it, the line's
/// departures to choose another one, where to board along the train. Waiting for it is this card: the moment a vehicle
/// leaves, is missed or cancelled, or changes platform, its header says so.
class GoDeparturesCard extends ConsumerWidget {
  const GoDeparturesCard({super.key, required this.state, required this.card, required this.live, required this.done, this.onHeadSize});

  final GoState state;
  final GoCard card;
  final bool live;
  final bool done;
  final ValueChanged<Size>? onHeadSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.colors;
    // The departures' clock: the header and the list count the same minutes
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final tracker = state.tracker;
    final progress = state.progress;
    final step = tracker.steps[card.step];
    final section = step.section;
    final line = section.line;
    // The line's departures from when the traveller gets to the stop (at it already, waiting), the one followed among
    // them; its real time, else GO's for the next ride (the planned vehicle followed by the controller)
    final earliest = card.step == progress.step ? now : earliestBoarding(state.journey, step.sectionIndex, now).add(progress.shift);
    final key = rideKey(section, earliest, now);
    final rides = key == null
        ? const <Ride>[]
        : (ref.watch(rideOptionsProvider(key)).value ?? const <Ride>[])
              .where((ride) => ride.departure.time.isAfter(now.subtract(const Duration(minutes: 1))))
              .toList();
    final planned = tracker.plannedDeparture(step, progress);
    final selected = rides.isEmpty ? null : plannedRide(rides, planned);
    final vehicle = state.vehicleStep == card.step ? state.vehicle : selected?.departure;
    final departure = tracker.expectedDeparture(step, progress, vehicle);
    final waiting = progress.phase == GoPhase.waiting && progress.step == card.step;
    final minutes = math.min(minutesLeft(departure.difference(now)), 999);

    // When it leaves: its time, then on time, late or cancelled when the real time says
    final late = vehicle == null ? 0 : vehicle.time.difference(vehicle.aimedTime ?? vehicle.time).roundedMinutes;
    final (status, statusColor) = switch (vehicle) {
      null => (context.l10n.goScheduled, colors.muted),
      final vehicle when vehicle.cancelled => (context.l10n.goCancelledStatus, colors.cancelled),
      _ when late >= 1 => (context.l10n.goMinutesLate(late), colors.warning),
      _ => (context.l10n.goOnTime, colors.live),
    };
    final mission = vehicle?.mission;
    final issue = live && waiting && progress.issue != GoIssue.offRoute ? progress.issue : null;
    final glance = live && waiting ? goGlance(state, now) : null;
    final lineLabel = line?.label ?? '';
    final header = issue != null
        // Missed or cancelled, the next one not kept yet: choose
        ? GoCardHeader(
            leading: line != null ? LineBadge(line, size: 30) : const Icon(Icons.directions_transit, size: 30, color: Colors.white),
            title: issue == GoIssue.cancelled ? context.l10n.goCancelledChoose(lineLabel) : context.l10n.goMissedChoose(lineLabel),
            live: true,
            tone: GoTone.warn,
          )
        : glance != null && glance.tone != GoTone.ok
        ? GoCardHeader.alert(glance, live: true)
        : GoCardHeader(
            leading: line != null ? LineBadge(line, size: 30) : const Icon(Icons.directions_transit, size: 30),
            title: formatClock(departure),
            titleSpan: TextSpan(children: [
              TextSpan(text: '${formatClock(departure)} '),
              TextSpan(text: status, style: TextStyle(color: done ? null : statusColor)),
            ]),
            subtitle: [?mission, mission != null ? section.headsign ?? '' : context.l10n.direction(section.headsign ?? '')]
                .where((part) => part.isNotEmpty)
                .join(' '),
            figure: done ? null : (minutes <= 0 ? context.l10n.now : '$minutes'),
            unit: done || minutes <= 0 ? null : context.l10n.minutesUnit,
            note: done ? null : platformLabel(line, vehicle?.platform),
            live: live,
            done: done,
          );

    final transfer = card.transfer == null ? null : tracker.steps[card.transfer!];
    final walkingTransfer = transfer != null && progress.phase == GoPhase.moving && progress.step == card.transfer;
    final positions = section.boardingPositions;
    final head = [
      header,
      if (!live && !done) GoHereButton(card: card),
      if (transfer != null && !done && (walkingTransfer || progress.step < card.step))
        GoContextLine(
          icon: Icons.transfer_within_a_station,
          text: context.l10n.goTransferWalk(formatDuration(walkingTransfer
              ? (metersToGo(state) / movePace(state, transfer)).round()
              : transfer.section.duration)),
        ),
      if (issue != null) _IssueActions(state: state, issue: issue),
      if (live && state.retained != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(context.l10n.goRecalculateJourney),
            onPressed: state.recalculating ? null : ref.read(goControllerProvider.notifier).recalculate,
          ),
        ),
    ];
    return GoCardFrame(
      children: [
        SizeReporter(
          onSize: (size) => onHeadSize?.call(size),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, part) in head.indexed) ...[if (index > 0) const SizedBox(height: 12), part],
              if (!done) ...[
                const SizedBox(height: 12),
                _Departures(step: step, index: card.step, rides: rides, selected: selected, planned: planned, earliest: earliest, departures: key),
              ],
              if (!done && positions.isNotEmpty && positions.length < 3) ...[
                const SizedBox(height: 12),
                TrainPositions(positions: positions, color: parseHexColor(line?.color, theme.colorScheme.primary)),
              ],
            ],
          ),
        ),
        if (!done) RideDisruptions(lineId: line?.id, max: 1, top: 0),
        if (live && tracker.followsSchedule(progress, now)) const GoNoGpsLine(),
      ],
    );
  }
}

/// Where to board along the train, like Citymapper's "Où monter ?": its cars from the front, the ones to board
/// highlighted
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
          Text(boardingLabel(positions), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Departures of the ride's line stopping where it gets off, from when the traveller gets to its stop, with their
/// times at both stops; the one followed is highlighted, and the next one told in case it is missed. Choosing another
/// one moves the journey to it.
class _Departures extends ConsumerWidget {
  const _Departures({
    required this.step,
    required this.index,
    required this.rides,
    required this.selected,
    required this.planned,
    required this.earliest,
    required this.departures,
  });

  final GoStep step;
  final int index;
  final List<Ride> rides;
  final Ride? selected;
  final DateTime planned;
  final DateTime earliest;

  /// Where and from when they are asked
  final RideKey? departures;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    if (rides.isEmpty) {
      return Text(context.l10n.goPlannedDeparture(formatClock(planned)), style: Theme.of(context).textTheme.titleMedium);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RideDepartureList(
          rides: rides,
          now: now,
          mode: step.section.line?.mode,
          selected: selected,
          earliest: earliest,
          onSelect: (ride) => ref.read(goControllerProvider.notifier).choose(index, ride),
          onAllDepartures: () => context.push(Routes.stop(departures!.from)),
        ),
        IfMissedLine(rides: rides, taken: selected),
      ],
    );
  }
}

/// The vehicle waited for was missed or is cancelled, before GO keeps the next one on its own: that one in one tap,
/// or the journey recalculated
class _IssueActions extends ConsumerWidget {
  const _IssueActions({required this.state, required this.issue});

  final GoState state;
  final GoIssue issue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(goControllerProvider.notifier);
    final progress = state.progress;
    final step = state.tracker.stepOf(progress);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final key = step == null || !step.isRide ? null : rideKey(step.section, now, now);
    final planned = step == null ? now : state.tracker.expectedDeparture(step, progress, state.currentVehicle);
    final next = key == null ? null : replacementRide(ref.watch(rideOptionsProvider(key)).value ?? const <Ride>[], issue, planned, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (next != null)
          Text(
            [
              context.l10n.goNextDeparture(formatClock(next.departure.time), math.max(0, next.departure.time.difference(now).inMinutes)),
              if (next.arrivalAt case final arrival?) context.l10n.arrivalAt(formatClock(arrival)),
            ].join(' · '),
            style: theme.textTheme.titleSmall,
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (next != null) ...[
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  controller.dismissIssue();
                  controller.choose(progress.step, next);
                },
                child: Text(context.l10n.goTakeThisOne),
              ),
              const SizedBox(width: 8),
            ],
            state.recalculating
                ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton(onPressed: controller.recalculate, child: Text(context.l10n.recalculate)),
          ],
        ),
      ],
    );
  }
}
