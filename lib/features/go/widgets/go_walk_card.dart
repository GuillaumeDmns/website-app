import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/size_reporter.dart';
import '../../../l10n/l10n.dart';
import '../../journey/journey_labels.dart';
import '../go_cards.dart';
import '../go_controller.dart';
import '../go_glance.dart';
import '../go_guidance.dart';
import '../go_state.dart';
import '../go_tracker.dart';
import 'go_card_parts.dart';

/// A move on foot (or by bike, by car), like Citymapper's: where to and how long, then its turns (from the next one on
/// the move in progress, which the map labels too), the time to spare on the ride after it, the best way into the
/// station it ends at. Its header says what needs attention: walking too slowly for the ride, off the way.
class GoWalkCard extends ConsumerWidget {
  const GoWalkCard({
    super.key,
    required this.state,
    required this.card,
    required this.live,
    required this.done,
    this.onHeadSize,
    this.outAlong = 0,
    this.entrance,
  });

  final GoState state;
  final GoCard card;

  /// The card of what is going on
  final bool live;
  final bool done;

  /// The size of what the sheet shows of it at rest
  final ValueChanged<Size>? onHeadSize;

  /// Meters along the move once out of the station before it, for "Je suis ici"
  final double outAlong;

  /// The best way into the station it ends at
  final StationEntrance? entrance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final tracker = state.tracker;
    final progress = state.progress;
    final step = tracker.steps[card.step];
    final section = step.section;
    final moving = progress.phase == GoPhase.moving && progress.step == card.step;
    final pace = movePace(state, step);
    final meters = moving ? metersToGo(state) : ((section.length ?? 0) > 0 ? section.length!.toDouble() : step.line.length);
    final minutes = moving ? math.max(1, (meters / pace / 60).ceil()) : math.max(1, (section.duration / 60).round());
    final to = section.to?.name ?? '';

    final glance = live && moving ? goGlance(state, now, turns: false) : null;
    final header = glance != null && glance.tone != GoTone.ok
        ? GoCardHeader.alert(glance, live: true)
        : GoCardHeader(
            leading: GoMoveIcon(icon: moveIcon(section.kind), live: live),
            title: section.kind == SectionKind.transfer ? context.l10n.goTransferTo(to) : context.l10n.goVerbTo(moveVerb(section.kind), to),
            subtitle: meters >= 1 ? formatDistance(meters.round()) : null,
            figure: '$minutes',
            unit: context.l10n.minutesUnit,
            live: live,
            done: done,
          );

    final turns = _turns(context, step, moving, pace);
    final head = [
      header,
      if (!live && !done) GoHereButton(card: card, along: outAlong),
      if (live && progress.issue == GoIssue.offRoute) _OffRouteActions(state: state),
      if (live && moving) ?_marginLine(context, ref, now),
      ?turns.firstOrNull,
    ];
    return GoCardFrame(
      children: [
        SizeReporter(
          onSize: (size) => onHeadSize?.call(size),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, part) in head.indexed) ...[if (index > 0) const SizedBox(height: 12), part],
            ],
          ),
        ),
        ...turns.skip(1),
        if (entrance case final entrance?) GoStationAccess(entrance: entrance, exit: false),
        if (live && tracker.followsSchedule(progress, now)) const GoNoGpsLine(),
      ],
    );
  }

  /// Navitia's instructions as Citymapper lists them: how far after the one before, what to do, how long. On the move in
  /// progress, from the next turn (the ones gone by are left out), its distance from the user.
  List<Widget> _turns(BuildContext context, GoStep step, bool moving, double pace) {
    final walks = step.section.steps;
    if (walks.isEmpty) {
      return const [];
    }
    final total = (step.section.length ?? 0) > 0 ? step.section.length! : walks.last.offset + walks.last.length;
    final scale = total > 0 && step.line.length > 0 ? step.line.length / total : 1.0;
    final along = moving ? state.progress.along : 0.0;
    final next = moving ? nextManeuver(step, along) : null;
    final rows = <Widget>[];
    var first = true;
    for (final (index, walk) in walks.indexed) {
      final at = walk.offset * scale;
      if (moving && at < along - 3 && walk != next?.walk) {
        continue;
      }
      final from = first && moving ? along : (index == 0 ? 0.0 : walks[index - 1].offset * scale);
      first = false;
      rows.add(_TurnRow(walk: walk, meters: walk.offset == 0 ? null : math.max(0.0, at - from), pace: pace, next: walk == next?.walk));
    }
    return rows;
  }

  /// The time to spare on the ride after the move, green; walking too slowly, the departure after it
  Widget? _marginLine(BuildContext context, WidgetRef ref, DateTime now) {
    final margin = walkMargin(state, now);
    if (margin == null) {
      return null;
    }
    final colors = context.colors;
    final ride = state.tracker.steps[state.progress.step + 1];
    final vehicle = state.vehicleStep == state.progress.step + 1 ? state.vehicle : null;
    return switch (margin.level) {
      MarginLevel.ahead => GoContextLine(
          icon: Icons.check_circle,
          text: [
            context.l10n.goMarginAheadOf((margin.margin.inSeconds / 60).floor(), ride.section.line?.label ?? '', formatClock(margin.departure)),
            ?platformLabel(ride.section.line, vehicle?.platform),
          ].join(' · '),
          color: colors.live,
        ),
      // The header says to hurry: here, the plan B
      MarginLevel.hurry => switch (goNextCatchable(ref, state, margin, now)) {
          (:final time, :final later) => GoContextLine(icon: Icons.update, text: context.l10n.goIfMissed(formatClock(time), later)),
          null => null,
        },
      MarginLevel.late => GoContextLine(
          icon: Icons.warning_amber,
          text: goMissedNextText(ref, state, margin, now) ?? context.l10n.goMarginLate,
          color: colors.warning,
        ),
    };
  }
}

/// Off the way: the recalculation coming on its own (its countdown in the header), done now or ignored
class _OffRouteActions extends ConsumerWidget {
  const _OffRouteActions({required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(goControllerProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: state.recalculating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh, size: 20),
            label: Text(context.l10n.recalculate),
            onPressed: state.recalculating ? null : controller.recalculate,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: controller.dismissIssue,
            child: Text(context.l10n.dismiss),
          ),
        ),
      ],
    );
  }
}

/// One instruction of a move, like Citymapper's: its arrow in a square, `Dans 35 m` over what to do, the time it takes
class _TurnRow extends StatelessWidget {
  const _TurnRow({required this.walk, required this.meters, required this.pace, required this.next});

  final WalkStep walk;

  /// From the instruction before (from the user for the first one of the move in progress); null for the first one
  final double? meters;
  final double pace;

  /// The next turn of the move in progress
  final bool next;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = next ? AppTheme.brand : theme.colorScheme.onSurface;
    final meters = this.meters;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: context.colors.subtle, borderRadius: BorderRadius.circular(9)),
          child: Icon(walk.offset == 0 ? Icons.navigation_outlined : turnIcon(walk.direction), size: 22, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (meters != null)
                Text(context.l10n.goInDistance(formatDistance(meters.round())),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: next ? color : null)),
              Text(walk.instruction, style: theme.textTheme.bodyMedium?.copyWith(height: 1.3)),
            ],
          ),
        ),
        if (meters != null) ...[
          const SizedBox(width: 8),
          Text(goWalkMinutes(Duration(seconds: (meters / pace).round())),
              style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
        ],
      ],
    );
  }
}
