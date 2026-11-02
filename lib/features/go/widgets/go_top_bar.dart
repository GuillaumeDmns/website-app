import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/utils/time_format.dart';
import '../../../l10n/l10n.dart';
import '../go_controller.dart';
import '../go_state.dart';
import '../go_tracker.dart';

/// GO's controls over the map, like Citymapper's: back, the minutes left and the arrival time in a pill (orange when
/// late), finishing; the alerts' sound and keeping the screen on under them. What to do now is in the cards.
class GoTopBar extends ConsumerWidget {
  const GoTopBar({super.key, required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(goControllerProvider.notifier);
    final router = GoRouter.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _RoundButton(
              icon: Icons.arrow_back,
              tooltip: context.l10n.back,
              onPressed: () => router.canPop() ? router.pop() : router.go(Routes.home),
            ),
            Expanded(child: Center(child: _TimePill(state: state))),
            _RoundButton(
              icon: Icons.close,
              tooltip: context.l10n.goStop,
              color: Theme.of(context).colorScheme.error,
              onPressed: () => confirmGoStop(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundButton(
                icon: state.muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
                tooltip: state.muted ? context.l10n.goUnmute : context.l10n.goMute,
                onPressed: controller.toggleMute,
              ),
              const SizedBox(height: 10),
              _RoundButton(
                icon: state.keepAwake ? Icons.light_mode : Icons.light_mode_outlined,
                tooltip: state.keepAwake ? context.l10n.goLetScreenSleep : context.l10n.goKeepScreenOn,
                color: state.keepAwake ? AppTheme.brand : null,
                onPressed: controller.toggleKeepAwake,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `36 min / 20:55`: what is left and when the user arrives, the arrival orange from 3 min late
class _TimePill extends StatelessWidget {
  const _TimePill({required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final arrived = state.progress.phase == GoPhase.arrived;
    final eta = state.tracker.eta(state.progress, state.currentVehicle);
    final late = eta.difference(state.journey.arrival).inMinutes;
    final left = math.max(0, (eta.difference(DateTime.now()).inSeconds / 60).ceil());
    final figure = theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.1, fontFeatures: const [FontFeature.tabularFigures()]);
    return Material(
      color: colors.card,
      elevation: 4,
      shadowColor: Colors.black38,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: arrived
            ? Text(context.l10n.goFinished, style: theme.textTheme.titleMedium)
            : Semantics(
                label: context.l10n.goTimeLeftAndArrival(left, formatClock(eta)),
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$left', style: figure),
                    Text(' ${context.l10n.minutesUnit}', style: theme.textTheme.labelLarge?.copyWith(color: colors.muted)),
                    Text('  /  ', style: theme.textTheme.titleLarge?.copyWith(color: colors.muted)),
                    Text(formatClock(eta), style: figure?.copyWith(color: late >= 3 ? colors.warning : null)),
                  ],
                ),
              ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onPressed, this.color});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => Material(
        color: context.colors.card,
        elevation: 4,
        shadowColor: Colors.black38,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          padding: const EdgeInsets.all(10),
          icon: Icon(icon, size: 24, color: color ?? Theme.of(context).colorScheme.onSurface),
          onPressed: onPressed,
        ),
      );
}

/// "Terminer le trajet ?": GO stops, back home
Future<void> confirmGoStop(BuildContext context, WidgetRef ref) async {
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
