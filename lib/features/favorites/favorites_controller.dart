import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/storage/local_store.dart';
import '../auth/auth_controller.dart';
import '../journey/journey_request.dart';

/// Favorites. With an account they are the server's: the copy kept on the device is shown at once, then replaced by
/// the server's. A guest's stay on the device only, with negative ids, and join the account at sign-in.
class FavoritesController extends AsyncNotifier<List<Favorite>> {
  static const _cacheKey = 'favorites';

  @override
  Future<List<Favorite>> build() async {
    final status = ref.watch(authControllerProvider);
    if (status == AuthStatus.unknown) {
      return const [];
    }

    final cached = await _readCache();
    if (status == AuthStatus.guest) {
      return cached;
    }

    final local = cached.where(_isLocal).toList();
    if (local.isEmpty) {
      if (cached.isNotEmpty) {
        unawaited(_refresh());
        return cached;
      }
      return _fetch();
    }

    // Saved as a guest: they join the account. Offline, they wait on the device for the next start.
    for (final favorite in local) {
      try {
        await ref.read(mobilityApiProvider).addFavorite(_body(favorite));
      } on ApiException catch (e) {
        final statusCode = e.statusCode;
        if (statusCode == null || statusCode >= 500) {
          return cached;
        }
        // Refused (e.g. a line that no longer exists): dropped
      }
    }
    return _fetch();
  }

  Future<List<Favorite>> _readCache() async {
    final json = await ref.read(localStoreProvider).readJson(_cacheKey);
    return json is List ? json.map((item) => Favorite.fromJson(item as Map<String, dynamic>)).toList() : const [];
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

  bool get _guest => ref.read(authControllerProvider) != AuthStatus.signedIn;

  static bool _isLocal(Favorite favorite) => favorite.id < 0;

  /// Account: the server stores it. Guest: on the device, as the server would (home and work replace the previous one,
  /// a stop or line saved twice stays once).
  Future<void> _save(Favorite favorite) async {
    final Favorite saved;
    if (_guest) {
      final lowestId = _current.fold(0, (lowest, existing) => existing.id < lowest ? existing.id : lowest);
      saved = favorite.copyWith(id: lowestId - 1);
    } else {
      saved = await ref.read(mobilityApiProvider).addFavorite(_body(favorite));
    }
    final replaced = saved.kind == FavoriteKind.home || saved.kind == FavoriteKind.work;
    final next = [
      ..._current.where((existing) => existing.id != saved.id && !(replaced && existing.kind == saved.kind)),
      saved,
    ];
    state = AsyncData(next);
    await _cache(next);
  }

  /// What the server needs to save [favorite]
  static Map<String, dynamic> _body(Favorite favorite) => switch (favorite.kind) {
        FavoriteKind.stop => {'kind': favorite.kind.apiName, 'stopAreaId': favorite.stopAreaId},
        FavoriteKind.line => {'kind': favorite.kind.apiName, 'lineId': favorite.line?.id},
        _ => {
            'kind': favorite.kind.apiName,
            'label': favorite.label,
            'lat': favorite.lat,
            'lon': favorite.lon,
            'stopAreaId': ?favorite.stopAreaId,
          },
      };

  Future<void> remove(Favorite favorite) async {
    if (!_isLocal(favorite)) {
      await ref.read(mobilityApiProvider).deleteFavorite(favorite.id);
    }
    final next = _current.where((existing) => existing.id != favorite.id).toList();
    state = AsyncData(next);
    await _cache(next);
  }

  /// Home, work or another saved place
  Future<void> savePlace(FavoriteKind kind, JourneyPlace place) {
    assert(kind == FavoriteKind.home || kind == FavoriteKind.work || kind == FavoriteKind.place);
    return _save(Favorite(id: 0, kind: kind, label: place.name, lat: place.lat, lon: place.lon, stopAreaId: place.stopAreaId));
  }

  Future<void> toggleStop(StopAreaSummary stop) async {
    final existing = stopFavorite(stop.id);
    existing != null
        ? await remove(existing)
        : await _save(Favorite(
            id: 0, kind: FavoriteKind.stop, label: stop.name, lat: stop.lat, lon: stop.lon, stopAreaId: stop.id, stop: stop));
  }

  Future<void> toggleLine(LineSummary line) async {
    final existing = lineFavorite(line.id);
    existing != null ? await remove(existing) : await _save(Favorite(id: 0, kind: FavoriteKind.line, line: line));
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
