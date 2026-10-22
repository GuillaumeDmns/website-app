import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/api/models.dart';
import '../../core/map/map_overlay.dart';
import '../../core/widgets/line_badge.dart';
import '../../l10n/l10n.dart';
import 'go_controller.dart';
import 'go_glance.dart';
import 'go_instruction.dart';
import 'go_state.dart';
import 'go_tracker.dart';

/// Floating bar over the map while a journey is followed: on the other pages, the current instruction (tap to open GO);
/// on the GO page, the moment at a glance in large ([GoBanner]), the latest alert under it for a few seconds.
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
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GoBanner(glance: goGlance(state, now), urgentAlert: alert?.urgent ?? false),
          if (alert != null) ...[const SizedBox(height: 8), _AlertStrip(alert: alert)],
        ],
      );
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

/// GO's instruction over the map, like a navigation app: the context small, what to do in large, the figure that counts
/// down on the right, then where. Green while all is well, orange when it needs attention, red to act now.
class GoBanner extends StatelessWidget {
  const GoBanner({super.key, required this.glance, this.urgentAlert = false});

  final GoGlance glance;

  /// An urgent alert was just given: red whatever the moment
  final bool urgentAlert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final tone = urgentAlert ? GoTone.urgent : glance.tone;
    final background = switch (tone) {
      GoTone.ok => theme.colorScheme.primary,
      GoTone.warn => colors.warning,
      GoTone.urgent => colors.cancelled,
    };
    final foreground = tone == GoTone.ok ? theme.colorScheme.onPrimary : Colors.white;
    final soft = foreground.withValues(alpha: 0.85);
    final line = glance.line;

    return Semantics(
      liveRegion: true,
      container: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x38000000), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (line != null)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        // The ring follows the badge's IDFM shape
                        borderRadius: BorderRadius.circular(switch (line.mode) {
                          TransportMode.metro => 20,
                          TransportMode.rer || TransportMode.transilien || TransportMode.ter => 10,
                          _ => 3,
                        }),
                        boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.85), spreadRadius: 2)],
                      ),
                      child: LineBadge(line, size: 40),
                    )
                  else if (glance.icon != null)
                    Icon(glance.icon, size: 40, color: foreground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (glance.kicker.isNotEmpty)
                          Text(glance.kicker,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(color: soft, height: 1.25)),
                        const SizedBox(height: 2),
                        Text(
                          glance.action,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(color: foreground, height: 1.15),
                        ),
                      ],
                    ),
                  ),
                  if (glance.hero case final hero?) ...[
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(hero,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(color: foreground, fontSize: 32, height: 1, letterSpacing: -1, fontFeatures: const [FontFeature.tabularFigures()])),
                        if (glance.heroUnit case final unit?)
                          Text(unit, style: theme.textTheme.labelMedium?.copyWith(color: soft, height: 1.3)),
                      ],
                    ),
                  ],
                ],
              ),
              if (glance.place case final place? when place.isNotEmpty) ...[
                Container(height: 1, margin: const EdgeInsets.fromLTRB(0, 11, 0, 9), color: foreground.withValues(alpha: 0.22)),
                Text(place, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: foreground, height: 1.3)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
