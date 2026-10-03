import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/widgets/line_badge.dart';
import '../journey/journey_request.dart';
import '../stops/stop_screen.dart';
import '../stops/widgets/stop_departures_card.dart';
import 'favorites_controller.dart';

/// Runs a favorite change and shows its error, if any, in a snackbar
Future<void> runFavoriteAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (success != null) {
      messenger.showSnackBar(SnackBar(content: Text(success)));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Favori non enregistré : $e')));
  }
}

/// Star toggling a stop area in the favorites
class FavoriteStopButton extends ConsumerWidget {
  const FavoriteStopButton({super.key, required this.stopAreaId});

  final String stopAreaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(favoritesProvider);
    final saved = ref.read(favoritesProvider.notifier).stopFavorite(stopAreaId) != null;
    return IconButton(
      tooltip: saved ? 'Retirer des favoris' : 'Ajouter aux favoris',
      icon: Icon(saved ? Icons.star : Icons.star_border, color: saved ? Colors.amber.shade600 : null),
      onPressed: () => runFavoriteAction(context, () => ref.read(favoritesProvider.notifier).toggleStop(stopAreaId)),
    );
  }
}

/// Star toggling a line in the favorites
class FavoriteLineButton extends ConsumerWidget {
  const FavoriteLineButton({super.key, required this.lineId});

  final String lineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(favoritesProvider);
    final saved = ref.read(favoritesProvider.notifier).lineFavorite(lineId) != null;
    return IconButton(
      tooltip: saved ? 'Retirer des favoris' : 'Ajouter aux favoris',
      icon: Icon(saved ? Icons.star : Icons.star_border, color: saved ? Colors.amber.shade600 : null),
      onPressed: () => runFavoriteAction(context, () => ref.read(favoritesProvider.notifier).toggleLine(lineId)),
    );
  }
}

/// Lets the user choose an address or a stop to save as [kind] (no "Ma position": it moves)
Future<void> chooseFavoritePlace(BuildContext context, WidgetRef ref, FavoriteKind kind) async {
  final title = switch (kind) {
    FavoriteKind.home => 'Maison',
    FavoriteKind.work => 'Travail',
    _ => 'Lieu favori',
  };
  final place = await context.push<JourneyPlace>(Routes.pickPlace(title, allowCurrentLocation: false));
  if (place == null || !context.mounted) {
    return;
  }
  await runFavoriteAction(context, () => ref.read(favoritesProvider.notifier).savePlace(kind, place), success: '$title enregistré');
}

/// Home, work and saved places as shortcuts: tap to go there, long press (or the menu) to change them.
class FavoriteShortcuts extends ConsumerWidget {
  const FavoriteShortcuts({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider).value ?? const <Favorite>[];
    Favorite? find(FavoriteKind kind) => favorites.where((favorite) => favorite.kind == kind).firstOrNull;
    final places = favorites.where((favorite) => favorite.kind == FavoriteKind.place);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _PlaceShortcut(kind: FavoriteKind.home, icon: Icons.home_outlined, title: 'Maison', favorite: find(FavoriteKind.home)),
          const SizedBox(width: 8),
          _PlaceShortcut(kind: FavoriteKind.work, icon: Icons.work_outline, title: 'Travail', favorite: find(FavoriteKind.work)),
          for (final place in places) ...[
            const SizedBox(width: 8),
            _PlaceShortcut(kind: FavoriteKind.place, icon: Icons.star_outline, title: place.label ?? '', favorite: place),
          ],
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Lieu'),
            tooltip: 'Ajouter un lieu favori',
            onPressed: () => chooseFavoritePlace(context, ref, FavoriteKind.place),
          ),
        ],
      ),
    );
  }
}

class _PlaceShortcut extends ConsumerWidget {
  const _PlaceShortcut({required this.kind, required this.icon, required this.title, required this.favorite});

  final FavoriteKind kind;
  final IconData icon;
  final String title;
  final Favorite? favorite;

  void _go(BuildContext context) => context.push(Routes.journey(JourneyRequest(
        from: const JourneyPlace.currentLocation(),
        to: favoritePlace(favorite!),
      )));

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(favorite!.label ?? title), subtitle: Text(title)),
            if (kind != FavoriteKind.place)
              ListTile(
                leading: const Icon(Icons.edit_location_alt_outlined),
                title: const Text('Modifier l\'adresse'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Supprimer'),
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
    if (favorite == null) {
      return ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text('Ajouter $title'),
        onPressed: () => chooseFavoritePlace(context, ref, kind),
      );
    }
    return GestureDetector(
      onLongPress: () => _edit(context, ref),
      onSecondaryTap: () => _edit(context, ref),
      child: InputChip(
        avatar: Icon(icon, size: 18),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(title, overflow: TextOverflow.ellipsis),
        ),
        tooltip: favorite!.label,
        onPressed: () => _go(context),
        deleteIcon: const Icon(Icons.more_vert, size: 18),
        deleteButtonTooltipMessage: 'Modifier',
        onDeleted: () => _edit(context, ref),
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
        Text('Mes arrêts', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
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

/// Favorite lines as badges
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mes lignes', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final line in lines)
              Tooltip(
                message: '${line.mode.label} ${line.name ?? ''}',
                child: InkWell(onTap: () => context.push(Routes.line(line.id)), child: LineBadge(line, size: 34)),
              ),
          ],
        ),
      ],
    );
  }
}
