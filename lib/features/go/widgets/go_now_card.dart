import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/utils/colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../l10n/l10n.dart';
import '../../journey/journey_labels.dart';
import '../go_controller.dart';
import '../go_guidance.dart';
import '../go_state.dart';
import '../go_tracker.dart';
import 'go_card_parts.dart';
import 'go_ride_card.dart';

/// Under the banner, in the capsule, for the step in progress: one card of context (on board the stops ahead on a
/// rail, waiting where to board along the train, then a single line: the time to spare, the delay, what comes next),
/// and, only when it does, that GO follows the schedule for want of GPS. The banner says what to do; this says why it's
/// fine.
class GoNowCard extends ConsumerWidget {
  const GoNowCard({super.key, required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final now = DateTime.now();
    final progress = state.progress;
    final step = state.tracker.stepOf(progress);
    final line = _contextLine(context, ref, now);
    final noGps = progress.phase != GoPhase.arrived && state.tracker.followsSchedule(progress, now);
    final positions = step?.section.boardingPositions ?? const <String>[];
    final lineColor = parseHexColor(step?.section.line?.color, theme.colorScheme.primary);

    final parts = <Widget>[
      if (step != null && progress.phase == GoPhase.onBoard) _StopsRail(state: state, step: step, color: lineColor),
      if (progress.phase == GoPhase.waiting && positions.isNotEmpty && positions.length < 3)
        TrainPositions(positions: positions, color: lineColor),
      if (line != null)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(line.icon, size: 20, color: line.color)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(line.text, style: theme.textTheme.titleSmall?.copyWith(color: line.color, height: 1.3)),
            ),
          ],
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (parts.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: theme.brightness == Brightness.light ? Border.all(color: theme.colorScheme.outline, width: 0.5) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, part) in parts.indexed) ...[if (index > 0) const SizedBox(height: 10), part],
              ],
            ),
          ),
        if (state.retained != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(context.l10n.goRecalculateJourney),
              onPressed: state.recalculating ? null : ref.read(goControllerProvider.notifier).recalculate,
            ),
          ),
        if (noGps)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
            child: Row(
              children: [
                Icon(Icons.gps_off, size: 16, color: colors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(context.l10n.goNoGps, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// The one line of context: green when all is well, orange when it needs attention, plain for what comes next
  ({IconData icon, String text, Color color})? _contextLine(BuildContext context, WidgetRef ref, DateTime now) {
    final colors = context.colors;
    final text = Theme.of(context).colorScheme.onSurface;
    final progress = state.progress;
    final tracker = state.tracker;
    switch (progress.phase) {
      case GoPhase.moving:
        final margin = walkMargin(state, now);
        if (margin != null) {
          final ride = tracker.steps[progress.step + 1];
          final vehicle = state.vehicleStep == progress.step + 1 ? state.vehicle : null;
          final platform = platformLabel(ride.section.line, vehicle?.platform);
          return switch (margin.level) {
            MarginLevel.ahead => (
                icon: Icons.check_circle,
                text: [
                  context.l10n.goMarginAheadOf(
                      (margin.margin.inSeconds / 60).floor(), ride.section.line?.label ?? '', formatClock(margin.departure)),
                  ?platform,
                ].join(' · '),
                color: colors.live,
              ),
            // The banner says to hurry: here, the plan B
            MarginLevel.hurry => switch (goNextCatchable(ref, state, margin, now)) {
                (:final time, :final later) => (icon: Icons.update, text: context.l10n.goIfMissed(formatClock(time), later), color: text),
                null => (icon: Icons.directions_run, text: context.l10n.goMarginHurry, color: colors.warning),
              },
            MarginLevel.late => (
                icon: Icons.warning_amber,
                text: goMissedNextText(ref, state, margin, now) ?? context.l10n.goMarginLate,
                color: colors.warning,
              ),
          };
        }
        return _then(context, progress.step + 1, text);
      case GoPhase.waiting:
        return _then(context, progress.step + 1, text);
      case GoPhase.onBoard:
        final late = progress.shift.inSeconds / 60;
        if (late >= 1) {
          return (icon: Icons.schedule, text: context.l10n.goMinutesLate(late.round()), color: colors.warning);
        }
        return state.currentVehicle != null
            ? (icon: Icons.check_circle, text: context.l10n.goOnTimeLive, color: colors.live)
            : _then(context, progress.step + 1, text);
      case GoPhase.arrived:
        return null;
    }
  }

  /// What comes after: `Ensuite : 3 · Direction Gallieni · départ 08:38`, or the arrival
  ({IconData icon, String text, Color color}) _then(BuildContext context, int index, Color color) {
    final tracker = state.tracker;
    if (index >= tracker.steps.length) {
      return (
        icon: Icons.flag,
        text: context.l10n.goArrival(formatClock(tracker.eta(state.progress, state.currentVehicle))),
        color: color,
      );
    }
    final step = tracker.steps[index];
    final section = step.section;
    if (step.isRide) {
      final vehicle = state.vehicleStep == index ? state.vehicle : null;
      final departure = tracker.expectedDeparture(step, state.progress, vehicle);
      return (
        icon: Icons.transfer_within_a_station,
        text: [
          '${context.l10n.goThen} : ${section.line?.label ?? ''}',
          context.l10n.direction(section.headsign ?? ''),
          context.l10n.goDepartsAt(formatClock(departure)),
        ].join(' · '),
        color: color,
      );
    }
    return (
      icon: moveIcon(section.kind),
      text: '${context.l10n.goThen} : ${context.l10n.goNextMove(formatDuration(section.duration), section.to?.name ?? '')}',
      color: color,
    );
  }
}

/// On board, the stops ahead on one line, left to right: the last one left, the user, the next one, then where to
/// get off. One column each, the line running through their dots, bright up to the user and faint after.
class _StopsRail extends StatelessWidget {
  const _StopsRail({required this.state, required this.step, required this.color});

  final GoState state;
  final GoStep step;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final stops = step.section.stops;
    if (stops.length < 2) {
      return const SizedBox.shrink();
    }
    final last = stops.length - 1;
    final left = math.min(state.progress.stopIndex, last);
    final items = <(String, _Dot)>[
      (stops[left].name, _Dot.done),
      ('', _Dot.me),
      if (left + 1 < last) (stops[left + 1].name, _Dot.next),
      if (left + 2 < last) (stops[left + 2].name, _Dot.stop),
      if (left < last) (stops[last].name, _Dot.end),
    ];
    final me = items.indexWhere((item) => item.$2 == _Dot.me);
    Widget half(bool shown, bool bright) => Expanded(
          child: Container(height: 4, color: shown ? color.withValues(alpha: bright ? 1 : 0.3) : Colors.transparent),
        );
    return Semantics(
      label: context.l10n.goGetOffInAt(state.tracker.stopsLeft(state.progress), stops[last].name),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, (label, dot)) in items.indexed)
            Expanded(
              // The end gets more room for its name
              flex: dot == _Dot.end || dot == _Dot.next ? 3 : 2,
              child: Column(
                children: [
                  SizedBox(
                    height: 18,
                    child: Row(
                      children: [
                        half(index > 0, index <= me),
                        _dot(context, dot),
                        half(index < items.length - 1, index < me),
                      ],
                    ),
                  ),
                  _label(context, label, dot),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dot(BuildContext context, _Dot dot) {
    final card = context.colors.card;
    final blue = Theme.of(context).colorScheme.secondary;
    final (size, fill, border, halo) = switch (dot) {
      _Dot.done => (10.0, color, null, null),
      _Dot.me => (18.0, blue, Border.all(color: card, width: 3), BoxShadow(color: blue.withValues(alpha: 0.18), spreadRadius: 4)),
      _Dot.next => (14.0, card, Border.all(color: color, width: 3), null),
      _Dot.stop => (11.0, card, Border.all(color: color, width: 2.5), null),
      _Dot.end => (18.0, color, Border.all(color: card, width: 3), BoxShadow(color: color, spreadRadius: 2)),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: border, boxShadow: [?halo]),
    );
  }

  Widget _label(BuildContext context, String label, _Dot dot) {
    final theme = Theme.of(context);
    final strong = dot == _Dot.next || dot == _Dot.end;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: strong
            ? theme.textTheme.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)
            : theme.textTheme.labelMedium?.copyWith(fontSize: 11),
      ),
    );
  }
}

enum _Dot { done, me, next, stop, end }

/// "Corriger", next to the steps' strip, whatever card is shown: GO got where the user is wrong
class GoCorrectButton extends StatelessWidget {
  const GoCorrectButton({super.key, required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => showGoCorrection(context, state),
        child: Text(context.l10n.goCorrect),
      );
}

/// "Corriger": where the user is, when GO got it wrong. On board, at a step, arrived: GO goes on from there.
Future<void> showGoCorrection(BuildContext context, GoState state) {
  final tracker = state.tracker;
  final progress = state.progress;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final theme = Theme.of(context);
        final controller = ref.read(goControllerProvider.notifier);
        void pick(VoidCallback action) {
          HapticFeedback.lightImpact();
          action();
          Navigator.pop(context);
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(context.l10n.goCorrectTitle, style: theme.textTheme.titleMedium),
                ),
                if (progress.phase == GoPhase.waiting)
                  ListTile(
                    leading: const Icon(Icons.directions_transit),
                    title: Text(context.l10n.goImOnBoard),
                    onTap: () => pick(controller.next),
                  ),
                for (final (index, step) in tracker.steps.indexed)
                  ListTile(
                    selected: index == progress.step && progress.phase != GoPhase.arrived,
                    leading: step.isRide && step.section.line != null
                        ? LineBadge(step.section.line!, size: 26)
                        : Icon(step.section.kind == SectionKind.transfer ? Icons.transfer_within_a_station : moveIcon(step.section.kind)),
                    title: Text(step.isRide
                        ? '${step.section.line?.label ?? ''} → ${step.section.headsign ?? ''}'
                        : step.section.kind == SectionKind.transfer
                            ? context.l10n.goTransferTo(step.section.to?.name ?? '')
                            : context.l10n.goVerbTo(moveVerb(step.section.kind), step.section.to?.name ?? '')),
                    subtitle: Text(formatClock(step.section.departure.add(progress.shift))),
                    onTap: () => pick(() => controller.jumpTo(index)),
                  ),
                ListTile(
                  leading: Icon(Icons.flag, color: theme.colorScheme.error),
                  title: Text(context.l10n.goImArrived),
                  onTap: () => pick(() => controller.jumpTo(tracker.steps.length)),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
