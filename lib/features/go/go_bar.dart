import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/map/map_overlay.dart';
import '../../core/widgets/line_badge.dart';
import '../../l10n/l10n.dart';
import 'go_controller.dart';
import 'go_instruction.dart';
import 'go_tracker.dart';

/// Floating bar over the map while a journey is followed: on the other pages, the current instruction (tap to open GO);
/// on the GO page, whose sheet tells what to do, nothing but the latest alert for a few seconds, leaving the map free.
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
      return alert == null ? const SizedBox.shrink() : _AlertStrip(alert: alert);
    }
    return _Compact(state: state, alert: alert, now: now);
  }
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

/// The latest alert on the GO page, on one or two lines
class _AlertStrip extends StatelessWidget {
  const _AlertStrip({required this.alert});

  final GoAlert alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = alert.urgent ? scheme.onError : scheme.onInverseSurface;
    return Material(
      color: alert.urgent ? scheme.error : scheme.inverseSurface,
      borderRadius: BorderRadius.circular(14),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Icon(alert.urgent ? Icons.notifications_active : Icons.notifications, size: 20, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [alert.title, ?alert.body].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
