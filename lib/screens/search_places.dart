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
  final _debouncer = AsyncDebouncer(delay: const Duration(milliseconds: 300));

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

    setState(() {
      _isLoading = true;
    });

    _debouncer.debounce<void>(() async {
      final response = await _api.autocompletePlaces(_searchController.text);
      if (mounted) {
        setState(() {
          _places = response.places ?? [];
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.hintText,
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.grey[600]),
          ),
          style: const TextStyle(color: Colors.black, fontSize: 18),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.isNotEmpty && _places.isEmpty) {
      return const Center(child: Text('No results found.'));
    }

    return ListView.builder(
      itemCount: _places.length,
      itemBuilder: (context, index) {
        final place = _places[index];
        return ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: Text(place.name ?? 'Unknown place'),
          onTap: () {
            Navigator.of(context).pop(place);
          },
        );
      },
    );
  }
}