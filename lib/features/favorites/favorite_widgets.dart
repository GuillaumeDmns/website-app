import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/widgets/line_badge.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/l10n.dart';
import '../daily_trips/daily_trip_widgets.dart';
import '../journey/journey_request.dart';
import '../stops/stop_screen.dart';
import '../traffic/traffic_providers.dart';
import '../stops/widgets/stop_departures_card.dart';
import 'favorites_controller.dart';
import '../../app/theme.dart';

/// Runs a favorite change and shows the result in a snackbar. The messenger is resolved before running the action:
/// the widget that started it may be gone when it ends.
Future<void> runFavoriteAction(BuildContext context, Future<void> Function() action, {String? success}) =>
    _runFavoriteAction(ScaffoldMessenger.of(context), action, success: success);

Future<void> _runFavoriteAction(ScaffoldMessengerState messenger, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null) {
      messenger.showSnackBar(SnackBar(content: Text(success)));
    }
  } catch (e, stackTrace) {
    debugPrint('Favorite action failed: $e\n$stackTrace');
    messenger.showSnackBar(SnackBar(content: Text(currentL10n.favoriteNotSaved('$e'))));
  }
}

/// Star toggling a stop area in the favorites (a guest's keeps the stop's name and lines on the device)
class FavoriteStopButton extends ConsumerWidget {
  const FavoriteStopButton({super.key, required this.stop});

  final StopAreaSummary stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(favoritesProvider);
    final saved = ref.read(favoritesProvider.notifier).stopFavorite(stop.id) != null;
    return IconButton(
      tooltip: saved ? context.l10n.favoriteRemove : context.l10n.favoriteAdd,
      icon: Icon(saved ? Icons.star : Icons.star_border, color: saved ? context.colors.warning : null),
      onPressed: () {
        HapticFeedback.lightImpact();
        runFavoriteAction(context, () => ref.read(favoritesProvider.notifier).toggleStop(stop));
      },
    );
  }
}

/// Star toggling a line in the favorites
class FavoriteLineButton extends ConsumerWidget {
  const FavoriteLineButton({super.key, required this.line});

  final LineSummary line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(favoritesProvider);
    final saved = ref.read(favoritesProvider.notifier).lineFavorite(line.id) != null;
    return IconButton(
      tooltip: saved ? context.l10n.favoriteRemove : context.l10n.favoriteAdd,
      icon: Icon(saved ? Icons.star : Icons.star_border, color: saved ? context.colors.warning : null),
      onPressed: () {
        HapticFeedback.lightImpact();
        runFavoriteAction(context, () => ref.read(favoritesProvider.notifier).toggleLine(line));
      },
    );
  }
}

/// Lets the user choose an address or a stop to save as [kind] (no "Ma position": it moves).
///
/// Everything needed after the choice is resolved before opening the search: the shortcut that called this can be
/// rebuilt or disposed while the search is shown, and saving does not depend on it.
Future<void> chooseFavoritePlace(BuildContext context, WidgetRef ref, FavoriteKind kind) async {
  final title = switch (kind) {
    FavoriteKind.home => context.l10n.home,
    FavoriteKind.work => context.l10n.work,
    _ => context.l10n.favoritePlace,
  };
  final favorites = ref.read(favoritesProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);

  final place = await router.push<JourneyPlace>(Routes.pickPlace(title, allowCurrentLocation: false));
  debugPrint('chooseFavoritePlace($kind): ${place?.param ?? 'cancelled'}');
  if (place == null) {
    return;
  }
  await _runFavoriteAction(messenger, () => favorites.savePlace(kind, place), success: currentL10n.favoriteSaved(title));
}

/// Home, work and saved places as pills, scrolled sideways: tap to go there, long press (or right click) to change
/// them. When to leave for home or work is told by the commute card above them (see `HomeScreen`).
class FavoriteShortcuts extends ConsumerWidget {
  const FavoriteShortcuts({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider).value ?? const <Favorite>[];
    Favorite? find(FavoriteKind kind) => favorites.where((favorite) => favorite.kind == kind).firstOrNull;
    final places = favorites.where((favorite) => favorite.kind == FavoriteKind.place);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _PlaceShortcut(kind: FavoriteKind.home, icon: Icons.home_rounded, title: context.l10n.home, favorite: find(FavoriteKind.home)),
          const SizedBox(width: 8),
          _PlaceShortcut(kind: FavoriteKind.work, icon: Icons.work_rounded, title: context.l10n.work, favorite: find(FavoriteKind.work)),
          for (final place in places) ...[
            const SizedBox(width: 8),
            _PlaceShortcut(kind: FavoriteKind.place, icon: Icons.star_rounded, title: place.label ?? '', favorite: place),
          ],
          const SizedBox(width: 8),
          Tooltip(
            message: context.l10n.favoritePlaceAdd,
            child: Material(
              color: Colors.transparent,
              shape: StadiumBorder(side: BorderSide(color: theme.colorScheme.outline)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => chooseFavoritePlace(context, ref, FavoriteKind.place),
                child: SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(14) + 26,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 18, color: context.colors.muted),
                        const SizedBox(width: 6),
                        Text(context.l10n.place, style: theme.textTheme.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: context.colors.muted)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill of the shortcuts: the place's icon in a tinted bubble, its name
class _ShortcutPill extends StatelessWidget {
  const _ShortcutPill({required this.icon, required this.title, required this.color, required this.onTap, this.onLongPress, this.tooltip, this.muted = false});

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;

  /// Not set yet
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pill = Material(
      color: context.colors.card,
      shape: StadiumBorder(side: BorderSide(color: theme.colorScheme.outline, width: 0.5)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        child: SizedBox(
          height: MediaQuery.textScalerOf(context).scale(14) + 26,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 14, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconBubble(icon, color: color, size: 28),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: muted ? context.colors.muted : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }
}

class _PlaceShortcut extends ConsumerWidget {
  const _PlaceShortcut({required this.kind, required this.icon, required this.title, required this.favorite});

  final FavoriteKind kind;
  final IconData icon;
  final String title;
  final Favorite? favorite;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      // Above the whole app, not inside the panel or the bottom sheet
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(favorite!.label ?? title, style: Theme.of(context).textTheme.titleSmall),
              subtitle: Text(title),
            ),
            if (kind != FavoriteKind.place)
              ListTile(
                leading: const Icon(Icons.edit_location_alt_outlined),
                title: Text(context.l10n.editAddress),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text(context.l10n.delete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) {
      return;
    }
    switch (action) {
      case 'edit':
        await chooseFavoritePlace(context, ref, kind);
      case 'delete':
        await runFavoriteAction(context, () => ref.read(favoritesProvider.notifier).remove(favorite!));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = switch (kind) {
      FavoriteKind.home => Theme.of(context).colorScheme.primary,
      FavoriteKind.work => Theme.of(context).colorScheme.secondary,
      _ => context.colors.warning,
    };
    if (favorite == null) {
      return _ShortcutPill(
        icon: icon,
        title: title,
        color: color,
        muted: true,
        tooltip: context.l10n.addPlace(title),
        onTap: () => chooseFavoritePlace(context, ref, kind),
      );
    }
    return Semantics(
      onLongPressHint: context.l10n.edit,
      child: _ShortcutPill(
        icon: icon,
        title: title,
        color: color,
        tooltip: favorite!.label,
        onTap: () => goToPlace(context, ref, favorite!),
        onLongPress: () => _edit(context, ref),
      ),
    );
  }
}

/// Real-time departures of the favorite stops
class FavoriteStopsSection extends ConsumerWidget {
  const FavoriteStopsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = (ref.watch(favoritesProvider).value ?? const <Favorite>[])
        .where((favorite) => favorite.kind == FavoriteKind.stop && favorite.stopAreaId != null)
        .toList();
    if (stops.isEmpty) {
      return const SizedBox.shrink();
    }
    final now = ref.watch(nowProvider).value ?? DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.l10n.myStops),
        for (final stop in stops)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: switch (ref.watch(stopDeparturesProvider(stop.stopAreaId!))) {
              AsyncValue(:final value?) => StopDeparturesCard(departures: value, now: now, maxRows: 4),
              AsyncValue(:final error?) => Card(
                  child: ListTile(
                    title: Text(stop.label ?? ''),
                    subtitle: Text(error.toString()),
                    onTap: () => context.push(Routes.stop(stop.stopAreaId!)),
                  ),
                ),
              _ => Card(child: ListTile(title: Text(stop.label ?? ''), trailing: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))),
            },
          ),
      ],
    );
  }
}

/// Favorite lines, one row each with its traffic: normal in green, disrupted in orange (or red when interrupted)
/// with the first disruption's title
class FavoriteLinesSection extends ConsumerWidget {
  const FavoriteLinesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = (ref.watch(favoritesProvider).value ?? const <Favorite>[])
        .where((favorite) => favorite.kind == FavoriteKind.line && favorite.line != null)
        .map((favorite) => favorite.line!)
        .toList();
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    final traffic = ref.watch(trafficProvider);
    final byLine = {for (final line in traffic.value ?? const <LineTraffic>[]) line.line.id: line};
    final theme = Theme.of(context);
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.l10n.myLines),
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
          child: Column(
            children: [
              for (final (index, line) in lines.indexed) ...[
                if (index > 0) const Divider(indent: 40),
                InkWell(
                  onTap: () => context.push(Routes.line(line.id)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        SizedBox(width: 40, child: Align(alignment: Alignment.centerLeft, child: LineBadge(line, size: 28))),
                        Expanded(
                          child: switch (byLine[line.id]) {
                            // Not known yet: nothing rather than a wrong "normal"
                            _ when !traffic.hasValue => Text(line.label, style: theme.textTheme.bodyMedium),
                            LineTraffic(severity: final severity?, :final titles) when severity != DisruptionSeverity.info =>
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _TrafficState(
                                    icon: severity == DisruptionSeverity.blocking ? Icons.block : Icons.warning_rounded,
                                    text: severity == DisruptionSeverity.blocking ? context.l10n.trafficInterrupted : context.l10n.trafficDisrupted,
                                    color: severity == DisruptionSeverity.blocking ? colors.cancelled : colors.warning,
                                  ),
                                  if (titles.isNotEmpty)
                                    Text(titles.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                                ],
                              ),
                            _ => _TrafficState(icon: Icons.check_circle, text: context.l10n.trafficNormal, color: colors.live),
                          },
                        ),
                        Icon(Icons.chevron_right, color: colors.muted),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TrafficState extends StatelessWidget {
  const _TrafficState({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14, color: color)),
          ),
        ],
      );
}
