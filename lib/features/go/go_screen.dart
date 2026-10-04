import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/models.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/text.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/line_badge.dart';
import '../journey/journey_providers.dart';
import '../journey/widgets/journey_map.dart';
import '../traffic/disruption_widgets.dart';
import '../traffic/traffic_providers.dart';
import 'go_controller.dart';
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
            child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: back),
          ),
          const Padding(padding: EdgeInsets.all(24), child: Text('Aucun trajet en cours')),
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
          _Header(state: state, onBack: back),
          if (progress.issue != null) _IssueBanner(state: state),
          Expanded(
            // Swipe with a mouse or a trackpad too (desktop, web)
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              child: PageView.builder(
                controller: _pages,
                itemCount: pageCount,
                onPageChanged: (page) => setState(() => _shown = page),
                itemBuilder: (context, page) {
                  final Widget card = page < tracker.steps.length
                      ? _StepCard(state: state, index: page)
                      : _ArrivalCard(state: state);
                  return SingleChildScrollView(
                    // The bottom sheet is dragged by the list of the page shown only
                    controller: page == _shown ? PanelScrollScope.of(context) : null,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: card,
                  );
                },
              ),
            ),
          ),
          _Dots(count: pageCount, shown: _shown, live: live, onTap: _show),
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
          IconButton(tooltip: 'Retour', icon: const Icon(Icons.arrow_back), onPressed: onBack),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: arrived ? 'Trajet terminé' : 'Arrivée ${formatClock(eta)}'),
                  if (!arrived && late.abs() >= 1)
                    TextSpan(
                      text: late > 0 ? '  +$late min' : '  $late min',
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
            tooltip: state.muted ? 'Activer le son des alertes' : 'Couper le son des alertes',
            icon: Icon(state.muted ? Icons.volume_off_outlined : Icons.volume_up_outlined),
            onPressed: controller.toggleMute,
          ),
          IconButton(
            tooltip: 'Terminer le trajet',
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
        title: const Text('Terminer le trajet ?'),
        content: const Text('Le guidage et les alertes s\'arrêtent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Continuer')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Terminer')),
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
      GoIssue.offRoute => 'Vous vous êtes écarté du trajet',
      GoIssue.missed => '$lineLabel manqué : choisissez un autre passage',
      GoIssue.cancelled => '$lineLabel supprimé : choisissez un autre passage',
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
              : TextButton(onPressed: controller.recalculate, child: const Text('Recalculer')),
          IconButton(tooltip: 'Ignorer', icon: const Icon(Icons.close, size: 18), onPressed: controller.dismissIssue),
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
        title = left <= 1 ? 'Descendez au prochain arrêt' : 'Descendez dans $left arrêts';
        detail = ['à ${section.to?.name ?? ''}', if (left > 1 && nextStop != null) 'prochain : $nextStop'].join(' · ');
      } else {
        final stopCount = math.max(0, section.stops.length - 1);
        title = '$lineLabel → ${section.headsign ?? ''}';
        detail =
            'De ${section.from?.name ?? ''} à ${section.to?.name ?? ''}'
            '${stopCount > 0 ? ' · $stopCount arrêt${stopCount > 1 ? 's' : ''}' : ''}';
      }
    } else {
      final verb = switch (section.kind) {
        SectionKind.bike => 'Pédalez',
        SectionKind.car => 'Roulez',
        SectionKind.transfer => 'Correspondance',
        _ => 'Marchez',
      };
      title = section.kind == SectionKind.transfer
          ? 'Correspondance vers ${section.to?.name ?? ''}'
          : '$verb jusqu\'à ${section.to?.name ?? ''}';
      if (isLive) {
        // Away from the path: at least the straight distance to the end
        final end = step.end;
        final position = state.position;
        final meters = math.max(
          tracker.metersLeft(progress),
          end == null || position == null ? 0.0 : metersBetween(position, end),
        );
        detail = '${formatDistance(meters.round())} · ${math.max(1, (meters / 1.2 / 60).ceil())} min';
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
          _Departures(state: state, step: step, index: index, selectable: isLive),
          if (positions.isNotEmpty && positions.length < 3)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Montez ${positions.map(_position).join(' ou ')}',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
        ],
        if (step.isRide && !isDone) _LineDisruption(lineId: section.line?.id),
        const SizedBox(height: 8),
        // Manual corrections, kept discreet
        if (isLive && progress.phase == GoPhase.waiting)
          _SmallAction(label: 'Je suis à bord', onPressed: () => ref.read(goControllerProvider.notifier).next())
        else if (!isLive)
          _SmallAction(
            label: 'Je suis à cette étape',
            onPressed: () => ref.read(goControllerProvider.notifier).jumpTo(index),
          ),
      ],
    );
  }

  static String _position(String position) => switch (position) {
    'front' => 'à l\'avant',
    'middle' => 'au milieu',
    'back' => 'à l\'arrière',
    _ => position,
  };
}

/// Next departures of the ride's line towards its direction; the one followed is highlighted. On the step in
/// progress, choosing another one makes it the followed one.
class _Departures extends ConsumerWidget {
  const _Departures({required this.state, required this.step, required this.index, required this.selectable});

  final GoState state;
  final GoStep step;
  final int index;
  final bool selectable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final section = step.section;
    final stopAreaId = section.from?.stopAreaId;
    final lineId = section.line?.id ?? '';
    final planned = state.tracker.plannedDeparture(step, state.progress);
    final now = DateTime.now();

    final departures = stopAreaId == null || lineId.isEmpty
        ? null
        : ref.watch(rideDeparturesProvider((stopAreaId: stopAreaId, lineId: lineId))).value;
    final rows =
        departures?.lines.where((row) => row.line.id == lineId && row.departures.isNotEmpty).toList() ?? const [];
    final matching = rows.where((row) => sameDestination(row.destination, section.headsign ?? '')).toList();
    final list =
        ((matching.isNotEmpty ? matching : rows).expand((row) => row.departures).toList()
              ..sort((a, b) => a.time.compareTo(b.time)))
            .where((departure) => departure.time.isAfter(now.subtract(const Duration(minutes: 1))))
            .take(5)
            .toList();

    if (list.isEmpty) {
      return Text('Départ prévu à ${formatClock(planned)}', style: theme.textTheme.titleMedium);
    }

    // The followed vehicle: closest scheduled time to the planned one
    Departure? followed;
    var bestGap = const Duration(minutes: 4);
    for (final departure in list) {
      final gap = (departure.aimedTime ?? departure.time).difference(planned).abs();
      if (gap <= bestGap) {
        bestGap = gap;
        followed = departure;
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final departure in list)
          _DepartureChip(
            departure: departure,
            now: now,
            selected: departure == followed,
            onTap: selectable && departure != followed && !departure.cancelled
                ? () => ref.read(goControllerProvider.notifier).takeVehicle(departure)
                : null,
          ),
      ],
    );
  }
}

class _DepartureChip extends StatelessWidget {
  const _DepartureChip({required this.departure, required this.now, required this.selected, this.onTap});

  final Departure departure;
  final DateTime now;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? scheme.onPrimary
        : departure.realtime
        ? Colors.green.shade700
        : scheme.onSurface;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (departure.realtime && !departure.cancelled) ...[
                Icon(Icons.rss_feed, size: 13, color: foreground),
                const SizedBox(width: 4),
              ],
              Text(
                departureLabel(departure, now),
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  decoration: departure.cancelled ? TextDecoration.lineThrough : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
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
                    arrived ? 'Vous êtes arrivé' : 'Arrivée',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text('$destination · ${formatClock(eta)}', style: theme.textTheme.bodyLarge?.copyWith(color: muted)),
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
            child: const Text('Terminer'),
          )
        else
          _SmallAction(
            label: 'Je suis arrivé',
            onPressed: () => ref.read(goControllerProvider.notifier).jumpTo(state.tracker.steps.length),
          ),
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
      padding: const EdgeInsets.only(top: 4, bottom: 12),
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
