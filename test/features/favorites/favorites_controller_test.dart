import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/favorites/favorites_controller.dart';
import 'package:website_app/features/journey/journey_request.dart';

import '../../support/fake_backend.dart';
import '../../support/memory_store.dart';
import '../../support/samples.dart';
import '../../support/test_container.dart';

void main() {
  late FakeBackend backend;
  late MemoryStore store;

  setUp(() {
    backend = FakeBackend();
    store = MemoryStore();
  });

  Map<String, dynamic> serverFavorite(int id, Map<String, dynamic> body) => {'id': id, ...body};

  group('as a guest', () {
    test('keeps favorites on the device with negative ids', () async {
      final container = testContainer(backend, store: store);
      await sessionOf(container);
      final favorites = container.read(favoritesProvider.notifier);
      await container.read(favoritesProvider.future);

      await favorites.toggleStop(chatelet);
      await favorites.toggleLine(metro1);

      final saved = container.read(favoritesProvider).value!;
      expect(saved.map((favorite) => favorite.id), [-1, -2]);
      expect(favorites.stopFavorite(chatelet.id)!.stop, chatelet);
      expect(favorites.lineFavorite(metro1.id)!.line, metro1);
      expect((await store.readJson('favorites') as List), hasLength(2));
      expect(backend.requestsTo('/api/v2/me/favorites'), isEmpty);

      await favorites.toggleStop(chatelet);
      expect(container.read(favoritesProvider).value!.single.kind, FavoriteKind.line);
    });

    test('replaces home and keeps other places', () async {
      final container = testContainer(backend, store: store);
      await sessionOf(container);
      final favorites = container.read(favoritesProvider.notifier);
      await container.read(favoritesProvider.future);

      await favorites.savePlace(FavoriteKind.home, const JourneyPlace.point(name: 'Old home', lat: 48.8, lon: 2.3));
      await favorites.savePlace(FavoriteKind.home, const JourneyPlace.point(name: 'New home', lat: 48.9, lon: 2.4));
      await favorites.savePlace(FavoriteKind.place, const JourneyPlace.stopArea(name: 'Gym', id: 'IDFM:70002', lat: 48.8, lon: 2.3));

      final saved = container.read(favoritesProvider).value!;
      expect(saved.map((favorite) => '${favorite.kind.name}:${favorite.label}'), ['home:New home', 'place:Gym']);
      expect(favoritePlace(saved.last).stopAreaId, 'IDFM:70002');
      expect(favoritePlace(saved.first).lat, 48.9);
    });
  });

  group('with an account', () {
    test('shows the device copy at once, then the server favorites', () async {
      await store.writeJson('favorites', [
        {'id': 7, 'kind': 'LINE', 'line': metro1.toJson()},
      ]);
      backend.get('/api/v2/me/favorites', [
        {'id': 7, 'kind': 'LINE', 'line': metro1.toJson()},
        {'id': 8, 'kind': 'LINE', 'line': rerA.toJson()},
      ]);
      final container = testContainer(backend, store: store, refreshToken: 'stored');
      await sessionOf(container);

      expect((await container.read(favoritesProvider.future)).map((favorite) => favorite.id), [7]);
      for (var i = 0; i < 50 && container.read(favoritesProvider).value!.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(container.read(favoritesProvider).value!.map((favorite) => favorite.id), [7, 8]);
      expect(backend.requestsTo('/api/v2/me/favorites'), hasLength(1));
    });

    test('saves and deletes on the server', () async {
      backend.get('/api/v2/me/favorites', []);
      backend.on('POST', '/api/v2/me/favorites', (request) => FakeResponse(serverFavorite(12, request.data as Map<String, dynamic>), status: 201));
      backend.delete('/api/v2/me/favorites/12');
      final container = testContainer(backend, store: store, refreshToken: 'stored');
      await sessionOf(container);
      await container.read(favoritesProvider.future);
      final favorites = container.read(favoritesProvider.notifier);

      await favorites.toggleStop(chatelet);
      expect(backend.requestsTo('/api/v2/me/favorites', method: 'POST').single.data, {'kind': 'STOP', 'stopAreaId': 'IDFM:70001'});
      expect(container.read(favoritesProvider).value!.single.id, 12);

      await favorites.toggleStop(chatelet);
      expect(backend.requestsTo('/api/v2/me/favorites/12', method: 'DELETE'), hasLength(1));
      expect(container.read(favoritesProvider).value, isEmpty);
    });

    test('uploads what was saved as a guest at sign-in, drops what the server refuses', () async {
      await store.writeJson('favorites', [
        {'id': -1, 'kind': 'STOP', 'label': 'Châtelet', 'stopAreaId': 'IDFM:70001', 'lat': 48.8584, 'lon': 2.347},
        {'id': -2, 'kind': 'LINE', 'line': const LineSummary(id: 'C99999', mode: TransportMode.bus).toJson()},
      ]);
      backend.on('POST', '/api/v2/me/favorites', (request) {
        final body = request.data as Map<String, dynamic>;
        return body['kind'] == 'LINE' ? FakeResponse.problem(400, detail: 'Unknown line') : FakeResponse(serverFavorite(1, body), status: 201);
      });
      backend.get('/api/v2/me/favorites', [
        {'id': 1, 'kind': 'STOP', 'label': 'Châtelet', 'stopAreaId': 'IDFM:70001', 'lat': 48.8584, 'lon': 2.347},
      ]);
      final container = testContainer(backend, store: store, refreshToken: 'stored');
      await sessionOf(container);

      final favorites = await container.read(favoritesProvider.future);

      expect(backend.requestsTo('/api/v2/me/favorites', method: 'POST'), hasLength(2));
      expect(favorites.map((favorite) => favorite.id), [1]);
    });

    test('keeps the guest favorites on the device while the server is unreachable', () async {
      await store.writeJson('favorites', [
        {'id': -1, 'kind': 'STOP', 'label': 'Châtelet', 'stopAreaId': 'IDFM:70001', 'lat': 48.8584, 'lon': 2.347},
      ]);
      backend.on('POST', '/api/v2/me/favorites', (_) => const FakeResponse.unreachable());
      final container = testContainer(backend, store: store, refreshToken: 'stored');
      await sessionOf(container);

      final favorites = await container.read(favoritesProvider.future);

      expect(favorites.single.id, -1);
    });
  });
}
