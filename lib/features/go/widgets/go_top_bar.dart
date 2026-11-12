import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/utils/time_format.dart';
import '../../../l10n/l10n.dart';
import '../go_controller.dart';
import '../go_state.dart';
import '../go_tracker.dart';

typedef _Control = ({IconData icon, String tooltip, Color? color, VoidCallback onPressed});

/// GO's controls, the same over the map ([GoTopBar]) and in the side panel ([GoPanelHeader]): back, finishing, the
/// alerts' sound, keeping the screen on
({_Control back, _Control stop, _Control mute, _Control keepAwake}) _controls(BuildContext context, WidgetRef ref, GoState state) {
  final controller = ref.read(goControllerProvider.notifier);
  final router = GoRouter.of(context);
  final l10n = context.l10n;
  return (
    back: (icon: Icons.arrow_back, tooltip: l10n.back, color: null, onPressed: () => router.canPop() ? router.pop() : router.go(Routes.home)),
    stop: (icon: Icons.close, tooltip: l10n.goStop, color: Theme.of(context).colorScheme.error, onPressed: () => confirmGoStop(context, ref)),
    mute: (
      icon: state.muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
      tooltip: state.muted ? l10n.goUnmute : l10n.goMute,
      color: null,
      onPressed: controller.toggleMute,
    ),
    keepAwake: (
      icon: state.keepAwake ? Icons.light_mode : Icons.light_mode_outlined,
      tooltip: state.keepAwake ? l10n.goLetScreenSleep : l10n.goKeepScreenOn,
      color: state.keepAwake ? AppTheme.brand : null,
      onPressed: controller.toggleKeepAwake,
    ),
  );
}

/// GO's controls over the map, like Citymapper's: back, the minutes left and the arrival time in a pill (orange when
/// late), finishing; the alerts' sound and keeping the screen on under them. What to do now is in the cards. A phone's
/// (narrow layout): on a wide screen they are in the side panel's header ([GoPanelHeader]).
class GoTopBar extends ConsumerWidget {
  const GoTopBar({super.key, required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controls = _controls(context, ref, state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _RoundButton(controls.back),
            Expanded(child: Center(child: _TimePill(state: state))),
            _RoundButton(controls.stop),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundButton(controls.mute),
              const SizedBox(height: 10),
              _RoundButton(controls.keepAwake),
            ],
          ),
        ),
      ],
    );
  }
}

/// GO's controls on a wide screen (web, desktop, tablet): the side panel's header, like the other pages' (back, the
/// essentials, the actions), over GO's cards; the map is left clear
class GoPanelHeader extends ConsumerWidget {
  const GoPanelHeader({super.key, required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controls = _controls(context, ref, state);
    Widget button(_Control control) => IconButton(
          tooltip: control.tooltip,
          icon: Icon(control.icon, color: control.color),
          onPressed: control.onPressed,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          button(controls.back),
          const SizedBox(width: 4),
          Expanded(
            child: Align(alignment: AlignmentDirectional.centerStart, child: _TimeLeft(state: state)),
          ),
          button(controls.mute),
          button(controls.keepAwake),
          button(controls.stop),
        ],
      ),
    );
  }
}

/// `36 min / 20:55` in a pill over the map
class _TimePill extends StatelessWidget {
  const _TimePill({required this.state});

  final GoState state;

  @override
  Widget build(BuildContext context) => Material(
        color: context.colors.card,
        elevation: 4,
        shadowColor: Colors.black38,
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          child: _TimeLeft(state: state),
        ),
      );
}

/// `36 min / 20:55`: what is left and when the user arrives, the arrival orange from 3 min late
class _TimeLeft extends StatelessWidget {
  const _TimeLeft({required this.state});

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
    if (arrived) {
      return Text(context.l10n.goFinished, style: theme.textTheme.titleMedium);
    }
    return Semantics(
      label: context.l10n.goTimeLeftAndArrival(left, formatClock(eta)),
      excludeSemantics: true,
      // Large text: smaller rather than over the buttons
      child: FittedBox(
        fit: BoxFit.scaleDown,
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
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton(this.control);

  final _Control control;

  @override
  Widget build(BuildContext context) => Material(
        color: context.colors.card,
        elevation: 4,
        shadowColor: Colors.black38,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: control.tooltip,
          padding: const EdgeInsets.all(10),
          icon: Icon(control.icon, size: 24, color: control.color ?? Theme.of(context).colorScheme.onSurface),
          onPressed: control.onPressed,
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
