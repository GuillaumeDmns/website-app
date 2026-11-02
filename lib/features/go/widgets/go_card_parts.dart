import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../l10n/l10n.dart';
import '../../journey/journey_providers.dart';
import '../../journey/journey_retime.dart';
import '../go_cards.dart';
import '../go_controller.dart';
import '../go_glance.dart';
import '../go_guidance.dart';
import '../go_state.dart';

/// A card of GO: white, rounded, its parts one under the other
class GoCardFrame extends StatelessWidget {
  const GoCardFrame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A Material, for the ink of the switches and buttons in it
    return Material(
      color: context.colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: theme.brightness == Brightness.light ? BorderSide(color: theme.colorScheme.outline, width: 0.5) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, child) in children.indexed) ...[if (index > 0) const SizedBox(height: 12), child],
          ],
        ),
      ),
    );
  }
}

/// A card's header, like Citymapper's: what the card is about in a few words, one line under it, the figure that
/// counts on the right, Citymapper's blue dot by it on the card of what is going on. Orange when the moment needs
/// attention, red to act now: GO's alerts are said there, nowhere else on the screen.
class GoCardHeader extends StatelessWidget {
  const GoCardHeader({
    super.key,
    required this.leading,
    required this.title,
    this.titleSpan,
    this.subtitle,
    this.figure,
    this.unit,
    this.note,
    this.live = false,
    this.done = false,
    this.tone = GoTone.ok,
  });

  /// The header of the moment at a glance ([goGlance]) when it needs attention: its action, where, its figure
  factory GoCardHeader.alert(GoGlance glance, {required bool live}) => GoCardHeader(
        leading: glance.line != null ? LineBadge(glance.line!, size: 30) : Icon(glance.icon ?? Icons.info_outline, size: 30, color: Colors.white),
        title: glance.action,
        // Where, else the context: one line under the action
        subtitle: glance.place?.isNotEmpty ?? false ? glance.place : glance.kicker,
        figure: glance.hero,
        unit: glance.heroUnit,
        live: live,
        tone: glance.tone,
      );

  final Widget leading;
  final String title;

  /// Instead of [title], when parts of it have their own color (`20:30 À l'heure`)
  final InlineSpan? titleSpan;
  final String? subtitle;

  /// `7` (min), `3` (arrêts)
  final String? figure;
  final String? unit;

  /// Under the unit: the platform
  final String? note;
  final bool live;
  final bool done;
  final GoTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final background = switch (tone) {
      GoTone.ok => null,
      GoTone.warn => colors.warning,
      GoTone.urgent => colors.cancelled,
    };
    final foreground = background == null ? null : Colors.white;
    final soft = foreground?.withValues(alpha: 0.85) ?? colors.muted;
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: foreground ?? (done ? colors.muted : null),
    );
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 1, right: 12), child: leading),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (titleSpan case final span?)
                Text.rich(span, style: titleStyle, maxLines: 3, overflow: TextOverflow.ellipsis)
              else
                Text(title, style: titleStyle, maxLines: 3, overflow: TextOverflow.ellipsis),
              if (subtitle case final subtitle? when subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: soft, height: 1.3)),
              ],
            ],
          ),
        ),
        if (live) Padding(padding: const EdgeInsets.fromLTRB(8, 8, 0, 0), child: _LiveDot(onColor: background != null)),
        if (figure case final figure?)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  figure,
                  // A word ("maintenant") smaller than a figure: the title keeps its room
                  style: (int.tryParse(figure.replaceFirst('+', '')) == null ? theme.textTheme.titleMedium : theme.textTheme.headlineSmall)
                      ?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.05,
                    color: foreground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit case final unit?) Text(unit, style: theme.textTheme.labelMedium?.copyWith(color: soft)),
                if (note case final note?) Text(note, style: theme.textTheme.labelMedium?.copyWith(color: soft)),
              ],
            ),
          ),
        if (done) Padding(padding: const EdgeInsets.only(left: 8), child: Icon(Icons.check_circle, color: colors.live)),
      ],
    );
    if (background == null) {
      return content;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      child: content,
    );
  }
}

/// Citymapper's blue dot on the card of what is going on: the user is there
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.onColor});

  /// On an orange or red header: ringed in white
  final bool onColor;

  @override
  Widget build(BuildContext context) {
    final blue = Theme.of(context).colorScheme.secondary;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: onColor ? 2 : 0),
        boxShadow: [BoxShadow(color: blue.withValues(alpha: 0.25), spreadRadius: 3)],
      ),
    );
  }
}

/// The move's icon in a rounded square, green for the one in progress
class GoMoveIcon extends StatelessWidget {
  const GoMoveIcon({super.key, required this.icon, this.live = false});

  final IconData icon;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: live ? AppTheme.brand : context.colors.subtle,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 22, color: live ? Colors.white : Theme.of(context).colorScheme.onSurface),
      );
}

/// One line of context under a header: green when all is well, orange when it needs attention, plain otherwise
class GoContextLine extends StatelessWidget {
  const GoContextLine({super.key, required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 20, color: color ?? context.colors.muted)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: color, height: 1.3))),
      ],
    );
  }
}

/// GO follows the schedule for want of GPS: said once, small
class GoNoGpsLine extends StatelessWidget {
  const GoNoGpsLine({super.key});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(Icons.gps_off, size: 16, color: context.colors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(context.l10n.goNoGps, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      );
}

/// "Je suis ici" on a card that is not the one going on: GO got it wrong, it goes on from there
class GoHereButton extends ConsumerWidget {
  const GoHereButton({super.key, required this.card, this.along = 0, this.label});

  final GoCard card;

  /// On a walk after a station: out of it already
  final double along;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.my_location, size: 18),
          label: Text(label ?? context.l10n.goImHere),
          onPressed: () {
            HapticFeedback.lightImpact();
            ref.read(goControllerProvider.notifier).hereAt(card, along: along);
          },
        ),
      );
}

/// A station's way in or out: its number on the signs and its street, else the street alone
String stationAccessName(StationEntrance entrance, {required bool exit}) => switch (entrance.code) {
      final code? => exit ? currentL10n.goExitNamed(code, entrance.name) : currentL10n.goEntranceNamed(code, entrance.name),
      null => entrance.name,
    };

/// The best way in or out of a station, as Citymapper says it: `Meilleure sortie` over `Sortie 7 – r. de Presbourg`
class GoStationAccess extends StatelessWidget {
  const GoStationAccess({super.key, required this.entrance, required this.exit});

  final StationEntrance entrance;
  final bool exit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: context.colors.subtle, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(exit ? Icons.exit_to_app : Icons.login, size: 26, color: AppTheme.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exit ? context.l10n.goBestExit : context.l10n.goBestEntrance, style: theme.textTheme.bodyMedium),
                Text(
                  stationAccessName(entrance, exit: exit),
                  style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.brand, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `Vous allez le rater · suivant à 14:38 (+6 min)`: walking too slowly to the ride, its next departure the user can
/// still catch, from the ride's departures
String? goMissedNextText(WidgetRef ref, GoState state, WalkMargin margin, DateTime now) => switch (goNextCatchable(ref, state, margin, now)) {
      (:final time, :final later) => currentL10n.goMarginLateNext(formatClock(time), later),
      null => null,
    };

/// Walking to the ride: its next departure after the one aimed at that the user can still catch at their pace, and
/// how many minutes later it leaves; null when the departures don't say
({DateTime time, int later})? goNextCatchable(WidgetRef ref, GoState state, WalkMargin margin, DateTime now) {
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
  return (time: next.departure.time, later: next.departure.time.difference(margin.departure).roundedMinutes);
}

/// Minutes as Citymapper writes them on a walk: `< 1 min`, `3 min`
String goWalkMinutes(Duration duration) =>
    duration < const Duration(minutes: 1) ? currentL10n.goUnderAMinute : currentL10n.minutesShort((duration.inSeconds / 60).round());
