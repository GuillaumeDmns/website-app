import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/navitia/place.dart';
import '../services/api_repository.dart';
import '../services/recent_places_service.dart';
import '../utils/debounce_utils.dart';
import '../utils/location_utils.dart';

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
  final _recentPlacesService = RecentPlacesService();
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 300));

  List<Place> _places = [];
  List<Place> _recentPlaces = [];
  bool _isLoading = false;
  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadRecentPlaces();
  }

  Future<void> _loadRecentPlaces() async {
    final recent = await _recentPlacesService.getRecentPlaces();
    if (mounted) {
      setState(() {
        _recentPlaces = recent;
      });
    }
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

  Future<void> _selectCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      bool hasPermission = await LocationUtils.checkAndRequestLocationPermissions(
        context,
        title: 'Ma position',
        description: 'Autorisez la localisation pour utiliser votre position comme point de départ.',
      );
      if (!hasPermission || !mounted) {
        setState(() => _isGettingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final currentPlace = Place(
        id: '${position.longitude};${position.latitude}',
        name: 'Ma position actuelle',
      );

      if (!mounted) return;
      await _selectPlace(currentPlace);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'obtenir la position actuelle')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _selectPlace(Place place) async {
    if (place.id != null && !place.id!.contains(';')) {
      await _recentPlacesService.saveRecentPlace(place);
    }
    if (mounted) {
      Navigator.of(context).pop(place);
    }
  }

  Future<void> _clearRecentPlaces() async {
    await _recentPlacesService.clearRecentPlaces();
    setState(() {
      _recentPlaces = [];
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

    if (_searchController.text.isEmpty) {
      return ListView(
        children: [
          // Current Location tile
          ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: _isGettingLocation
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: colorScheme.primary),
                    )
                  : Icon(Icons.my_location_rounded,
                      size: 20, color: colorScheme.primary),
            ),
            title: Text(
              'Ma position actuelle',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
            ),
            onTap: _isGettingLocation ? null : _selectCurrentLocation,
          ),
          const Divider(height: 1),

          // Recent places header & list
          if (_recentPlaces.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recherches récentes',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                  TextButton(
                    onPressed: _clearRecentPlaces,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Effacer',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ..._recentPlaces.map(
              (place) => ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.history_rounded,
                      size: 18,
                      color: colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                title: Text(
                  place.name ?? 'Lieu inconnu',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                onTap: () => _selectPlace(place),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_rounded,
                      size: 52, color: colorScheme.onSurface.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text(
                    'Entrez une adresse, une station ou une gare',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                  ),
                ],
              ),
            ),
        ],
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
          onTap: () => _selectPlace(place),
        );
      },
    );
  }
}
