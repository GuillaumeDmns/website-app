import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/size_reporter.dart';
import '../../../l10n/l10n.dart';
import '../go_cards.dart';
import '../go_guidance.dart';
import '../go_state.dart';
import 'go_card_parts.dart';

/// Getting out of the station after a metro or a train, like Citymapper's: its best way out (the one leaving the least
/// to walk, [bestExit]) and how long to it; the map shows every way out, the best one named
class GoExitCard extends ConsumerWidget {
  const GoExitCard({super.key, required this.state, required this.card, required this.live, required this.done, this.exit, this.onHeadSize});

  final GoState state;
  final GoCard card;
  final bool live;
  final bool done;

  /// The best way out, when the station's are known
  final StationAccess? exit;
  final ValueChanged<Size>? onHeadSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracker = state.tracker;
    final step = tracker.steps[card.step];
    final exit = this.exit;
    final progress = state.progress;
    final along = progress.step == card.step ? progress.along : 0.0;
    final minutes = exit == null ? null : math.max(1, ((exit.along - along) / movePace(state, step) / 60).ceil());
    return GoCardFrame(
      children: [
        SizeReporter(
          onSize: (size) => onHeadSize?.call(size),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GoCardHeader(
                leading: GoMoveIcon(icon: Icons.exit_to_app, live: live),
                title: context.l10n.goExitStation,
                subtitle: tracker.steps[card.step - 1].section.to?.name,
                figure: done || minutes == null ? null : '$minutes',
                unit: done || minutes == null ? null : context.l10n.minutesUnit,
                live: live,
                done: done,
              ),
              if (!live && !done) ...[const SizedBox(height: 12), GoHereButton(card: card)],
              if (exit != null && !done) ...[const SizedBox(height: 12), GoStationAccess(entrance: exit.entrance, exit: true)],
            ],
          ),
        ),
      ],
    );
  }
}
