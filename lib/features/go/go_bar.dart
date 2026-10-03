import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/map/map_overlay.dart';
import '../../core/widgets/line_badge.dart';
import 'go_controller.dart';
import 'go_instruction.dart';

/// Floating bar over the map while a journey is followed: the current instruction (tap to open GO) on the other
/// pages, and the latest alert for a few seconds everywhere.
class GoBar extends ConsumerWidget {
  const GoBar({super.key});

  static const _alertDuration = Duration(seconds: 20);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(goControllerProvider);
    if (state == null) {
      return const SizedBox.shrink();
    }
    // The GO state changes every 5 s at least: fresher than nowProvider
    final now = DateTime.now();
    final onGoPage = ref.watch(routerLocationProvider).startsWith(Routes.go);
    final alert = state.alert != null && state.alertAt != null && now.difference(state.alertAt!) < _alertDuration
        ? state.alert
        : null;
    if (onGoPage && alert == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final instruction = goInstruction(state, now);
    final urgent = alert?.urgent ?? instruction.urgent;
    final background = alert != null ? (urgent ? scheme.error : scheme.inverseSurface) : scheme.primaryContainer;
    final foreground = alert != null ? (urgent ? scheme.onError : scheme.onInverseSurface) : scheme.onPrimaryContainer;

    return Material(
      color: background,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onGoPage ? null : () => context.push(Routes.go),
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
                        style: theme.textTheme.titleSmall?.copyWith(color: foreground, fontWeight: FontWeight.w800)),
                    if ((alert?.body ?? instruction.subtitle) case final text?)
                      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: foreground)),
                  ],
                ),
              ),
              if (!onGoPage)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: foreground, borderRadius: BorderRadius.circular(10)),
                  child: Text('GO', style: TextStyle(color: background, fontWeight: FontWeight.w900)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
