import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../core/api/models.dart';
import '../../core/config.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/colors.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/line_badge.dart';
import '../../core/widgets/size_reporter.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/l10n.dart';
import '../daily_trips/daily_trip_widgets.dart';
import '../journey/journey_labels.dart';
import '../journey/journey_providers.dart';
import '../journey/journey_request.dart';
import '../journey/journey_retime.dart';
import '../journey/widgets/journey_card.dart';
import '../journey/widgets/journey_map.dart';
import '../journey/widgets/ride_departures.dart';
import '../traffic/disruption_widgets.dart';
import 'go_controller.dart';
import 'go_guidance.dart';
import 'go_instruction.dart';
import 'go_tracker.dart';

/// GO mode, like Citymapper: in the panel the arrival with the journey's progress, the strip of its steps (tap one to
/// look at it) and one card per step, swiped horizontally, the one in progress telling what to do now (the next turn,
/// the time to spare, the countdown to the departure). The panel stays low, the map above it free: the page follows
/// the step in progress; the map frames the step shown (on a ride, what is left of it) or follows the user on foot.
class GoScreen extends ConsumerStatefulWidget {
  const GoScreen({super.key});

  @override
  ConsumerState<GoScreen> createState() => _GoScreenState();
}

class _GoScreenState extends ConsumerState<GoScreen> {
  PageController? _pages;

  /// Page shown (a step index, or `steps.length` for the arrival)
  int _shown = 0;

  /// Step in progress when the page last followed it
  int? _followed;

  /// Heights of the parts of the page, to fit the bottom sheet to the card shown
  double _top = 0;
  final _cards = <int, double>{};
  bool _newCard = true;

  void _fitSheet() {
    final card = _cards[_shown];
    if (card == null || !mounted) {
      return;
    }
    PanelSheetScope.fitContent(context, _top + card + MediaQuery.paddingOf(context).bottom, reset: _newCard);
    _newCard = false;
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  void _show(int page) =>
      _pages?.animateToPage(page, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(goControllerProvider);
    void back() => context.canPop() ? context.pop() : context.go(Routes.home);

    if (state == null) {
      // The session closed itself after the arrival: back home
      if (_pages != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.go(Routes.home);
          }
        });
      }
      return ListView(
        controller: PanelScrollScope.of(context),
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(tooltip: context.l10n.back, icon: const Icon(Icons.arrow_back), onPressed: back),
          ),
          Padding(padding: const EdgeInsets.all(24), child: Text(context.l10n.goNoJourney)),
        ],
      );
    }

    final tracker = state.tracker;
    final progress = state.progress;
    final arrived = progress.phase == GoPhase.arrived;
    final live = arrived ? tracker.steps.length : progress.step;
    final pageCount = tracker.steps.length + 1;

    // A new step in progress: show it
    if (_pages == null) {
      _shown = live;
      _followed = live;
      _pages = PageController(initialPage: live);
    } else if (_followed != live) {
      _followed = live;
      WidgetsBinding.instance.addPostFrameCallback((_) => _show(live));
    }

    return MapOverlayScope(
      overlay: _overlay(state, live),
      child: Column(
        children: [
          SizeReporter(
            onSize: (size) {
              _top = size.height;
              _fitSheet();
            },
            child: Column(
              children: [
                _Header(state: state, onBack: back),
                _JourneyProgress(state: state),
                if (AppConfig.isDev) const _GpsStats(),
                _StepStrip(state: state, shown: _shown, onTap: _show),
                if (progress.issue case final issue? when issue != GoIssue.offRoute) _IssueCard(state: state, issue: issue),
                if (progress.issue == GoIssue.offRoute) _OffRouteBanner(state: state),
              ],
            ),
          ),
          Expanded(
            // Swipe with a mouse or a trackpad too (desktop, web)
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              child: PageView.builder(
                controller: _pages,
                itemCount: pageCount,
                onPageChanged: (page) {
                  setState(() => _shown = page);
                  _newCard = true;
                  _fitSheet();
                },
                itemBuilder: (context, page) {
                  final Widget card = page >= tracker.steps.length
                      ? _ArrivalCard(state: state)
                      : tracker.steps[page].isRide
                          ? _RideCard(state: state, index: page)
                          : _MoveCard(state: state, index: page);
                  return SingleChildScrollView(
                    // The bottom sheet is dragged by the list of the page shown only
                    controller: page == _shown ? PanelScrollScope.of(context) : null,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: SizeReporter(
                      onSize: (size) {
                        _cards[page] = size.height + 16;
                        if (page == _shown) {
                          _fitSheet();
                        }
                      },
                      child: card,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The journey on the map, framing the step shown; on the ride in progress, what is left of it (from the last stop
  /// passed to where to get off), the next stop marked
  MapOverlay _overlay(GoState state, int live) {
    final tracker = state.tracker;
    final progress = state.progress;
    final arrived = progress.phase == GoPhase.arrived;
    final shownStep = _shown < tracker.steps.length ? tracker.steps[_shown] : null;
    final onBoardOrMoving = progress.phase == GoPhase.moving || progress.phase == GoPhase.onBoard;
    final overlay = journeyOverlay(
      context,
      state.journey,
      currentSection: arrived ? state.journey.sections.length : tracker.stepOf(progress)?.sectionIndex ?? -1,
      currentAlong: onBoardOrMoving ? progress.along : 0,
      fitSection: shownStep?.sectionIndex,
    );
    final step = tracker.stepOf(progress);
    if (step != null && progress.phase == GoPhase.onBoard && _shown == live) {
      final stops = step.section.stops;
      final left = [
        for (var k = math.min(progress.stopIndex, stops.length - 1); k < stops.length; k++) LatLng(stops[k].lat, stops[k].lon),
      ];
      final next = progress.stopIndex + 1 < stops.length ? stops[progress.stopIndex + 1] : null;
      final color = parseHexColor(step.section.line?.color, Theme.of(context).colorScheme.primary);
      return MapOverlay(
        pins: [
          ...overlay.pins,
          if (next != null)
            MapPin(point: LatLng(next.lat, next.lon), color: color, size: 18, label: next.name, above: false),
        ],
        paths: overlay.paths,
        fit: left.length >= 2 ? left : overlay.fit,
      );
    }
    return overlay.withFollow(goFollow(state, _shown));
  }
}

/// How the fixes come (development builds): is the device's GPS giving one a second?
class _GpsStats extends ConsumerWidget {
  const _GpsStats();

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

/// The arrival, in how long and against the plan; screen, sound and stop
class _Header extends ConsumerWidget {
  const _Header({required this.state, required this.onBack});

  final GoState state;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(goControllerProvider.notifier);
    final arrived = state.progress.phase == GoPhase.arrived;
    final now = DateTime.now();
    final eta = state.tracker.eta(state.progress, state.currentVehicle);
    final late = eta.difference(state.journey.arrival).inMinutes;
    final left = eta.difference(now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          IconButton(tooltip: context.l10n.back, icon: const Icon(Icons.arrow_back), onPressed: onBack),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: arrived ? context.l10n.goFinished : context.l10n.goArrival(formatClock(eta))),
                      if (!arrived && late.abs() >= 1)
                        TextSpan(
                          text: '  ${late > 0 ? '+' : ''}${context.l10n.minutesShort(late)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: late >= 3 ? context.colors.warning : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (!arrived && left > Duration.zero)
                  Text(context.l10n.goArrivesIn(formatDuration(left.inSeconds)),
                      style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
              ],
            ),
          ),
          IconButton(
            tooltip: state.keepAwake ? context.l10n.goLetScreenSleep : context.l10n.goKeepScreenOn,
            isSelected: state.keepAwake,
            icon: const Icon(Icons.light_mode_outlined),
            selectedIcon: const Icon(Icons.light_mode),
            onPressed: controller.toggleKeepAwake,
          ),
          IconButton(
            tooltip: state.muted ? context.l10n.goUnmute : context.l10n.goMute,
            icon: Icon(state.muted ? Icons.volume_off_outlined : Icons.volume_up_outlined),
            onPressed: controller.toggleMute,
          ),
          IconButton(
            tooltip: context.l10n.goStop,
            icon: const Icon(Icons.close),
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

/// A thin bar: the share of the journey done
class _JourneyProgress extends StatelessWidget {
  const _JourneyProgress({required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: journeyFraction(state),
            minHeight: 4,
            color: AppTheme.brand,
            backgroundColor: context.colors.subtle,
          ),
        ),
      );
}

/// The steps of the journey in a row, like the journey results (walks with their minutes, rides with their line):
/// the one in progress outlined, the one shown filled, the ones done faded with a check. Tap one to look at it.
class _StepStrip extends StatelessWidget {
  const _StepStrip({required this.state, required this.shown, required this.onTap});

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

    Widget item(int index, Widget child, String label) {
      final done = index < live;
      return Semantics(
        button: true,
        label: label,
        selected: index == shown,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: index == shown ? theme.colorScheme.primary.withValues(alpha: 0.14) : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: index == live && index != shown ? theme.colorScheme.primary : Colors.transparent, width: 1.5),
            ),
            child: Opacity(
              opacity: done ? 0.45 : 1,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                child,
                if (done) Padding(padding: const EdgeInsets.only(left: 2), child: Icon(Icons.check, size: 14, color: colors.live)),
              ]),
            ),
          ),
        ),
      );
    }

    final items = <Widget>[];
    for (final (index, step) in steps.indexed) {
      final section = step.section;
      if (items.isNotEmpty) {
        items.add(Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.outline));
      }
      items.add(step.isRide && section.line != null
          ? item(index, LineBadge(section.line!, size: 24), section.line!.label)
          : item(index, MoveMinutes(section: section), context.l10n.goVerbTo(context.l10n.goVerbWalk, section.to?.name ?? '')));
    }
    items
      ..add(Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.outline))
      ..add(item(steps.length, Icon(Icons.flag, size: 20, color: theme.colorScheme.error), context.l10n.goArrivalTitle));

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        children: [Row(children: items)],
      ),
    );
  }
}

/// Off the way for a while: one line, with the recalculation
class _OffRouteBanner extends ConsumerWidget {
  const _OffRouteBanner({required this.state});

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
class _IssueCard extends ConsumerWidget {
  const _IssueCard({required this.state, required this.issue});

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

/// Title row of a card: the line badge or the move's icon, a few words in large, one detail line
class _CardTitle extends StatelessWidget {
  const _CardTitle({
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

/// A move on foot or by bike. In progress: what to do now (the next turn, else where to go), how far, the time to
/// spare; the turns folded under it so that the panel stays low. Otherwise where to, how long and its turns. Then what
/// comes next.
class _MoveCard extends ConsumerWidget {
  const _MoveCard({required this.state, required this.index});

  final GoState state;
  final int index;

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
          _CardTitle(
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
          _GoPills(state: state, now: now),
        ],
      );
    } else {
      title = _CardTitle(
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
        title,
        // The turns: folded while walking (the next one is the title), open on a step looked at
        if (turns.length > 1) _Turns(initiallyExpanded: !isLive, children: turns),
        if (!isDone && index + 1 < tracker.steps.length) _NextStep(state: state, index: index + 1),
        const SizedBox(height: 8),
        if (!isDone && index != progress.step)
          _SmallAction(label: context.l10n.goImAtThisStep, onPressed: () => ref.read(goControllerProvider.notifier).jumpTo(index)),
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

/// A ride: waiting for it (countdown, where to board, departures, the next one if missed), on board
/// (the stops left with their times, where to get off), or to come (its departures)
class _RideCard extends ConsumerWidget {
  const _RideCard({required this.state, required this.index});

  final GoState state;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracker = state.tracker;
    final progress = state.progress;
    final step = tracker.steps[index];
    final section = step.section;
    final isLive = index == progress.step && progress.phase != GoPhase.arrived;
    final isDone = index < progress.step || progress.phase == GoPhase.arrived;
    final onBoard = isLive && progress.phase == GoPhase.onBoard;
    final lineLabel = section.line?.label ?? '';
    final stopCount = math.max(0, section.stops.length - 1);

    final String title;
    final String detail;
    var urgent = false;
    if (onBoard) {
      final left = tracker.stopsLeft(progress);
      urgent = left <= 1;
      title = left <= 1 ? context.l10n.goGetOffNext : context.l10n.goGetOffIn(left);
      detail = context.l10n.goAtStop(section.to?.name ?? '');
    } else {
      title = '$lineLabel → ${section.headsign ?? ''}';
      detail = [
        context.l10n.goFromTo(section.from?.name ?? '', section.to?.name ?? ''),
        if (stopCount > 0) context.l10n.stopsCount(stopCount),
      ].join(' · ');
    }
    final positions = section.boardingPositions;
    final now = DateTime.now();
    final waiting = isLive && progress.phase == GoPhase.waiting;
    final countdown = waiting ? tracker.expectedDeparture(step, progress, state.currentVehicle).difference(now) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardTitle(
          leading: section.line != null ? LineBadge(section.line!, size: 36) : const Icon(Icons.directions_transit, size: 34),
          title: title,
          detail: detail,
          trailing: countdown == null
              ? null
              : _Countdown(
                  until: countdown,
                  color: countdown <= const Duration(minutes: 1) ? Theme.of(context).colorScheme.error : AppTheme.brand,
                ),
          done: isDone,
          urgent: urgent,
        ),
        if (waiting) _GoPills(state: state, now: now),
        if (onBoard) ...[
          const SizedBox(height: 12),
          _StopsLeft(state: state, step: step),
        ] else if (!isDone) ...[
          if (positions.isNotEmpty && positions.length < 3) ...[
            const SizedBox(height: 12),
            TrainPositions(positions: positions, color: parseHexColor(section.line?.color, Theme.of(context).colorScheme.primary)),
          ],
          const SizedBox(height: 14),
          _Departures(state: state, step: step, index: index),
        ],
        if (!isDone) RideDisruptions(lineId: section.line?.id, max: 1, top: 10),
        if (!isDone && index + 1 < tracker.steps.length) _NextStep(state: state, index: index + 1),
        const SizedBox(height: 8),
        // Manual corrections, kept discreet
        if (isLive && progress.phase == GoPhase.waiting)
          _SmallAction(label: context.l10n.goImOnBoard, onPressed: () => ref.read(goControllerProvider.notifier).next())
        else if (!isLive && !isDone)
          _SmallAction(label: context.l10n.goImAtThisStep, onPressed: () => ref.read(goControllerProvider.notifier).jumpTo(index)),
      ],
    );
  }
}

/// Where to board along the train: its cars from the front, the ones to board highlighted
class TrainPositions extends StatelessWidget {
  const TrainPositions({super.key, required this.positions, required this.color});

  /// `front`, `middle`, `back`
  final List<String> positions;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.colors.subtle;
    bool boarded(int car) => switch (car) {
          0 || 1 => positions.contains('front'),
          2 => positions.contains('middle'),
          _ => positions.contains('back'),
        };
    return Semantics(
      label: boardingLabel(positions),
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(Icons.arrow_back, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          for (var car = 0; car < 5; car++)
            Expanded(
              child: Container(
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: boarded(car) ? color : muted,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(car == 0 ? 9 : 3),
                    right: const Radius.circular(3),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 10),
          Text(boardingLabel(positions),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// On board: the stops left with their times, a dot on the next one, where to get off marked
class _StopsLeft extends StatelessWidget {
  const _StopsLeft({required this.state, required this.step});

  final GoState state;
  final GoStep step;

  /// More stops left than this: the ones in between folded
  static const _maxShown = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = state.progress;
    final stops = step.section.stops;
    final color = parseHexColor(step.section.line?.color, theme.colorScheme.primary);
    final first = math.min(progress.stopIndex + 1, stops.length - 1);
    final indexes = [for (var k = first; k < stops.length; k++) k];
    final folded = indexes.length > _maxShown ? indexes.length - (_maxShown - 1) : 0;
    final shown = folded == 0 ? indexes : [...indexes.take(_maxShown - 2), -1, indexes.last];

    return Column(
      children: [
        for (final (row, k) in shown.indexed)
          if (k < 0)
            _StopRow(color: color, name: context.l10n.stopsCount(folded), time: null, first: false, last: false, folded: true)
          else
            _StopRow(
              color: color,
              name: stops[k].name,
              // Where to get off: the ride's arrival (a stop's time is its departure)
              time: (k == stops.length - 1 ? step.section.arrival : step.stopTime(k)).add(progress.shift),
              first: row == 0,
              last: k == stops.length - 1,
            ),
      ],
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.color, required this.name, required this.time, required this.first, required this.last, this.folded = false});

  final Color color;
  final String name;
  final DateTime? time;

  /// The next stop
  final bool first;

  /// Where to get off
  final bool last;
  final bool folded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emphasis = first || last;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(time == null ? '' : formatClock(time!),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: emphasis ? FontWeight.w600 : null)),
            ),
          ),
          SizedBox(
            width: 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(children: [
                  Expanded(child: Container(width: 5, color: color)),
                  Expanded(child: Container(width: 5, color: last ? Colors.transparent : color)),
                ]),
                if (!folded)
                  Container(
                    width: emphasis ? 16 : 10,
                    height: emphasis ? 16 : 10,
                    decoration: BoxDecoration(
                      color: last ? color : context.colors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: folded
                          ? theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)
                          : (emphasis ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium),
                    ),
                  ),
                  if (first && !last) ...[
                    const SizedBox(width: 8),
                    PillTag(text: context.l10n.goNextStopLabel, color: theme.colorScheme.primary),
                  ],
                  if (last) ...[
                    const SizedBox(width: 8),
                    PillTag(text: context.l10n.goGetOffHere, color: theme.colorScheme.error),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What comes after this step: the next ride (line, direction, departure, platform) or the walk to the destination
class _NextStep extends StatelessWidget {
  const _NextStep({required this.state, required this.index});

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

/// Departures of the ride's line stopping where it gets off, from when the traveller gets to its stop, with their
/// times at both stops; the one followed is highlighted, and the next one told in case it is missed. Choosing another
/// one moves the journey to it.
class _Departures extends ConsumerWidget {
  const _Departures({required this.state, required this.step, required this.index});

  final GoState state;
  final GoStep step;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = state.progress;
    final planned = state.tracker.plannedDeparture(step, progress);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    // At the stop already for the step in progress; else after the steps before it
    final earliest = index == progress.step ? now : earliestBoarding(state.journey, step.sectionIndex, now).add(progress.shift);
    final key = rideKey(step.section, earliest, now);

    final rides = key == null
        ? const <Ride>[]
        : (ref.watch(rideOptionsProvider(key)).value ?? const <Ride>[])
              .where((ride) => ride.departure.time.isAfter(now.subtract(const Duration(minutes: 1))))
              .toList();

    if (rides.isEmpty) {
      return Text(context.l10n.goPlannedDeparture(formatClock(planned)), style: theme.textTheme.titleMedium);
    }
    final selected = plannedRide(rides, planned);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RideDepartureList(
          rides: rides,
          now: now,
          selected: selected,
          earliest: earliest,
          onSelect: (ride) => ref.read(goControllerProvider.notifier).choose(index, ride),
          onAllDepartures: () => context.push(Routes.stop(key!.from)),
        ),
        IfMissedLine(rides: rides, taken: selected),
      ],
    );
  }
}

/// The arrival: the summary, then the way back, saving the trip, finishing (it closes itself after a while)
class _ArrivalCard extends ConsumerWidget {
  const _ArrivalCard({required this.state});

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
          _SmallAction(
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

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.label, required this.onPressed});

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
class _GoPills extends StatelessWidget {
  const _GoPills({required this.state, required this.now});

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

/// Minutes until the vehicle leaves, large, with a ring emptying over the last ten minutes
class _Countdown extends StatelessWidget {
  const _Countdown({required this.until, required this.color});

  final Duration until;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Like the departure lists: whole minutes left, "now" within 30 s
    final minutes = math.min(minutesLeft(until), 999);
    final theme = Theme.of(context);
    return SizedBox.square(
      dimension: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: (until.inSeconds / 600).clamp(0.0, 1.0),
              strokeWidth: 4,
              color: color,
              backgroundColor: color.withValues(alpha: 0.2),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                minutes <= 0 ? context.l10n.now : '$minutes',
                style: (minutes <= 0 ? theme.textTheme.labelLarge : theme.textTheme.titleLarge)
                    ?.copyWith(color: color, fontWeight: FontWeight.w700, height: 1),
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

/// On foot or by bike, the map follows the user with the way ahead up, like Citymapper: a view from above makes
/// little sense when walking. Where the device has a compass, the map turns with it instead (the phone in the hand
/// turns, the map turns). Only for the move in progress, when it is the step shown.
MapFollow? goFollow(GoState state, int shownStep) {
  final progress = state.progress;
  final position = state.position;
  final step = state.tracker.stepOf(progress);
  if (position == null || step == null || step.isRide || progress.phase != GoPhase.moving || shownStep != progress.step) {
    return null;
  }
  return MapFollow(position: position, bearing: step.headingFrom(position, progress.along), compass: true);
}
