import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/line_badge.dart';
import '../../core/widgets/size_reporter.dart';
import '../../l10n/l10n.dart';
import '../journey/journey_providers.dart';
import '../journey/journey_retime.dart';
import '../journey/widgets/journey_map.dart';
import '../journey/widgets/ride_departures.dart';
import '../traffic/disruption_widgets.dart';
import '../traffic/traffic_providers.dart';
import 'go_controller.dart';
import 'go_instruction.dart';
import 'go_tracker.dart';

/// GO mode, like Citymapper: one card per step, swiped horizontally, dots telling where you are. The page follows
/// the step in progress; the map frames the step shown.
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
  double _bottom = 0;
  final _cards = <int, double>{};
  bool _newCard = true;

  void _fitSheet() {
    final card = _cards[_shown];
    if (card == null || !mounted) {
      return;
    }
    PanelSheetScope.fitContent(context, _top + card + _bottom, reset: _newCard);
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

    final shownStep = _shown < tracker.steps.length ? tracker.steps[_shown] : null;
    final onBoardOrMoving = progress.phase == GoPhase.moving || progress.phase == GoPhase.onBoard;

    return MapOverlayScope(
      overlay: journeyOverlay(
        context,
        state.journey,
        currentSection: arrived ? state.journey.sections.length : tracker.stepOf(progress)?.sectionIndex ?? -1,
        currentAlong: onBoardOrMoving ? progress.along : 0,
        fitSection: shownStep?.sectionIndex,
      ),
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
                if (progress.issue != null) _IssueBanner(state: state),
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
                  final Widget card = page < tracker.steps.length
                      ? _StepCard(state: state, index: page)
                      : _ArrivalCard(state: state);
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
          SizeReporter(
            onSize: (size) {
              _bottom = size.height;
              _fitSheet();
            },
            child: _Dots(count: pageCount, shown: _shown, live: live, onTap: _show),
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.state, required this.onBack});

  final GoState state;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(goControllerProvider.notifier);
    final arrived = state.progress.phase == GoPhase.arrived;
    final eta = state.tracker.eta(state.progress, state.currentVehicle);
    final late = eta.difference(state.journey.arrival).inMinutes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(tooltip: context.l10n.back, icon: const Icon(Icons.arrow_back), onPressed: onBack),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: arrived ? context.l10n.goFinished : context.l10n.goArrival(formatClock(eta))),
                  if (!arrived && late.abs() >= 1)
                    TextSpan(
                      text: '  ${late > 0 ? '+' : ''}${context.l10n.minutesShort(late)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: late >= 3 ? Colors.orange.shade700 : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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

/// Off route, missed or cancelled vehicle: one line, with the recalculation
class _IssueBanner extends ConsumerWidget {
  const _IssueBanner({required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(goControllerProvider.notifier);
    final line = state.tracker.stepOf(state.progress)?.section.line;
    final lineLabel = '${line?.mode.label ?? ''} ${line?.name ?? ''}'.trim();
    final text = switch (state.progress.issue!) {
      GoIssue.offRoute => context.l10n.goOffRoute,
      GoIssue.missed => context.l10n.goMissedChoose(lineLabel),
      GoIssue.cancelled => context.l10n.goCancelledChoose(lineLabel),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(color: theme.colorScheme.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
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

/// One step: a few words in big, one detail line, the departures for a ride
class _StepCard extends ConsumerWidget {
  const _StepCard({required this.state, required this.index});

  final GoState state;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final tracker = state.tracker;
    final progress = state.progress;
    final step = tracker.steps[index];
    final section = step.section;
    final isLive = index == progress.step && progress.phase != GoPhase.arrived;
    final isDone = index < progress.step || progress.phase == GoPhase.arrived;

    final String title;
    final String? detail;
    if (step.isRide) {
      final lineLabel = '${section.line?.mode.label ?? ''} ${section.line?.name ?? ''}'.trim();
      if (isLive && progress.phase == GoPhase.onBoard) {
        final left = tracker.stopsLeft(progress);
        final stops = section.stops;
        final nextStop = progress.stopIndex + 1 < stops.length ? stops[progress.stopIndex + 1].name : null;
        title = left <= 1 ? context.l10n.goGetOffNext : context.l10n.goGetOffIn(left);
        detail = [
          context.l10n.goAtStop(section.to?.name ?? ''),
          if (left > 1 && nextStop != null) context.l10n.goNextShort(nextStop),
        ].join(' · ');
      } else {
        final stopCount = math.max(0, section.stops.length - 1);
        title = '$lineLabel → ${section.headsign ?? ''}';
        detail = [
          context.l10n.goFromTo(section.from?.name ?? '', section.to?.name ?? ''),
          if (stopCount > 0) context.l10n.stopsCount(stopCount),
        ].join(' · ');
      }
    } else {
      final verb = switch (section.kind) {
        SectionKind.bike => context.l10n.goVerbBike,
        SectionKind.car => context.l10n.goVerbCar,
        SectionKind.transfer => context.l10n.goVerbTransfer,
        _ => context.l10n.goVerbWalk,
      };
      title = section.kind == SectionKind.transfer
          ? context.l10n.goTransferTo(section.to?.name ?? '')
          : context.l10n.goVerbTo(verb, section.to?.name ?? '');
      if (isLive) {
        // Away from the path: at least the straight distance to the end
        final end = step.end;
        final position = state.position;
        final meters = math.max(
          tracker.metersLeft(progress),
          end == null || position == null ? 0.0 : metersBetween(position, end),
        );
        detail = '${formatDistance(meters.round())} · ${context.l10n.minutesShort(math.max(1, (meters / 1.2 / 60).ceil()))}';
      } else {
        detail = [
          formatDuration(section.duration),
          if ((section.length ?? 0) > 0) formatDistance(section.length!),
        ].join(' · ');
      }
    }

    final urgent = isLive && progress.phase == GoPhase.onBoard && tracker.stopsLeft(progress) <= 1;
    final positions = section.boardingPositions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 12),
              child: step.isRide && section.line != null
                  ? LineBadge(section.line!, size: 36)
                  : Icon(
                      section.kind == SectionKind.bike ? Icons.pedal_bike : Icons.directions_walk,
                      size: 34,
                      color: isDone ? muted : theme.colorScheme.primary,
                    ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: urgent
                          ? theme.colorScheme.error
                          : isDone
                          ? muted
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(detail, style: theme.textTheme.bodyLarge?.copyWith(color: muted)),
                ],
              ),
            ),
            if (isDone) Icon(Icons.check_circle, color: Colors.green.shade600),
          ],
        ),
        if (step.isRide && !isDone && !(isLive && progress.phase == GoPhase.onBoard)) ...[
          const SizedBox(height: 14),
          _Departures(state: state, step: step, index: index),
          if (positions.isNotEmpty && positions.length < 3)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.l10n.boardAt(boardingPositions(positions)),
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
        ],
        if (step.isRide && !isDone) _LineDisruption(lineId: section.line?.id),
        const SizedBox(height: 8),
        // Manual corrections, kept discreet
        if (isLive && progress.phase == GoPhase.waiting)
          _SmallAction(label: context.l10n.goImOnBoard, onPressed: () => ref.read(goControllerProvider.notifier).next())
        else if (!isLive)
          _SmallAction(
            label: context.l10n.goImAtThisStep,
            onPressed: () => ref.read(goControllerProvider.notifier).jumpTo(index),
          ),
      ],
    );
  }
}

/// Departures of the ride's line stopping where it gets off, from when the traveller gets to its stop, with their
/// times at both stops; the one followed is highlighted. Choosing another one moves the journey to it.
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
    return RideDepartureList(
      rides: rides,
      now: now,
      selected: plannedRide(rides, planned),
      earliest: earliest,
      onSelect: (ride) => ref.read(goControllerProvider.notifier).choose(index, ride),
      onAllDepartures: () => context.push(Routes.stop(key!.from)),
    );
  }
}

/// The worst active disruption of the line, on one line
class _LineDisruption extends ConsumerWidget {
  const _LineDisruption({required this.lineId});

  final String? lineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (lineId == null || lineId!.isEmpty) {
      return const SizedBox.shrink();
    }
    final disruption = (ref.watch(lineDisruptionsProvider(lineId!)).value ?? const <Disruption>[])
        .where((disruption) => disruption.active && disruption.severity != DisruptionSeverity.info)
        .firstOrNull;
    return disruption == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: DisruptionLine(disruption: disruption),
          );
  }
}

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
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
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
          ],
        ),
        const SizedBox(height: 16),
        if (arrived)
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () {
              ref.read(goControllerProvider.notifier).stop();
              context.go(Routes.home);
            },
            child: Text(context.l10n.finish),
          )
        else
          _SmallAction(
            label: context.l10n.goImArrived,
            onPressed: () => ref.read(goControllerProvider.notifier).jumpTo(state.tracker.steps.length),
          ),
      ],
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
    final late = (arrivedAt.difference(state.plannedArrival).inSeconds / 60).round();
    final (label, color) = switch (late) {
      0 => (context.l10n.goOnTime, Colors.green.shade700),
      > 0 => (context.l10n.goMinutesLate(late), late >= 5 ? theme.colorScheme.error : Colors.orange.shade800),
      _ => (context.l10n.goMinutesEarly(-late), Colors.green.shade700),
    };
    final rides = state.journey.rides.length;
    Widget row(IconData icon, String text, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color ?? theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: color == null ? null : FontWeight.w700))),
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

/// One dot per step and one for the arrival: the page shown is long, done steps are faded, the step in progress
/// has a ring when another page is shown
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.shown, required this.live, required this.onTap});

  final int count;
  final int shown;
  final int live;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // Above the system navigation bar
      padding: EdgeInsets.only(top: 4, bottom: 12 + MediaQuery.paddingOf(context).bottom),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == shown ? 22 : 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: i == shown
                        ? scheme.primary
                        : i < live
                        ? scheme.outlineVariant
                        : scheme.outline,
                    borderRadius: BorderRadius.circular(5),
                    border: i == live && i != shown ? Border.all(color: scheme.primary, width: 2) : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
