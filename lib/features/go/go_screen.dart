import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/models.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/line_badge.dart';
import '../journey/widgets/journey_map.dart';
import '../traffic/disruption_widgets.dart';
import '../traffic/traffic_providers.dart';
import 'go_controller.dart';
import 'go_instruction.dart';
import 'go_tracker.dart';

/// GO mode: what to do now, problems to solve, the journey's steps, and the map following the user.
class GoScreen extends ConsumerWidget {
  const GoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(goControllerProvider);
    // The GO state changes every 5 s at least: fresher than nowProvider
    final now = DateTime.now();
    final theme = Theme.of(context);

    void back() => context.canPop() ? context.pop() : context.go(Routes.home);

    if (state == null) {
      return ListView(
        controller: PanelScrollScope.of(context),
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
        children: [
          Align(alignment: Alignment.centerLeft, child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: back)),
          const Padding(padding: EdgeInsets.all(24), child: Text('Aucun trajet en cours')),
        ],
      );
    }

    final progress = state.progress;
    final step = state.tracker.stepOf(progress);
    final following = progress.phase == GoPhase.moving || progress.phase == GoPhase.onBoard;
    final controller = ref.read(goControllerProvider.notifier);
    final eta = state.tracker.eta(progress, state.currentVehicle);
    final late = eta.difference(state.journey.arrival).inMinutes;
    final arrived = progress.phase == GoPhase.arrived;

    return MapOverlayScope(
      overlay: journeyOverlay(
        context,
        state.journey,
        currentSection: arrived ? state.journey.sections.length : step?.sectionIndex ?? -1,
        currentAlong: following ? progress.along : 0,
        follow: state.position,
      ),
      child: ListView(
        controller: PanelScrollScope.of(context),
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
        children: [
          Row(
            children: [
              IconButton(tooltip: 'Retour', icon: const Icon(Icons.arrow_back), onPressed: back),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(arrived ? 'Trajet terminé' : 'Arrivée ${formatClock(eta)}',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    if (!arrived)
                      Text(
                        late >= 1
                            ? '+$late min sur l\'horaire prévu'
                            : late <= -1
                                ? '${-late} min d\'avance'
                                : 'À l\'heure',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: late >= 3 ? Colors.orange.shade700 : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (ref.watch(mapFollowPausedProvider) && state.position != null)
                IconButton(
                  tooltip: 'Recentrer',
                  icon: const Icon(Icons.my_location),
                  onPressed: () => ref.read(mapFollowPausedProvider.notifier).resume(),
                ),
              IconButton(
                tooltip: state.muted ? 'Activer le son des alertes' : 'Couper le son des alertes',
                icon: Icon(state.muted ? Icons.volume_off : Icons.volume_up),
                onPressed: controller.toggleMute,
              ),
              IconButton(
                tooltip: 'Terminer le trajet',
                icon: const Icon(Icons.close),
                onPressed: () => _confirmStop(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InstructionCard(
                  instruction: goInstruction(state, now),
                  onPrevious: progress.step > 0 || progress.phase != GoPhase.moving ? controller.previous : null,
                  onNext: arrived ? null : controller.next,
                ),
                if (progress.issue != null) _IssueCard(state: state, now: now),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                if (!arrived) _RouteDisruptions(state: state),
                const SizedBox(height: 12),
                if (arrived)
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () {
                      controller.stop();
                      context.go(Routes.home);
                    },
                    child: const Text('Terminer'),
                  ),
                for (final (index, goStep) in state.tracker.steps.indexed)
                  _StepTile(step: goStep, index: index, progress: progress),
              ],
            ),
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

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.instruction, this.onPrevious, this.onNext});

  final GoInstruction instruction;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = instruction.urgent ? scheme.errorContainer : scheme.primaryContainer;
    final foreground = instruction.urgent ? scheme.onErrorContainer : scheme.onPrimaryContainer;

    return Card(
      margin: EdgeInsets.zero,
      color: background,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 12),
                  child: instruction.line != null
                      ? LineBadge(instruction.line!, size: 34)
                      : Icon(instruction.icon, size: 32, color: foreground),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(instruction.title,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: foreground)),
                      if (instruction.subtitle != null)
                        Text(instruction.subtitle!,
                            style: theme.textTheme.titleSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
                      if (instruction.detail != null && instruction.detail!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(instruction.detail!, style: theme.textTheme.bodyMedium?.copyWith(color: foreground)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: foreground),
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left, size: 18),
                  label: const Text('Étape précédente'),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: foreground),
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text('Suivante'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Off route, missed or cancelled vehicle: next vehicles to take instead, recalculation
class _IssueCard extends ConsumerWidget {
  const _IssueCard({required this.state, required this.now});

  final GoState state;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(goControllerProvider.notifier);
    final issue = state.progress.issue!;
    final step = state.tracker.stepOf(state.progress);
    final line = step?.section.line;
    final lineLabel = '${line?.mode.label ?? ''} ${line?.name ?? ''}'.trim();
    final planned = step == null ? now : state.tracker.plannedDeparture(step, state.progress);
    final others = issue == GoIssue.offRoute || state.vehicleStep != state.progress.step
        ? const <Departure>[]
        : state.upcoming
            .where((departure) => !departure.cancelled && departure.time.isAfter(now) && departure.time.difference(planned).inSeconds > 60)
            .take(3)
            .toList();

    final (icon, title, text) = switch (issue) {
      GoIssue.offRoute => (Icons.wrong_location_outlined, 'Vous vous êtes écarté du trajet', 'Recalculez depuis votre position.'),
      GoIssue.missed => (Icons.running_with_errors, '$lineLabel manqué', 'Prenez le suivant ou recalculez.'),
      GoIssue.cancelled => (Icons.block, '$lineLabel supprimé', 'Prenez le suivant ou recalculez.'),
    };

    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: theme.colorScheme.tertiaryContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
              ],
            ),
            Padding(padding: const EdgeInsets.only(top: 4, left: 32), child: Text(text)),
            if (others.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 32),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final departure in others)
                      ActionChip(
                        avatar: Icon(departure.realtime ? Icons.rss_feed : Icons.schedule, size: 16),
                        label: Text('Prendre celui de ${formatClock(departure.time)}'),
                        onPressed: () => controller.takeVehicle(departure),
                      ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: controller.dismissIssue, child: const Text('Ignorer')),
                TextButton.icon(
                  onPressed: state.recalculating ? null : controller.recalculate,
                  icon: state.recalculating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.alt_route, size: 18),
                  label: const Text('Recalculer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Active disruptions of the lines still to ride
class _RouteDisruptions extends ConsumerWidget {
  const _RouteDisruptions({required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lineIds = {
      for (final step in state.tracker.steps.skip(state.progress.step))
        if (step.isRide && (step.section.line?.id ?? '').isNotEmpty) step.section.line!.id,
    };
    final disruptions = [
      for (final lineId in lineIds)
        ...(ref.watch(lineDisruptionsProvider(lineId)).value ?? const <Disruption>[])
            .where((disruption) => disruption.active && disruption.severity != DisruptionSeverity.info)
            .take(2),
    ];
    if (disruptions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final disruption in disruptions) DisruptionLine(disruption: disruption)],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step, required this.index, required this.progress});

  final GoStep step;
  final int index;
  final GoProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = index < progress.step;
    final current = index == progress.step && progress.phase != GoPhase.arrived;
    final muted = theme.colorScheme.onSurfaceVariant;
    final section = step.section;
    // The shift (later vehicle, delay) only applies from the current step on
    final time = (step.isRide ? section.departure : section.arrival).add(done ? Duration.zero : progress.shift);

    final Widget leading = done
        ? Icon(Icons.check_circle, size: 22, color: Colors.green.shade600)
        : step.isRide && section.line != null
            ? LineBadge(section.line!, size: 24)
            : Icon(section.kind == SectionKind.bike ? Icons.pedal_bike : Icons.directions_walk,
                size: 22, color: current ? theme.colorScheme.primary : muted);

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: current
          ? BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10))
          : null,
      child: Row(
        children: [
          SizedBox(width: 32, child: Center(child: leading)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              goStepLabel(step),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: done ? muted : null,
                fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Text(formatClock(time), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );
  }
}
