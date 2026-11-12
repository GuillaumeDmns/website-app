import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/utils/colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/size_reporter.dart';
import '../../../core/widgets/ui.dart';
import '../../../l10n/l10n.dart';
import '../go_cards.dart';
import '../go_controller.dart';
import '../go_glance.dart';
import '../go_state.dart';
import '../go_tracker.dart';
import 'go_card_parts.dart';

/// A ride on board, like Citymapper's card after boarding: how many stops to where to get off and in how long, the
/// stops on a rail with their times, the user's dot between the stop left and the next one where GO puts them
/// ([GoTracker.betweenStops]: the GPS above ground, the clock underground), and "Alerter quand descendre". Its header
/// turns red when getting off is close.
class GoRideCard extends ConsumerWidget {
  const GoRideCard({super.key, required this.state, required this.card, required this.live, required this.done, this.onHeadSize});

  final GoState state;
  final GoCard card;
  final bool live;
  final bool done;
  final ValueChanged<Size>? onHeadSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final tracker = state.tracker;
    final progress = state.progress;
    final step = tracker.steps[card.step];
    final section = step.section;
    final line = section.line;
    final stops = section.stops;
    final onBoard = progress.phase == GoPhase.onBoard && progress.step == card.step;
    final left = onBoard ? tracker.stopsLeft(progress) : math.max(1, stops.length - 1);
    final arrival = section.arrival.add(progress.shift);
    final minutes = onBoard ? minutesLeft(arrival.difference(now)) : math.max(1, (section.duration / 60).round());
    final to = section.to?.name ?? '';
    final nextStop = progress.stopIndex + 1 < stops.length ? stops[progress.stopIndex + 1].name : null;

    final glance = live && onBoard ? goGlance(state, now) : null;
    final header = glance != null && glance.tone != GoTone.ok
        ? GoCardHeader.alert(glance, live: true)
        : GoCardHeader(
            leading: line != null ? LineBadge(line, size: 30) : const Icon(Icons.directions_transit, size: 30),
            title: onBoard && left <= 1 ? context.l10n.goGetOffNext : context.l10n.goStopsTo(left, to),
            subtitle: !onBoard
                ? context.l10n.direction(section.headsign ?? '')
                : left <= 1 || nextStop == null
                ? '$to · ${context.l10n.arrivalAt(formatClock(arrival))}'
                : context.l10n.goNextStop(nextStop),
            figure: minutes <= 0 ? context.l10n.now : '$minutes',
            unit: minutes <= 0 ? null : context.l10n.minutesUnit,
            live: live,
            done: done,
          );
    final late = (progress.shift.inSeconds / 60).round();
    return GoCardFrame(
      children: [
        SizeReporter(
          onSize: (size) => onHeadSize?.call(size),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (!live && !done) ...[const SizedBox(height: 12), GoHereButton(card: card)],
              if (onBoard && late >= 1) ...[
                const SizedBox(height: 12),
                GoContextLine(icon: Icons.schedule, text: context.l10n.goMinutesLate(late), color: context.colors.warning),
              ],
              if (!done) ...[
                const SizedBox(height: 12),
                _StopsRail(state: state, step: step, onBoard: onBoard, now: now, color: parseHexColor(line?.color, theme.colorScheme.primary)),
                const SizedBox(height: 4),
                _AlightAlertSwitch(step: card.step, on: !state.alightAlertsOff.contains(card.step)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The ride's stops down a rail in the line's color, like Citymapper's: on board from the stop left (the ones before
/// it gone), the next one stressed, where to get off marked; the user's dot glides between the stop left and the next
/// one. Long rides fold the stops in between.
class _StopsRail extends StatelessWidget {
  const _StopsRail({required this.state, required this.step, required this.onBoard, required this.now, required this.color});

  final GoState state;
  final GoStep step;
  final bool onBoard;
  final DateTime now;
  final Color color;

  /// More stops than this: the ones in between folded
  static const _maxShown = 8;
  static const _timeWidth = 48.0;
  static const _railWidth = 24.0;

  @override
  Widget build(BuildContext context) {
    final stops = step.section.stops;
    if (stops.length < 2) {
      return const SizedBox.shrink();
    }
    final progress = state.progress;
    final last = stops.length - 1;
    final from = onBoard ? math.min(progress.stopIndex, last - 1) : 0;
    final indexes = [for (var k = from; k <= last; k++) k];
    final folded = indexes.length > _maxShown ? indexes.length - (_maxShown - 1) : 0;
    final shown = folded == 0 ? indexes : [...indexes.take(_maxShown - 2), -1, last];
    final rowHeight = MediaQuery.textScalerOf(context).scale(34);
    final share = onBoard ? state.tracker.betweenStops(progress, now) : null;
    final railLeft = _timeWidth + _railWidth / 2 - 2.5;
    final top = rowHeight / 2;
    final bottom = rowHeight * (shown.length - 0.5);

    Widget rail(double top, double bottom, double alpha) => Positioned(
          left: railLeft,
          top: top,
          height: math.max(0, bottom - top),
          width: 5,
          child: ColoredBox(color: color.withValues(alpha: alpha)),
        );

    return Semantics(
      label: context.l10n.goGetOffInAt(state.tracker.stopsLeft(progress), stops[last].name),
      excludeSemantics: onBoard,
      child: TweenAnimationBuilder<double>(
        // From one fix or tick to the next, a glide; at the next stretch the user starts where they are
        key: ValueKey(from),
        tween: Tween(end: share ?? 0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        child: Column(
          children: [
            for (final (row, k) in shown.indexed)
              SizedBox(
                height: rowHeight,
                child: k < 0
                    ? _StopRow.folded(context.l10n.stopsCount(folded))
                    : _StopRow(
                        name: stops[k].name,
                        // Where to get off: the ride's arrival (a stop's time is its departure)
                        time: (k == last ? step.section.arrival : step.stopTime(k)).add(progress.shift),
                        color: color,
                        gone: onBoard && row == 0,
                        next: onBoard && row == 1 && k != last,
                        end: k == last,
                        first: row == 0,
                      ),
              ),
          ],
        ),
        builder: (context, share, rows) {
          final me = top + rowHeight * share;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (onBoard) ...[rail(top, me, 0.35), rail(me, bottom, 1)] else rail(top, bottom, 1),
              rows!,
              if (share > 0 || onBoard) Positioned(left: _timeWidth + _railWidth / 2 - 9, top: me - 9, child: const _UserDot()),
            ],
          );
        },
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.name,
    required this.time,
    required this.color,
    required this.gone,
    required this.next,
    required this.end,
    required this.first,
  }) : folded = false;

  const _StopRow.folded(this.name)
      : time = null,
        color = Colors.transparent,
        gone = false,
        next = false,
        end = false,
        first = false,
        folded = true;

  final String name;
  final DateTime? time;
  final Color color;

  /// The stop left, on board
  final bool gone;

  /// The next stop
  final bool next;

  /// Where to get off
  final bool end;
  final bool first;
  final bool folded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final emphasis = next || end || (first && !gone);
    final dot = end || first ? 14.0 : 10.0;
    return Row(
      children: [
        SizedBox(
          width: _StopsRail._timeWidth,
          child: Text(time == null ? '' : formatClock(time!),
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: emphasis ? FontWeight.w600 : null, color: gone ? colors.muted : null)),
        ),
        SizedBox(
          width: _StopsRail._railWidth,
          child: folded
              ? null
              : Center(
                  child: Container(
                    width: dot,
                    height: dot,
                    decoration: BoxDecoration(
                      color: end ? color : colors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 3),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: folded
                ? theme.textTheme.bodySmall?.copyWith(color: colors.muted)
                : emphasis
                ? theme.textTheme.titleSmall
                : theme.textTheme.bodyMedium?.copyWith(color: gone ? colors.muted : null),
          ),
        ),
        if (next) PillTag(text: context.l10n.goNextStopLabel, color: theme.colorScheme.primary),
        if (end) PillTag(text: context.l10n.goGetOffHere, color: theme.colorScheme.error),
      ],
    );
  }
}

/// The user on the rail: the blue of the map's dot
class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    final blue = Theme.of(context).colorScheme.secondary;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: blue,
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.card, width: 3),
        boxShadow: [BoxShadow(color: blue.withValues(alpha: 0.18), spreadRadius: 4)],
      ),
    );
  }
}

/// "Alerter quand descendre" for one ride, on by default: off, getting off there is not felt
class _AlightAlertSwitch extends ConsumerWidget {
  const _AlightAlertSwitch({required this.step, required this.on});

  final int step;
  final bool on;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        secondary: Icon(on ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
        title: Text(context.l10n.goAlightAlert, style: Theme.of(context).textTheme.titleSmall),
        value: on,
        onChanged: (value) => ref.read(goControllerProvider.notifier).setAlightAlert(step, value),
      );
}
