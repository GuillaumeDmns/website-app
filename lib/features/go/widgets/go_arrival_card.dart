import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/utils/time_format.dart';
import '../../../l10n/l10n.dart';
import '../../daily_trips/daily_trip_widgets.dart';
import '../../journey/journey_request.dart';
import '../go_controller.dart';
import '../go_state.dart';
import '../go_tracker.dart';
import 'go_card_parts.dart';

/// The arrival: the summary, then the way back, saving the trip, finishing (it closes itself after a while)
class GoArrivalCard extends ConsumerWidget {
  const GoArrivalCard({super.key, required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final progress = state.progress;
    final arrived = progress.phase == GoPhase.arrived;
    final destination = state.journey.sections.lastOrNull?.to?.name ?? '';
    final eta = state.tracker.eta(progress, state.currentVehicle);

    return Column(
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
          GoSmallAction(
            label: context.l10n.goImArrived,
            onPressed: () => ref.read(goControllerProvider.notifier).jumpTo(state.tracker.steps.length),
          ),
      ],
    );
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
