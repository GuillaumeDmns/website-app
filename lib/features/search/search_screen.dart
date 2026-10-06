import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/line_badge.dart';
import '../favorites/favorites_controller.dart';
import '../journey/journey_preferences.dart';
import '../journey/journey_request.dart';
import 'recent_searches.dart';

/// Results of a query (keyed by the query, so that stacked search pages don't share them)
final _searchResultsProvider = FutureProvider.autoDispose.family<SearchResult, String>(
  (ref, query) => ref.watch(mobilityApiProvider).search(query),
);

/// Unified search. With [pickTitle] it chooses a journey start or end and pops a [JourneyPlace].
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.pickTitle, this.allowCurrentLocation = true});

  final String? pickTitle;

  /// Offer "Ma position" when picking (not for saving a favorite: it moves)
  final bool allowCurrentLocation;

  bool get isPicking => pickTitle != null;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _query = value.trim());
      }
    });
    setState(() {});
  }

  /// What happens when a place is chosen, from the results, the favorites or the recent searches
  void _openPlace(PlaceResult place) {
    ref.read(recentSearchesProvider.notifier).add(RecentSearch.place(place));
    _openJourneyPlace(JourneyPlace.fromPlace(place), stopAreaId: place.type == PlaceType.stopArea ? place.id : null);
  }

  void _openJourneyPlace(JourneyPlace place, {String? stopAreaId}) {
    if (widget.isPicking) {
      context.pop(place);
    } else if (stopAreaId != null) {
      context.push(Routes.stop(stopAreaId));
    } else {
      // An address or a place: go there, like Citymapper
      context.push(Routes.journey(
          ref.read(journeyPreferencesProvider).apply(JourneyRequest(from: const JourneyPlace.currentLocation(), to: place))));
    }
  }

  void _openLine(LineSummary line) {
    ref.read(recentSearchesProvider.notifier).add(RecentSearch.line(line));
    context.push(Routes.line(line.id));
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.length >= 2;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
          child: Row(
            children: [
              IconButton(tooltip: 'Retour', icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: widget.isPicking ? '${widget.pickTitle} : arrêt, adresse, lieu…' : 'Arrêt, adresse, lieu, ligne…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Effacer',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _controller.clear();
                              _debounce?.cancel();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: searching
              ? AsyncView(
                  value: ref.watch(_searchResultsProvider(_query)),
                  onRetry: () => ref.invalidate(_searchResultsProvider(_query)),
                  data: (result) => result.lines.isEmpty && result.places.isEmpty
                      ? const Padding(padding: EdgeInsets.all(24), child: Text('Aucun résultat'))
                      : _Results(result: result, isPicking: widget.isPicking, onPlace: _openPlace, onLine: _openLine),
                )
              : _Suggestions(
                  isPicking: widget.isPicking,
                  allowCurrentLocation: widget.allowCurrentLocation,
                  onCurrentLocation: () => context.pop(const JourneyPlace.currentLocation()),
                  onFavorite: (favorite) => _openJourneyPlace(favoritePlace(favorite)),
                  onPlace: _openPlace,
                  onLine: _openLine,
                ),
        ),
      ],
    );
  }
}

/// Before typing: "Ma position" (picking), saved places, recent searches
class _Suggestions extends ConsumerWidget {
  const _Suggestions({
    required this.isPicking,
    required this.allowCurrentLocation,
    required this.onCurrentLocation,
    required this.onFavorite,
    required this.onPlace,
    required this.onLine,
  });

  final bool isPicking;
  final bool allowCurrentLocation;
  final VoidCallback onCurrentLocation;
  final ValueChanged<Favorite> onFavorite;
  final ValueChanged<PlaceResult> onPlace;
  final ValueChanged<LineSummary> onLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final places = (ref.watch(favoritesProvider).value ?? const <Favorite>[])
        .where((favorite) => favorite.kind == FavoriteKind.home || favorite.kind == FavoriteKind.work || favorite.kind == FavoriteKind.place)
        .toList()
      ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
    final recents = (ref.watch(recentSearchesProvider).value ?? const <RecentSearch>[])
        .where((recent) => !isPicking || recent.place != null)
        .toList();

    return ListView(
      controller: PanelScrollScope.of(context),
      // The last results stay reachable above the keyboard
      padding: EdgeInsets.only(bottom: 24 + MediaQuery.viewInsetsOf(context).bottom),
      children: [
        if (isPicking && allowCurrentLocation)
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.my_location)),
            title: const Text('Ma position'),
            onTap: onCurrentLocation,
          ),
        for (final favorite in places)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.amber.withValues(alpha: 0.2),
              foregroundColor: Colors.amber.shade800,
              child: Icon(switch (favorite.kind) {
                FavoriteKind.home => Icons.home_outlined,
                FavoriteKind.work => Icons.work_outline,
                _ => Icons.star_outline,
              }),
            ),
            title: Text(switch (favorite.kind) {
              FavoriteKind.home => 'Maison',
              FavoriteKind.work => 'Travail',
              _ => favorite.label ?? '',
            }),
            subtitle: favorite.kind == FavoriteKind.place ? null : Text(favorite.label ?? ''),
            onTap: () => onFavorite(favorite),
          ),
        if (recents.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(child: Text('Récents', style: theme.textTheme.titleSmall)),
                TextButton(
                  onPressed: () => ref.read(recentSearchesProvider.notifier).clear(),
                  child: const Text('Effacer'),
                ),
              ],
            ),
          ),
          for (final recent in recents)
            if (recent.place case final place?)
              _PlaceTile(place: place, isPicking: isPicking, onTap: () => onPlace(place), icon: Icons.history)
            else if (recent.line case final line?)
              ListTile(
                leading: SizedBox(width: 40, child: Center(child: LineBadge(line, size: 28))),
                title: Text('${line.mode.label} ${line.name ?? ''}'),
                onTap: () => onLine(line),
              ),
        ],
        if (!isPicking && places.isEmpty && recents.isEmpty) const _Hint(),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Exemples : « Châtelet », « 10 rue de Rivoli », « Tour Eiffel », « RER B », « 38 »',
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.result, required this.isPicking, required this.onPlace, required this.onLine});

  final SearchResult result;
  final bool isPicking;
  final ValueChanged<PlaceResult> onPlace;
  final ValueChanged<LineSummary> onLine;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: PanelScrollScope.of(context),
      // The last results stay reachable above the keyboard
      padding: EdgeInsets.only(bottom: 24 + MediaQuery.viewInsetsOf(context).bottom),
      children: [
        if (result.lines.isNotEmpty && !isPicking)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final line in result.lines)
                  ActionChip(
                    avatar: LineBadge(line, size: 22),
                    label: Text(line.mode.label),
                    onPressed: () => onLine(line),
                  ),
              ],
            ),
          ),
        for (final place in result.places) _PlaceTile(place: place, isPicking: isPicking, onTap: () => onPlace(place)),
      ],
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({required this.place, required this.isPicking, required this.onTap, this.icon});

  final PlaceResult place;
  final bool isPicking;
  final VoidCallback onTap;

  /// Overrides the type icon (e.g. history for recent searches)
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final typeIcon = switch (place.type) {
      PlaceType.stopArea => Icons.directions_transit,
      PlaceType.address => Icons.place_outlined,
      PlaceType.poi => Icons.star_outline,
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurfaceVariant,
        child: Icon(icon ?? typeIcon),
      ),
      title: Text(place.name),
      subtitle: place.lines.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [for (final line in place.lines.take(12)) LineBadge(line, size: 18)],
              ),
            ),
      onTap: onTap,
      trailing: isPicking || place.type == PlaceType.stopArea
          ? null
          : IconButton(
              tooltip: 'Départs autour',
              icon: const Icon(Icons.departure_board),
              onPressed: () => context.push(Routes.around(place.lat, place.lon, place.name)),
            ),
    );
  }
}
