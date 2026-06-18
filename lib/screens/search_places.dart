import 'package:flutter/material.dart';

import '../models/navitia/place.dart';
import '../services/api_repository.dart';
import '../utils/debounce_utils.dart';

class SearchPlaceScreen extends StatefulWidget {
  final String hintText;

  const SearchPlaceScreen({
    super.key,
    required this.hintText,
  });

  @override
  State<SearchPlaceScreen> createState() => _SearchPlaceScreenState();
}

class _SearchPlaceScreenState extends State<SearchPlaceScreen> {
  final _searchController = TextEditingController();
  final _api = ApiRepository();
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 300));

  List<Place> _places = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_searchController.text.isEmpty) {
      setState(() {
        _places = [];
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    _debouncer.run(() async {
      try {
        final response = await _api.autocompletePlaces(_searchController.text);
        if (mounted) {
          setState(() {
            _places = response.places ?? [];
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint(e.toString());
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            fillColor: Colors.transparent,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _searchController.clear();
                    },
                  )
                : null,
          ),
        ),
      ),
      body: _buildBody(colorScheme),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (_searchController.text.isNotEmpty && _places.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 52, color: colorScheme.onSurface.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            Text(
              'Aucun résultat trouvé',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      );
    }

    if (_places.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded,
                size: 52, color: colorScheme.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              'Entrez une adresse ou un lieu',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _places.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 56,
        color: colorScheme.outlineVariant,
      ),
      itemBuilder: (context, index) {
        final place = _places[index];
        return ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.location_on_rounded,
                size: 18, color: colorScheme.primary),
          ),
          title: Text(
            place.name ?? 'Lieu inconnu',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          onTap: () => Navigator.of(context).pop(place),
        );
      },
    );
  }
}
