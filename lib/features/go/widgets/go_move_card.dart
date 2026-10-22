import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/utils/time_format.dart';
import '../../../l10n/l10n.dart';
import '../../journey/journey_labels.dart';
import '../go_controller.dart';
import '../go_guidance.dart';
import '../go_instruction.dart';
import '../go_state.dart';
import '../go_tracker.dart';
import 'go_card_parts.dart';

/// A move on foot or by bike. In progress: what to do now (the next turn, else where to go), how far, the time to
/// spare (the banner and [GoNowCard] when [compact]); the turns folded under it so that the panel stays low.
/// Otherwise where to, how long and its turns. Then what comes next.
class GoMoveCard extends ConsumerWidget {
  const GoMoveCard({super.key, required this.state, required this.index, this.compact = false});

  final GoState state;
  final int index;

  /// The step in progress under the banner and [GoNowCard], which tell what to do: only the turns and what follows
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tracker = state.tracker;
    final progress = state.progress;
    final step = tracker.steps[index];
    final section = step.section;
    final isLive = index == progress.step && progress.phase == GoPhase.moving;
    final isDone = index < progress.step || progress.phase == GoPhase.arrived;
    final next = isLive ? nextManeuver(step, progress.along) : null;
    final along = isLive ? progress.along : (isDone ? double.infinity : 0.0);
    final total = (section.length ?? 0) > 0 ? section.length! : (section.steps.isEmpty ? 0 : section.steps.last.offset + section.steps.last.length);
    final scale = total > 0 && step.line.length > 0 ? step.line.length / total : 1.0;
    final turns = [
      for (final walk in section.steps)
        _TurnRow(
          walk: walk,
          passed: walk.offset * scale < along - 3 && walk != next?.walk,
          next: walk == next?.walk,
          meters: walk == next?.walk ? next!.meters : null,
        ),
    ];

    final Widget title;
    if (isLive) {
      final now = DateTime.now();
      final instruction = goInstruction(state, now);
      title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GoCardTitle(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppTheme.brand, borderRadius: BorderRadius.circular(12)),
              child: Icon(instruction.icon ?? moveIcon(section.kind), size: 30, color: Colors.white),
            ),
            title: instruction.title,
            detail: instruction.subtitle,
          ),
          if (instruction.towards case final towards?)
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 4),
              child: Text(towards, style: theme.textTheme.bodyMedium?.copyWith(color: context.colors.muted)),
            ),
          GoPills(state: state, now: now),
        ],
      );
    } else {
      title = GoCardTitle(
        leading: Icon(moveIcon(section.kind), size: 34, color: isDone ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary),
        title: section.kind == SectionKind.transfer
            ? context.l10n.goTransferTo(section.to?.name ?? '')
            : context.l10n.goVerbTo(moveVerb(section.kind), section.to?.name ?? ''),
        detail: [formatDuration(section.duration), if ((section.length ?? 0) > 0) formatDistance(section.length!)].join(' · '),
        done: isDone,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) title,
        // The turns: folded while walking (the next one is the title), open on a step looked at
        if (turns.length > 1) _Turns(initiallyExpanded: !isLive, children: turns),
        if (!isDone && index + 1 < tracker.steps.length) GoNextStep(state: state, index: index + 1),
        const SizedBox(height: 8),
        if (!isDone && index != progress.step && !compact)
          GoSmallAction(label: context.l10n.goImAtThisStep, onPressed: () => ref.read(goControllerProvider.notifier).jumpTo(index)),
      ],
    );
  }
}

/// The turns of a move behind a header, folded or not
class _Turns extends StatefulWidget {
  const _Turns({required this.initiallyExpanded, required this.children});

  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  State<_Turns> createState() => _TurnsState();
}

class _TurnsState extends State<_Turns> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.format_list_bulleted, size: 20, color: context.colors.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('${context.l10n.goTurnByTurn} · ${widget.children.length}',
                      style: theme.textTheme.labelLarge?.copyWith(color: context.colors.muted)),
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: context.colors.muted),
              ],
            ),
          ),
        ),
        if (_expanded) ...widget.children,
      ],
    );
  }
}

class _TurnRow extends StatelessWidget {
  const _TurnRow({required this.walk, required this.passed, required this.next, this.meters});

  final WalkStep walk;
  final bool passed;
  final bool next;

  /// To the turn, for the next one
  final double? meters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = next ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return Opacity(
      opacity: passed ? 0.4 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(walk.offset == 0 ? Icons.navigation_outlined : turnIcon(walk.direction), size: 22, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                walk.instruction,
                style: (next ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)?.copyWith(
                  fontWeight: next ? FontWeight.w600 : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatDistance((meters ?? walk.length.toDouble()).round()),
              style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: next ? FontWeight.w600 : null),
            ),
          ],
        ),
      ),
    );
  }
}
