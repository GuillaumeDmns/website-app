import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/storage/local_store.dart';
import '../auth/auth_controller.dart';
import '../journey/journey_request.dart';

/// Favorites of the signed-in user. The copy kept on the device is shown at once, then replaced by the server's.
class FavoritesController extends AsyncNotifier<List<Favorite>> {
  static const _cacheKey = 'favorites';

  @override
  Future<List<Favorite>> build() async {
    // Another user, or signed out: start over
    if (ref.watch(authControllerProvider) != AuthStatus.signedIn) {
      return const [];
    }

    final cached = await ref.read(localStoreProvider).readJson(_cacheKey);
    if (cached is List) {
      unawaited(_refresh());
      return cached.map((json) => Favorite.fromJson(json as Map<String, dynamic>)).toList();
    }
    return _fetch();
  }

  Future<List<Favorite>> _fetch() async {
    final favorites = await ref.read(mobilityApiProvider).favorites();
    await _cache(favorites);
    return favorites;
  }

  Future<void> _refresh() async {
    try {
      state = AsyncData(await _fetch());
    } catch (_) {
      // Offline: keep the cached favorites
    }
  }

  Future<void> _cache(List<Favorite> favorites) =>
      ref.read(localStoreProvider).writeJson(_cacheKey, favorites.map((favorite) => favorite.toJson()).toList());

  List<Favorite> get _current => state.value ?? const [];

  Future<void> _save(Map<String, dynamic> body) async {
    final saved = await ref.read(mobilityApiProvider).addFavorite(body);
    // Home/work replace the previous one and a stop saved twice comes back with the same id
    final next = [..._current.where((favorite) => favorite.id != saved.id), saved];
    state = AsyncData(next);
    await _cache(next);
  }

  Future<void> remove(Favorite favorite) async {
    await ref.read(mobilityApiProvider).deleteFavorite(favorite.id);
    final next = _current.where((existing) => existing.id != favorite.id).toList();
    state = AsyncData(next);
    await _cache(next);
  }

  /// Home, work or another saved place
  Future<void> savePlace(FavoriteKind kind, JourneyPlace place) {
    assert(kind == FavoriteKind.home || kind == FavoriteKind.work || kind == FavoriteKind.place);
    return _save({
      'kind': kind.apiName,
      'label': place.name,
      'lat': place.lat,
      'lon': place.lon,
      'stopAreaId': ?place.stopAreaId,
    });
  }

  Future<void> toggleStop(String stopAreaId) async {
    final existing = stopFavorite(stopAreaId);
    existing != null ? await remove(existing) : await _save({'kind': 'STOP', 'stopAreaId': stopAreaId});
  }

  Future<void> toggleLine(String lineId) async {
    final existing = lineFavorite(lineId);
    existing != null ? await remove(existing) : await _save({'kind': 'LINE', 'lineId': lineId});
  }

  Favorite? stopFavorite(String stopAreaId) =>
      _current.where((favorite) => favorite.kind == FavoriteKind.stop && favorite.stopAreaId == stopAreaId).firstOrNull;

  Favorite? lineFavorite(String lineId) =>
      _current.where((favorite) => favorite.kind == FavoriteKind.line && favorite.line?.id == lineId).firstOrNull;

  /// Forgets the device copy (sign-out)
  Future<void> clearCache() => ref.read(localStoreProvider).remove(_cacheKey);
}

final favoritesProvider = AsyncNotifierProvider<FavoritesController, List<Favorite>>(FavoritesController.new);

/// Journey place of a saved place (home, work, place)
JourneyPlace favoritePlace(Favorite favorite) => favorite.stopAreaId != null && favorite.kind != FavoriteKind.stop
    ? JourneyPlace.stopArea(name: favorite.label ?? '', id: favorite.stopAreaId!, lat: favorite.lat, lon: favorite.lon)
    : JourneyPlace.point(name: favorite.label ?? '', lat: favorite.lat ?? 0, lon: favorite.lon ?? 0);
