import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/colors.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/line_badge.dart';
import '../../core/widgets/size_reporter.dart';
import '../../l10n/l10n.dart';
import '../journey/journey_providers.dart';
import '../journey/journey_retime.dart';
import 'go_controller.dart';
import 'go_guidance.dart';
import 'go_instruction.dart';
import 'go_tracker.dart';

/// Floating bar over the map while a journey is followed. On the GO page, Citymapper's big instruction banner: what to
/// do now in large, in green on foot, in the line's color on a ride, red when it's time to act; with the time to spare
/// walking to a ride and the GPS state under it. On the other pages, the current instruction (tap to open GO). The
/// latest alert shows for a few seconds everywhere.
class GoBar extends ConsumerWidget {
  const GoBar({super.key});

  static const _alertDuration = Duration(seconds: 20);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(goControllerProvider);
    final onGoPage = ref.watch(routerLocationProvider).startsWith(Routes.go);
    if (state == null) {
      return const SizedBox.shrink();
    }
    // The GO state changes every 5 s at least: fresher than nowProvider
    final now = DateTime.now();
    final alert = state.alert != null && state.alertAt != null && now.difference(state.alertAt!) < _alertDuration
        ? state.alert
        : null;
    if (onGoPage) {
      // The map frames what it shows below the banner
      return _TopInset(child: _Banner(state: state, alert: alert, now: now));
    }
    return _Compact(state: state, alert: alert, now: now);
  }
}

/// Tells the map how much of its top [child] hides (the banner and its pills), and nothing once gone
class _TopInset extends ConsumerStatefulWidget {
  const _TopInset({required this.child});

  final Widget child;

  @override
  ConsumerState<_TopInset> createState() => _TopInsetState();
}

class _TopInsetState extends ConsumerState<_TopInset> {
  late final _inset = ref.read(mapTopInsetProvider.notifier);

  @override
  void dispose() {
    // Not while the tree builds
    Future.microtask(() => _inset.set(0));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeReporter(onSize: (size) => _inset.set(size.height + 8), child: widget.child);
}

class _Compact extends StatelessWidget {
  const _Compact({required this.state, required this.alert, required this.now});

  final GoState state;
  final GoAlert? alert;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final instruction = goInstruction(state, now);
    final alert = this.alert;
    final urgent = alert?.urgent ?? instruction.urgent;
    final background = alert != null ? (urgent ? scheme.error : scheme.inverseSurface) : scheme.primaryContainer;
    final foreground = alert != null ? (urgent ? scheme.onError : scheme.onInverseSurface) : scheme.onPrimaryContainer;

    return Material(
      color: background,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.go),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              if (alert != null)
                Icon(urgent ? Icons.notifications_active : Icons.notifications, color: foreground)
              else if (instruction.line != null)
                LineBadge(instruction.line!, size: 28)
              else
                Icon(instruction.icon, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(alert?.title ?? instruction.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
                    if ((alert?.body ?? instruction.subtitle) case final text?)
                      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: foreground)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: foreground, borderRadius: BorderRadius.circular(10)),
                child: Text(context.l10n.go, style: TextStyle(color: background, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The big instruction of the GO page, then the pills (time to spare, GPS) and the latest alert
class _Banner extends ConsumerWidget {
  const _Banner({required this.state, required this.alert, required this.now});

  final GoState state;
  final GoAlert? alert;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = state.progress;
    final instruction = goInstruction(state, now);
    final line = instruction.line;
    final onRide = line != null && progress.phase != GoPhase.arrived;
    final (background, foreground) = instruction.urgent
        ? (scheme.error, scheme.onError)
        : onRide
            ? (parseHexColor(line.color, scheme.primary), parseHexColor(line.textColor, Colors.white))
            : (AppTheme.brand, Colors.white);
    final step = state.tracker.stepOf(progress);
    final waiting = progress.phase == GoPhase.waiting && step != null;
    final countdown = waiting ? state.tracker.expectedDeparture(step, progress, state.currentVehicle).difference(now) : null;
    final margin = walkMargin(state, now);
    final noGps = progress.phase != GoPhase.arrived && state.tracker.followsSchedule(progress, now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: background,
          elevation: 6,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 12),
                  child: line != null && onRide
                      ? Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                          child: LineBadge(line, size: 34),
                        )
                      : Icon(instruction.icon, size: 40, color: foreground),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        instruction.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600, height: 1.15),
                      ),
                      if (instruction.subtitle case final subtitle?)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(color: foreground)),
                        ),
                      if (instruction.detail case final detail? when detail.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(color: foreground.withValues(alpha: 0.85))),
                        ),
                    ],
                  ),
                ),
                if (countdown != null) _Countdown(until: countdown, color: foreground),
              ],
            ),
          ),
        ),
        if (margin != null || noGps || alert != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (margin != null) _MarginPill(state: state, margin: margin, now: now),
                if (noGps) _Pill(icon: Icons.gps_off, text: context.l10n.goNoGps, color: scheme.inverseSurface, textColor: scheme.onInverseSurface),
              ],
            ),
          ),
        if (alert case final alert?)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: alert.urgent ? scheme.error : scheme.inverseSurface,
              borderRadius: BorderRadius.circular(14),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(alert.urgent ? Icons.notifications_active : Icons.notifications,
                        size: 20, color: alert.urgent ? scheme.onError : scheme.onInverseSurface),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [alert.title, ?alert.body].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: alert.urgent ? scheme.onError : scheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Minutes until the vehicle leaves, large, with a ring emptying over the last ten minutes
class _Countdown extends StatelessWidget {
  const _Countdown({required this.until, required this.color});

  final Duration until;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Like the departure lists: whole minutes left, "now" within 30 s
    final minutes = until.inSeconds <= 30 ? 0 : (until.inSeconds ~/ 60).clamp(1, 999);
    final theme = Theme.of(context);
    return SizedBox.square(
      dimension: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: (until.inSeconds / 600).clamp(0.0, 1.0),
              strokeWidth: 4,
              color: color,
              backgroundColor: color.withValues(alpha: 0.25),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                minutes <= 0 ? context.l10n.now : '$minutes',
                style: (minutes <= 0 ? theme.textTheme.labelLarge : theme.textTheme.headlineSmall)
                    ?.copyWith(color: color, fontWeight: FontWeight.w600, height: 1),
              ),
              if (minutes > 0) Text(context.l10n.minutesUnit, style: theme.textTheme.labelSmall?.copyWith(color: color, height: 1)),
            ],
          ),
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
    final later = (next.departure.time.difference(margin.departure).inSeconds / 60).round();
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
  Widget build(BuildContext context) => Material(
        color: color,
        elevation: 3,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
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
