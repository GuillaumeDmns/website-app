import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../l10n/l10n.dart';
import '../../journey/journey_labels.dart';
import '../../journey/journey_providers.dart';
import '../../journey/journey_retime.dart';
import '../go_guidance.dart';
import '../go_state.dart';
import '../go_tracker.dart';

/// Title row of a card: the line badge or the move's icon, a few words in large, one detail line
class GoCardTitle extends StatelessWidget {
  const GoCardTitle({super.key, 
    required this.leading,
    required this.title,
    required this.detail,
    this.trailing,
    this.done = false,
    this.urgent = false,
  });

  final Widget leading;
  final String title;
  final String? detail;
  final Widget? trailing;
  final bool done;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2, right: 12), child: leading),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: urgent
                      ? theme.colorScheme.error
                      : done
                          ? muted
                          : null,
                ),
              ),
              if (detail case final detail? when detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(detail, style: theme.textTheme.bodyLarge?.copyWith(color: muted)),
              ],
            ],
          ),
        ),
        ?trailing,
        if (done) Icon(Icons.check_circle, color: context.colors.live),
      ],
    );
  }
}

/// What comes after this step: the next ride (line, direction, departure, platform) or the walk to the destination
class GoNextStep extends StatelessWidget {
  const GoNextStep({super.key, required this.state, required this.index});

  final GoState state;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracker = state.tracker;
    final step = tracker.steps[index];
    final section = step.section;
    final String text;
    Widget leading;
    if (step.isRide) {
      final vehicle = state.vehicleStep == index ? state.vehicle : null;
      final departure = tracker.expectedDeparture(step, state.progress, vehicle);
      text = [
        context.l10n.direction(section.headsign ?? ''),
        context.l10n.goDepartsAt(formatClock(departure)),
        ?platformLabel(section.line, vehicle?.platform),
      ].join(' · ');
      leading = section.line != null ? LineBadge(section.line!, size: 22) : const Icon(Icons.directions_transit, size: 20);
    } else {
      text = context.l10n.goNextMove(formatDuration(section.duration), section.to?.name ?? '');
      leading = Icon(moveIcon(section.kind), size: 20, color: context.colors.muted);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: context.colors.subtle, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Text(context.l10n.goThen, style: theme.textTheme.labelLarge?.copyWith(color: context.colors.muted)),
            const SizedBox(width: 10),
            leading,
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

/// A manual correction, kept discreet: "Je suis à cette étape", "Je suis à bord", "Je suis arrivé"
class GoSmallAction extends StatelessWidget {
  const GoSmallAction({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
    onPressed: onPressed,
    child: Text(label),
  );
}

/// Under the instruction: the time to spare walking to the ride, and following the schedule without GPS
class GoPills extends StatelessWidget {
  const GoPills({super.key, required this.state, required this.now});

  final GoState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final margin = walkMargin(state, now);
    final noGps = state.progress.phase != GoPhase.arrived && state.tracker.followsSchedule(state.progress, now);
    if (margin == null && !noGps) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 56, top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (margin != null) _MarginPill(state: state, margin: margin, now: now),
          if (noGps) _Pill(icon: Icons.gps_off, text: context.l10n.goNoGps, color: scheme.inverseSurface, textColor: scheme.onInverseSurface),
        ],
      ),
    );
  }
}

/// Time to spare walking to the ride: green with time, orange to hurry, red with the next departure when too late
class _MarginPill extends ConsumerWidget {
  const _MarginPill({required this.state, required this.margin, required this.now});

  final GoState state;
  final WalkMargin margin;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final minutes = (margin.margin.inSeconds.abs() / 60).floor();
    return switch (margin.level) {
      MarginLevel.ahead => _Pill(
          icon: Icons.check_circle,
          text: context.l10n.goMarginAhead(minutes),
          color: context.colors.live,
          textColor: Colors.white,
        ),
      MarginLevel.hurry => _Pill(
          icon: Icons.directions_run,
          text: context.l10n.goMarginHurry,
          color: context.colors.warning,
          textColor: Colors.white,
        ),
      MarginLevel.late => _Pill(
          icon: Icons.warning_amber,
          text: _nextOne(context, ref) ?? context.l10n.goMarginLate,
          color: scheme.error,
          textColor: scheme.onError,
        ),
    };
  }

  /// `Vous allez le rater · suivant à 14:38 (+6 min)`, from the ride's departures
  String? _nextOne(BuildContext context, WidgetRef ref) {
    final tracker = state.tracker;
    final index = state.progress.step + 1;
    final ride = tracker.steps[index];
    final earliest = earliestBoarding(state.journey, ride.sectionIndex, now).add(state.progress.shift);
    final key = rideKey(ride.section, earliest, now);
    if (key == null) {
      return null;
    }
    final walk = Duration(seconds: (metersToGo(state) / movePace(state, tracker.steps[state.progress.step])).round());
    final reachable = now.add(walk);
    final next = (ref.watch(rideOptionsProvider(key)).value ?? const [])
        .where((ride) => ride.departure.time.isAfter(reachable) && ride.departure.time.isAfter(margin.departure))
        .firstOrNull;
    if (next == null) {
      return null;
    }
    final later = next.departure.time.difference(margin.departure).roundedMinutes;
    return context.l10n.goMarginLateNext(formatClock(next.departure.time), later);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color, required this.textColor});

  final IconData icon;
  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: textColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(text,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: textColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
}
