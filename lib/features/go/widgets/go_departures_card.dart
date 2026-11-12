import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/location/location_providers.dart';
import '../../../core/utils/colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/departure_time.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/size_reporter.dart';
import '../../../core/widgets/skeleton.dart';
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
    final options = key == null ? null : ref.watch(rideOptionsProvider(key));
    final rides = currentRides(options)
        .where((ride) => ride.departure.time.isAfter(now.subtract(const Duration(minutes: 1))))
        .toList();
    final planned = tracker.plannedDeparture(step, progress);
    final selected = rides.isEmpty ? null : plannedRide(rides, planned, arrival: section.arrival.add(progress.shift));
    final vehicle = state.vehicleStep == card.step ? state.vehicle : selected?.departure;
    final departure = tracker.expectedDeparture(step, progress, vehicle);
    final waiting = progress.phase == GoPhase.waiting && progress.step == card.step;
    final minutes = math.min(minutesLeft(departure.difference(now)), 999);

    // When it leaves: its time on time or from the schedule; moved by the real time, the planned time struck through and
    // the new one beside it, in the delay's color (blue early); cancelled, the planned time struck through
    final moved = vehicle == null || vehicle.cancelled ? 0 : RetimedClock.moved(departure, vehicle.aimedTime);
    final struck = TextStyle(
      color: colors.muted,
      fontWeight: FontWeight.w400,
      decoration: TextDecoration.lineThrough,
      decorationColor: colors.muted,
    );
    TextStyle colored(Color? color) => TextStyle(color: done ? null : color);
    final when = switch (vehicle) {
      null => [TextSpan(text: '${formatClock(departure)} '), TextSpan(text: context.l10n.goScheduled, style: colored(colors.muted))],
      final vehicle when vehicle.cancelled => [
          TextSpan(text: formatClock(vehicle.aimedTime ?? departure), style: struck),
          TextSpan(text: ' ${context.l10n.goCancelledStatus}', style: colored(colors.cancelled)),
        ],
      final vehicle when moved != 0 => [
          TextSpan(text: formatClock(vehicle.aimedTime!), style: struck),
          TextSpan(text: ' ${formatClock(departure)}', style: colored(RetimedClock.colorOf(context, moved))),
        ],
      _ => [TextSpan(text: '${formatClock(departure)} '), TextSpan(text: context.l10n.goOnTime, style: colored(colors.live))],
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
            titleSpan: TextSpan(children: when),
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
                _Departures(
                  step: step,
                  index: card.step,
                  rides: rides,
                  loading: options?.isLoading ?? false,
                  selected: selected,
                  planned: planned,
                  earliest: earliest,
                  departures: key,
                ),
              ],
              if (!done && positions.isNotEmpty && positions.length < 3) ...[
                const SizedBox(height: 12),
                TrainPositions(
                  positions: positions,
                  color: parseHexColor(line?.color, theme.colorScheme.primary),
                  headRight: TrainPositions.headRightFor(line),
                ),
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

/// Where to board along the train, like Citymapper's "Où monter ?": a small train as seen from the platform, facing the
/// track, its front where it will stop ([headRight]), the cars to board in the line's color with a mark under them
class TrainPositions extends StatelessWidget {
  const TrainPositions({super.key, required this.positions, required this.color, required this.headRight});

  /// `front`, `middle`, `back`
  final List<String> positions;
  final Color color;

  /// Its front on the traveller's right, the platform being on the train's right; else on the left
  final bool headRight;

  /// Cars drawn: two for each third of the train
  static const cars = 6;

  /// Tram-trains running on railway lines, on the left: T11, T13
  static const _onTheLeft = {'C01999', 'C02344'};

  /// Whether the front of the [line]'s trains stops on the traveller's right, as their usual station is laid out: the
  /// metro and the tram run on the right with a platform on each side, on their right; trains run on the left (RER A
  /// and B too, on their RATP sections as well: the GTFS tracks of both directions say so). An island platform between
  /// the tracks turns it round, which the data doesn't tell for trains (one point per station for both directions).
  static bool headRightFor(LineSummary? line) => switch (line?.mode) {
        TransportMode.metro || TransportMode.tram => !_onTheLeft.contains(line!.id),
        _ => false,
      };

  /// Whether each car, from the front, is one to board
  static List<bool> boardedCars(List<String> positions) => [
        for (var car = 0; car < cars; car++)
          positions.contains(switch (car * 3 ~/ cars) {
            0 => 'front',
            1 => 'middle',
            _ => 'back',
          }),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final label = boardingLabel(positions);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(context.l10n.goWhereToBoard, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                // The question asked: `À l'avant`, `Au milieu ou à l'arrière`
                child: Text(
                  switch (boardingPositionNames(positions)) {
                    '' => label,
                    final names => '${names[0].toUpperCase()}${names.substring(1)}',
                  },
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CustomPaint(
            size: const Size.fromHeight(38),
            painter: _TrainPainter(
              boarded: boardedCars(positions),
              color: color,
              idle: colors.subtle,
              windows: colors.card,
              headRight: headRight,
            ),
          ),
          const SizedBox(height: 2),
          // Under its front, the way it goes
          Row(
            mainAxisAlignment: headRight ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!headRight) ...[Icon(Icons.arrow_back, size: 14, color: colors.muted), const SizedBox(width: 4)],
              Text(context.l10n.goDirectionOfTravel, style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
              if (headRight) ...[const SizedBox(width: 4), Icon(Icons.arrow_forward, size: 14, color: colors.muted)],
            ],
          ),
        ],
      ),
    );
  }
}

/// [TrainPositions]' train: its cars side by side, the first one with a sloping nose, windows along them, the cars to
/// board filled with the line's color and a mark pointing up at them
class _TrainPainter extends CustomPainter {
  const _TrainPainter({required this.boarded, required this.color, required this.idle, required this.windows, required this.headRight});

  final List<bool> boarded;
  final Color color;
  final Color idle;
  final Color windows;
  final bool headRight;

  static const _gap = 3.0;
  static const _mark = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn from its front on the left, mirrored for a front on the right
    if (headRight) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final height = size.height - _mark - 3;
    final width = (size.width - _gap * (boarded.length - 1)) / boarded.length;
    for (final (car, board) in boarded.indexed) {
      final left = car * (width + _gap);
      final body = Rect.fromLTWH(left, 0, width, height);
      final first = car == 0;
      final last = car == boarded.length - 1;
      final nose = Radius.elliptical(math.min(width * 0.55, height * 1.3), height * 0.9);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          body,
          topLeft: first ? nose : const Radius.circular(4),
          bottomLeft: first ? const Radius.circular(6) : const Radius.circular(4),
          topRight: Radius.circular(last ? 8 : 4),
          bottomRight: Radius.circular(last ? 8 : 4),
        ),
        Paint()..color = board ? color : idle,
      );
      // Windows along the upper half; the first car's start after its nose, a windscreen
      final window = Paint()..color = board ? Colors.white.withValues(alpha: 0.85) : windows;
      final top = height * 0.2;
      final windowHeight = height * 0.32;
      final start = left + (first ? width * 0.42 : 5);
      final end = left + width - 5;
      final count = first ? 1 : math.max(2, ((end - start) / 16).floor());
      final windowWidth = (end - start - (count - 1) * 4) / count;
      for (var index = 0; index < count; index++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(start + index * (windowWidth + 4), top, windowWidth, windowHeight),
            const Radius.circular(2.5),
          ),
          window,
        );
      }
    }
    // The mark under the cars to board, pointing up at them
    final firstBoarded = boarded.indexOf(true);
    if (firstBoarded < 0) {
      return;
    }
    final lastBoarded = boarded.lastIndexOf(true);
    final middle = (firstBoarded * (width + _gap) + (lastBoarded + 1) * (width + _gap) - _gap) / 2;
    final tip = height + 3;
    canvas.drawPath(
      Path()
        ..moveTo(middle, tip)
        ..lineTo(middle + _mark, tip + _mark)
        ..lineTo(middle - _mark, tip + _mark)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrainPainter oldDelegate) =>
      !listEquals(oldDelegate.boarded, boarded) ||
      oldDelegate.color != color ||
      oldDelegate.idle != idle ||
      oldDelegate.windows != windows ||
      oldDelegate.headRight != headRight;
}

/// Departures of the ride's line stopping where it gets off, from when the traveller gets to its stop, with their
/// times at both stops; the one followed is highlighted, and the next one told in case it is missed. Choosing another
/// one moves the journey to it.
class _Departures extends ConsumerWidget {
  const _Departures({
    required this.step,
    required this.index,
    required this.rides,
    required this.loading,
    required this.selected,
    required this.planned,
    required this.earliest,
    required this.departures,
  });

  final GoStep step;
  final int index;
  final List<Ride> rides;

  /// Being asked: [rides] are to come
  final bool loading;
  final Ride? selected;
  final DateTime planned;
  final DateTime earliest;

  /// Where and from when they are asked
  final RideKey? departures;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    if (rides.isEmpty) {
      // Their place kept while they are asked
      return loading
          ? const SkeletonCards(height: 62)
          : Text(context.l10n.goPlannedDeparture(formatClock(planned)), style: Theme.of(context).textTheme.titleMedium);
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
