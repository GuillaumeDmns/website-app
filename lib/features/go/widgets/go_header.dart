import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/location/location_providers.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../l10n/l10n.dart';
import '../../journey/journey_providers.dart';
import '../../journey/journey_retime.dart';
import '../../journey/journey_labels.dart';
import '../go_controller.dart';
import '../go_state.dart';
import '../go_tracker.dart';

/// The capsule's first line: the arrival, against the plan and in how long; screen, sound and stop kept small
class GoHeader extends ConsumerWidget {
  const GoHeader({super.key, required this.state, required this.onBack});

  final GoState state;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final controller = ref.read(goControllerProvider.notifier);
    final arrived = state.progress.phase == GoPhase.arrived;
    final now = DateTime.now();
    final eta = state.tracker.eta(state.progress, state.currentVehicle);
    final late = eta.difference(state.journey.arrival).inMinutes;
    final left = eta.difference(now);
    final compact = MediaQuery.textScalerOf(context).scale(10) > 13;
    final small = IconButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: colors.muted);

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 4, 0),
      child: Row(
        children: [
          IconButton(tooltip: context.l10n.back, style: small, icon: const Icon(Icons.arrow_back, size: 22), onPressed: onBack),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: arrived ? context.l10n.goFinished : context.l10n.goArrival(formatClock(eta))),
                  if (!arrived && late.abs() >= 1)
                    TextSpan(
                      text: '  ${late > 0 ? '+' : ''}${context.l10n.minutesShort(late)}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: late >= 3 ? colors.warning : colors.muted,
                      ),
                    ),
                  if (!arrived && left > Duration.zero && !compact)
                    TextSpan(
                      text: ' · ${context.l10n.goArrivesIn(formatDuration(left.inSeconds))}',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14, color: colors.muted),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: state.keepAwake ? context.l10n.goLetScreenSleep : context.l10n.goKeepScreenOn,
            style: small,
            isSelected: state.keepAwake,
            icon: const Icon(Icons.light_mode_outlined, size: 20),
            selectedIcon: Icon(Icons.light_mode, size: 20, color: theme.colorScheme.primary),
            onPressed: controller.toggleKeepAwake,
          ),
          IconButton(
            tooltip: state.muted ? context.l10n.goUnmute : context.l10n.goMute,
            style: small,
            icon: Icon(state.muted ? Icons.volume_off_outlined : Icons.volume_up_outlined, size: 20),
            onPressed: controller.toggleMute,
          ),
          IconButton(
            tooltip: context.l10n.goStop,
            style: small,
            icon: const Icon(Icons.close, size: 22),
            onPressed: () => _confirmStop(context, ref),
          ),
        ],
      ),
    );
  }

  static Future<void> _confirmStop(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.goStopQuestion),
        content: Text(context.l10n.goStopText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.continueAction)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.finish)),
        ],
      ),
    );
    if (stop == true) {
      ref.read(goControllerProvider.notifier).stop();
      router.go(Routes.home);
    }
  }
}

/// How the fixes come (development builds): is the device's GPS giving one a second?
class GoGpsStats extends ConsumerWidget {
  const GoGpsStats({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(goFixStatsProvider);
    // Redrawn at each fix, and by the clock while none comes
    ref.watch(nowProvider);
    final interval = stats?.interval;
    final text = stats == null
        ? context.l10n.goGpsWaiting
        : context.l10n.goGpsStats(
            stats.accuracy.round(),
            interval == null ? '?' : (interval.inMilliseconds / 1000).toStringAsFixed(1),
            DateTime.now().difference(stats.at).inSeconds,
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.colors.muted)),
    );
  }
}

/// The steps of the journey in a row, small (walks with their minutes, rides with their line, a short dash between):
/// the one in progress filled, the one looked at outlined, the ones done faded. Tap one to look at it.
class GoStepStrip extends StatelessWidget {
  const GoStepStrip({super.key, required this.state, required this.shown, required this.onTap});

  final GoState state;
  final int shown;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final steps = state.tracker.steps;
    final progress = state.progress;
    final arrived = progress.phase == GoPhase.arrived;
    final live = arrived ? steps.length : progress.step;
    final primary = theme.colorScheme.primary;

    Widget item(int index, Widget child, String label) {
      final done = index < live;
      return Semantics(
        button: true,
        label: label,
        selected: index == shown,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => onTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              color: index == live ? primary.withValues(alpha: theme.brightness == Brightness.light ? 0.14 : 0.22) : null,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: index == shown && index != live ? primary : Colors.transparent, width: 1.5),
            ),
            child: Opacity(opacity: done ? 0.4 : 1, child: child),
          ),
        ),
      );
    }

    Widget dash() => Container(width: 10, height: 2, margin: const EdgeInsets.symmetric(horizontal: 2), color: theme.colorScheme.outline);

    final items = <Widget>[];
    for (final (index, step) in steps.indexed) {
      final section = step.section;
      if (items.isNotEmpty) {
        items.add(dash());
      }
      items.add(step.isRide && section.line != null
          ? item(index, LineBadge(section.line!, size: 20), section.line!.label)
          : item(
              index,
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(moveIcon(section.kind), size: 17, color: colors.muted),
                Text('${math.max(1, (section.duration / 60).round())}', style: TextStyle(fontSize: 11, color: colors.muted)),
              ]),
              context.l10n.goVerbTo(context.l10n.goVerbWalk, section.to?.name ?? '')));
    }
    items
      ..add(dash())
      ..add(item(steps.length, Icon(Icons.flag, size: 17, color: theme.colorScheme.error), context.l10n.goArrivalTitle));

    return SizedBox(
      height: MediaQuery.textScalerOf(context).scale(14) + 26,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        children: [Row(children: items)],
      ),
    );
  }
}

/// Off the way for a while: one line, with the recalculation
class GoOffRouteBanner extends ConsumerWidget {
  const GoOffRouteBanner({super.key, required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(goControllerProvider.notifier);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(color: theme.colorScheme.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.wrong_location_outlined, size: 20, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(child: Text(context.l10n.goOffRoute, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          state.recalculating
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(onPressed: controller.recalculate, child: Text(context.l10n.recalculate)),
          IconButton(tooltip: context.l10n.dismiss, icon: const Icon(Icons.close, size: 18), onPressed: controller.dismissIssue),
        ],
      ),
    );
  }
}

/// Missed or cancelled vehicle: the next departure of the line at once, to take it in one tap (no new search); the
/// recalculation second
class GoIssueCard extends ConsumerWidget {
  const GoIssueCard({super.key, required this.state, required this.issue});

  final GoState state;
  final GoIssue issue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(goControllerProvider.notifier);
    final progress = state.progress;
    final index = progress.step;
    final step = state.tracker.stepOf(progress);
    final line = step?.section.line;
    final lineLabel = line?.label ?? '';
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final key = step == null || !step.isRide ? null : rideKey(step.section, now, now);
    final planned = step == null ? now : state.tracker.expectedDeparture(step, progress, state.currentVehicle);
    final next = key == null
        ? null
        : (ref.watch(rideOptionsProvider(key)).value ?? const <Ride>[])
            .where((ride) => ride.departure.time.isAfter(now) && ride.departure.cancelled != true)
            .where((ride) => issue != GoIssue.cancelled || ride.departure.time.isAfter(planned.add(const Duration(seconds: 30))))
            .firstOrNull;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(issue == GoIssue.cancelled ? Icons.block : Icons.directions_run, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue == GoIssue.cancelled ? context.l10n.goCancelledChoose(lineLabel) : context.l10n.goMissedChoose(lineLabel),
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              IconButton(tooltip: context.l10n.dismiss, icon: const Icon(Icons.close, size: 18), onPressed: controller.dismissIssue),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                context.l10n.goNextDeparture(formatClock(next.departure.time), math.max(0, next.departure.time.difference(now).inMinutes)),
                if (next.arrivalAt case final arrival?) context.l10n.arrivalAt(formatClock(arrival)),
              ].join(' · '),
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onErrorContainer, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (next != null)
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    controller.dismissIssue();
                    controller.choose(index, next);
                  },
                  child: Text(context.l10n.goTakeThisOne),
                ),
              const SizedBox(width: 8),
              state.recalculating
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton(onPressed: controller.recalculate, child: Text(context.l10n.recalculate)),
            ],
          ),
        ],
      ),
    );
  }
}
