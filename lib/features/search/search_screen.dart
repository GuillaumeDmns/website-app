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
import '../journey/journey_request.dart';

class _SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final _searchQueryProvider = NotifierProvider.autoDispose<_SearchQuery, String>(_SearchQuery.new);

final _searchResultsProvider = FutureProvider.autoDispose<SearchResult?>((ref) async {
  final query = ref.watch(_searchQueryProvider).trim();
  if (query.length < 2) {
    return null;
  }
  return ref.watch(mobilityApiProvider).search(query);
});

/// Unified search. With [pickTitle] it chooses a journey start or end and pops a [JourneyPlace].
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.pickTitle});

  final String? pickTitle;

  bool get isPicking => pickTitle != null;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => ref.read(_searchQueryProvider.notifier).set(value));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(_searchResultsProvider);

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
                              _onChanged('');
                            },
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.isPicking)
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.my_location)),
            title: const Text('Ma position'),
            onTap: () => context.pop(const JourneyPlace.currentLocation()),
          ),
        Expanded(
          child: AsyncView(
            value: results,
            onRetry: () => ref.invalidate(_searchResultsProvider),
            data: (result) => result == null
                ? (widget.isPicking ? const SizedBox.shrink() : const _Hint())
                : result.lines.isEmpty && result.places.isEmpty
                    ? const Padding(padding: EdgeInsets.all(24), child: Text('Aucun résultat'))
                    : _Results(result: result, isPicking: widget.isPicking),
          ),
        ),
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
  const _Results({required this.result, required this.isPicking});

  final SearchResult result;
  final bool isPicking;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: PanelScrollScope.of(context),
      padding: const EdgeInsets.only(bottom: 24),
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
                    onPressed: () => context.push(Routes.line(line.id)),
                  ),
              ],
            ),
          ),
        for (final place in result.places) _PlaceTile(place: place, isPicking: isPicking),
      ],
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({required this.place, required this.isPicking});

  final PlaceResult place;
  final bool isPicking;

  void _open(BuildContext context) {
    if (isPicking) {
      context.pop(JourneyPlace.fromPlace(place));
    } else if (place.type == PlaceType.stopArea) {
      context.push(Routes.stop(place.id));
    } else {
      // An address or a place: go there, like Citymapper
      context.push(Routes.journey(JourneyRequest(from: const JourneyPlace.currentLocation(), to: JourneyPlace.fromPlace(place))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (place.type) {
      PlaceType.stopArea => Icons.directions_transit,
      PlaceType.address => Icons.place_outlined,
      PlaceType.poi => Icons.star_outline,
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurfaceVariant,
        child: Icon(icon),
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
      onTap: () => _open(context),
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
