import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/size_reporter.dart';
import '../../../l10n/l10n.dart';
import '../../daily_trips/daily_trip_widgets.dart';
import '../../journey/journey_request.dart';
import '../go_cards.dart';
import '../go_controller.dart';
import '../go_state.dart';
import '../go_trace.dart';
import '../go_tracker.dart';
import '../go_vehicle_match.dart';
import 'go_card_parts.dart';

/// The arrival: the summary, then the way back, saving the trip, finishing (it closes itself after a while)
class GoArrivalCard extends ConsumerWidget {
  const GoArrivalCard({super.key, required this.state, this.onHeadSize});

  final GoState state;
  final ValueChanged<Size>? onHeadSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final progress = state.progress;
    final arrived = progress.phase == GoPhase.arrived;
    final destination = state.journey.sections.lastOrNull?.to?.name ?? '';
    final eta = state.tracker.eta(progress, state.currentVehicle);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 12),
              child: Icon(Icons.flag, size: 34, color: theme.colorScheme.error),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    arrived ? context.l10n.goArrived : context.l10n.goArrivalTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text('$destination · ${formatClock(eta)}', style: theme.textTheme.bodyLarge?.copyWith(color: muted)),
                  if (arrived) ...[
                    const SizedBox(height: 12),
                    _Summary(state: state, arrivedAt: eta),
                  ],
                ],
              ),
            ),
            if (arrived) SaveDailyTripButton(journey: state.journey, request: state.request),
          ],
        ),
        if (arrived && ref.watch(goTraceProvider) != null) _TakenQuestions(state: state),
        const SizedBox(height: 16),
        if (arrived) ...[
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () {
              ref.read(goControllerProvider.notifier).stop();
              context.go(Routes.home);
            },
            child: Text(context.l10n.finish),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            icon: const Icon(Icons.u_turn_left),
            label: Text(context.l10n.goWayBack),
            onPressed: () {
              final back = _wayBack(state);
              ref.read(goControllerProvider.notifier).stop();
              context.go(Routes.home);
              context.push(Routes.journey(back));
            },
          ),
        ] else
          GoHereButton(card: GoCard(GoCardKind.arrival, state.tracker.steps.length), label: context.l10n.goImArrived),
      ],
    );
    return GoCardFrame(children: [SizeReporter(onSize: (size) => onHeadSize?.call(size), child: content)]);
  }

  /// From here (the destination) to where the journey started, leaving now
  static JourneyRequest _wayBack(GoState state) {
    final fixed = state.request.forSharing(state.journey);
    return fixed.copyWith(
      from: const JourneyPlace.currentLocation(),
      to: fixed.from,
      datetime: () => null,
      arriveBy: false,
    );
  }
}

/// Arrival summary: real arrival compared with the plan, time taken
class _Summary extends StatelessWidget {
  const _Summary({required this.state, required this.arrivedAt});

  final GoState state;
  final DateTime arrivedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final late = arrivedAt.difference(state.plannedArrival).roundedMinutes;
    final (label, color) = switch (late) {
      0 => (context.l10n.goOnTime, context.colors.live),
      > 0 => (context.l10n.goMinutesLate(late), late >= 5 ? theme.colorScheme.error : context.colors.warning),
      _ => (context.l10n.goMinutesEarly(-late), context.colors.live),
    };
    final rides = state.journey.rides.length;
    Widget row(IconData icon, String text, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color ?? theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: color == null ? null : FontWeight.w600))),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(Icons.flag_outlined, context.l10n.goArrivedVsPlanned(formatClock(arrivedAt), formatClock(state.plannedArrival))),
        row(Icons.schedule, label, color: color),
        row(Icons.timer_outlined,
            context.l10n.goTripDuration(formatDuration(arrivedAt.difference(state.startedAt).inSeconds))),
        if (rides > 0) row(Icons.directions_transit, context.l10n.goRides(rides)),
      ],
    );
  }
}

/// Development and beta builds: for each ride boarded, which departure the user really took, among those seen at its
/// stop about when they left ([GoController.takenOptions]); one tap writes it in the trace ([GoTrace.taken]), the truth
/// the replays of the traces check GO against. Never asked during the journey, nor in the published app.
class _TakenQuestions extends ConsumerStatefulWidget {
  const _TakenQuestions({required this.state});

  final GoState state;

  @override
  ConsumerState<_TakenQuestions> createState() => _TakenQuestionsState();
}

class _TakenQuestionsState extends ConsumerState<_TakenQuestions> {
  /// The departure answered per ride
  final _answers = <int, Departure>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ref.read(goControllerProvider.notifier);
    final steps = widget.state.tracker.steps;
    final questions = <Widget>[];
    for (final (index, step) in steps.indexed) {
      final options = step.isRide ? controller.takenOptions(index) : const <Ride>[];
      if (options.length < 2) {
        continue;
      }
      final section = step.section;
      final mode = section.line?.mode;
      questions.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.goWhichTrain(
                mode?.isRail == true ? context.l10n.goTrainWord : context.l10n.goVehicleWord,
                section.line?.name ?? '',
                section.from?.name ?? '',
              ),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final ride in options)
                  ChoiceChip(
                    label: Text(_label(ride.departure)),
                    selected: _answers[index] != null && sameVehicleDeparture(_answers[index]!, ride.departure),
                    onSelected: (_) => _answer(index, ride.departure),
                  ),
              ],
            ),
          ],
        ),
      ));
    }
    if (questions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...questions,
        const SizedBox(height: 4),
        Text(context.l10n.goWhichTrainHint, style: theme.textTheme.labelSmall?.copyWith(color: context.colors.muted)),
      ],
    );
  }

  /// Its time, its mission (else its destination), and its scheduled time when minutes off it (a late train)
  static String _label(Departure departure) {
    final aimed = departure.aimedTime;
    final late = aimed != null && departure.time.difference(aimed).abs() >= const Duration(minutes: 2);
    return [
      formatClock(departure.time),
      ?departure.mission,
      if (late) '(${formatClock(aimed)})',
    ].join(' · ');
  }

  Future<void> _answer(int step, Departure departure) async {
    final trace = ref.read(goTraceProvider);
    final session = trace?.sessionId;
    if (trace == null || session == null) {
      return;
    }
    setState(() => _answers[step] = departure);
    await trace.taken(session, step, departure, ref.read(goClockProvider)());
  }
}
