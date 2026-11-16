import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/routes.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/departure_time.dart';
import '../../core/widgets/line_badge.dart';
import '../../l10n/l10n.dart';
import '../go/go_controller.dart';
import 'departure_follow.dart';

/// What a long press on a departure of a stop's page does: offers to follow it, where that is possible (Android, no
/// journey followed in GO: one live notification) and it hasn't left nor been cancelled; null otherwise
VoidCallback? followDepartureAction(
  BuildContext context,
  WidgetRef ref, {
  required StopAreaSummary stop,
  required LineSummary line,
  required String destination,
  required Departure? departure,
}) {
  if (departure == null || departure.cancelled || !ref.watch(departureFollowAvailableProvider) ||
      ref.watch(goControllerProvider.select((state) => state != null))) {
    return null;
  }
  return () => showFollowDepartureSheet(
        context,
        FollowedDeparture(stopAreaId: stop.id, stopName: stop.name, line: line, destination: destination, departure: departure),
      );
}

/// The departure, and "Suivre ce départ"
Future<void> showFollowDepartureSheet(BuildContext context, FollowedDeparture departure) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    // Above the whole app, not inside the panel or the bottom sheet
    useRootNavigator: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  LineBadge(departure.line, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(departure.destination, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          context.l10n.followAt(departure.stopName, formatClock(departure.departure.time)),
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(context.l10n.followDepartureHint, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              Consumer(
                builder: (context, ref, _) => FilledButton.icon(
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(context.l10n.followDeparture),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ref.read(departureFollowProvider.notifier).follow(departure);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Floating bar over the map while a departure is followed: its line, where it goes and leaves from, the time left,
/// and "Arrêter"; a tap opens its stop
class FollowBar extends ConsumerWidget {
  const FollowBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followed = ref.watch(departureFollowProvider);
    if (followed == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    return Material(
      color: scheme.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.stop(followed.stopAreaId)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: [
              LineBadge(followed.line, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(followed.destination,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text(followed.stopName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DepartureTime(followed.departure, now: now, mode: followed.line.mode, emphasized: true),
              TextButton(
                onPressed: ref.read(departureFollowProvider.notifier).stop,
                child: Text(context.l10n.followStop),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
