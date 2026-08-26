import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/navitia/place.dart';

class RecentPlacesService {
  static const String _storageKey = 'recent_places';
  final FlutterSecureStorage _storage;

  RecentPlacesService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<List<Place>> getRecentPlaces() async {
    try {
      final jsonString = await _storage.read(key: _storageKey);
      if (jsonString == null || jsonString.isEmpty) return [];

      final List<dynamic> list = jsonDecode(jsonString);
      final now = DateTime.now();

      final filteredList = list.where((item) {
        final itemDateTime = DateTime.tryParse(item['timestamp'] as String);
        if (itemDateTime == null) return true;
        final ageInDays = now.difference(itemDateTime).inDays;
        return ageInDays <= 7;
      }).toList();

      return filteredList.map((item) {
        Place place = Place.fromJson(item as Map<String, dynamic>);
        if (item.containsKey('timestamp')) {
          place = Place(
            id: place.id,
            name: place.name,
            quality: place.quality
          );
        }
        return place;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRecentPlace(Place place) async {
    if (place.id == null || place.name == null) return;

    final current = await getRecentPlaces();
    current.removeWhere((p) => p.id == place.id);
    current.insert(0, place);

    final jsonList = current.map((p) => {
          'id': p.id,
          'name': p.name,
          if (p.quality != null) 'quality': p.quality,
          if (_hasDistance(p)) 'distance': _getDistance(p),
        }).toList();

    await _storage.write(key: _storageKey, value: jsonEncode(jsonList));
  }

  bool _hasDistance(Place place) => place.distance != null;

  String? _getDistance(Place place) => place.distance?.toString();

  Future<void> clearRecentPlaces() async {
    await _storage.delete(key: _storageKey);
  }
}
