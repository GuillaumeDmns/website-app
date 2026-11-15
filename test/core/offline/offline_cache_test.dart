import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/offline/offline_cache.dart';

import '../../support/fake_backend.dart';
import '../../support/memory_store.dart';

void main() {
  late FakeBackend backend;
  late MemoryStore store;
  late Dio dio;
  late OfflineCacheInterceptor cache;
  DateTime? offlineSince;
  var online = 0;

  setUp(() {
    backend = FakeBackend();
    store = MemoryStore();
    offlineSince = null;
    online = 0;
    cache = OfflineCacheInterceptor(store: store, onOffline: (at) => offlineSince = at, onOnline: () => online++);
    addTearDown(cache.dispose);
    dio = backend.dio()..interceptors.add(cache);
  });

  /// The answers written to the device, as when the app leaves the screen
  Future<void> settle() => cache.flush();

  test('serves the last answer when the server cannot be reached', () async {
    backend.get('/api/v2/traffic', [
      {'line': 'C01371'},
    ]);
    await dio.get<Object>('/api/v2/traffic');
    await settle();
    expect(online, 1);

    backend.on('GET', '/api/v2/traffic', (_) => const FakeResponse.unreachable());
    final cached = await dio.get<Object>('/api/v2/traffic');

    expect(cached.data, [
      {'line': 'C01371'},
    ]);
    expect(cached.extra['offlineAt'], isA<DateTime>());
    expect(offlineSince, isNotNull);
  });

  test('answers wait in memory, written together when the app leaves the screen; served meanwhile', () async {
    backend.get('/api/v2/traffic', [1]);
    backend.get('/api/v2/nearby/departures', [2]);
    for (var refresh = 0; refresh < 5; refresh++) {
      await dio.get<Object>('/api/v2/traffic');
      await dio.get<Object>('/api/v2/nearby/departures');
    }
    await Future<void>.delayed(Duration.zero);
    expect(store.values, isEmpty);

    // Offline before anything was written: the answer in memory
    backend.down = true;
    expect((await dio.get<Object>('/api/v2/traffic')).data, [1]);
    backend.down = false;

    await cache.flush();
    expect(store.values.keys, unorderedEquals(['http_cache:/api/v2/traffic?', 'http_cache:/api/v2/nearby/departures?', 'http_cache_index']));
    // The latest answered first in the index
    expect(await store.readJson('http_cache_index'), ['http_cache:/api/v2/nearby/departures?', 'http_cache:/api/v2/traffic?']);
  });

  test('written after a while at the latest, without leaving the screen', () async {
    cache = OfflineCacheInterceptor(store: store, onOffline: (_) {}, onOnline: () {}, flushAfter: const Duration(milliseconds: 20));
    addTearDown(cache.dispose);
    dio = backend.dio()..interceptors.add(cache);
    backend.get('/api/v2/traffic', [1]);
    await dio.get<Object>('/api/v2/traffic');
    expect(store.values, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(store.values.keys, contains('http_cache:/api/v2/traffic?'));
  });

  test('answers not written yet are forgotten at sign-out too', () async {
    backend.get('/api/v2/me/favorites', []);
    await dio.get<Object>('/api/v2/me/favorites');
    await cache.clearAll();
    await cache.flush();
    expect(store.values, isEmpty);
    backend.down = true;
    await expectLater(dio.get<Object>('/api/v2/me/favorites'), throwsA(isA<DioException>()));
  });

  test('keeps each query apart', () async {
    backend.on('GET', '/api/v2/stops/*/departures', (request) => FakeResponse({'stop': request.uri.pathSegments[3]}));
    await dio.get<Object>('/api/v2/stops/IDFM:1/departures');
    await settle();
    backend.on('GET', '/api/v2/stops/*/departures', (_) => const FakeResponse.unreachable());

    await expectLater(dio.get<Object>('/api/v2/stops/IDFM:2/departures'), throwsA(isA<DioException>()));
    expect((await dio.get<Object>('/api/v2/stops/IDFM:1/departures')).data, {'stop': 'IDFM:1'});
  });

  test('never keeps real-time-only answers, the stops of the map nor the account', () async {
    for (final path in ['/api/v2/lines/C1/vehicles', '/api/v2/lines/C1/rides', '/api/v2/bikes/nearby', '/api/v2/search', '/api/v2/nearby', '/api/v2/me', '/api/v2/me/export']) {
      backend.get(path, {'path': path});
      await dio.get<Object>(path);
    }
    await settle();

    expect(store.values.keys.where((key) => key.startsWith('http_cache:')), isEmpty);
  });

  test('keeps the departures around, which the home page shows offline', () async {
    backend.get('/api/v2/nearby/departures', [{'stop': 'IDFM:1'}]);
    await dio.get<Object>('/api/v2/nearby/departures');
    await settle();

    expect(store.values.keys.where((key) => key.startsWith('http_cache:')), hasLength(1));
  });

  test('does not hide server errors', () async {
    backend.get('/api/v2/traffic', []);
    await dio.get<Object>('/api/v2/traffic');
    await settle();
    backend.get('/api/v2/traffic', {'status': 500}, status: 500);

    await expectLater(dio.get<Object>('/api/v2/traffic'), throwsA(isA<DioException>()));
  });

  test('forgets everything at sign-out', () async {
    backend.get('/api/v2/traffic', []);
    backend.get('/api/v2/me/favorites', []);
    await dio.get<Object>('/api/v2/traffic');
    await settle();
    await dio.get<Object>('/api/v2/me/favorites');
    await settle();
    expect(store.values.keys.where((key) => key.startsWith('http_cache')), hasLength(3));

    await cache.clearAll();

    expect(store.values, isEmpty);
  });

  test('keeps the 60 latest answers', () async {
    backend.on('GET', '/api/v2/lines/*', (request) => FakeResponse({'id': request.uri.pathSegments.last}));
    for (var i = 0; i < 65; i++) {
      await dio.get<Object>('/api/v2/lines/C$i');
      await settle();
    }

    final cached = store.values.keys.where((key) => key.startsWith('http_cache:')).toList();
    expect(cached, hasLength(60));
    expect(cached, isNot(contains('http_cache:/api/v2/lines/C0?')));
    expect(cached, contains('http_cache:/api/v2/lines/C64?'));
  });

  test('indexes answers that come together, so that sign-out forgets them all', () async {
    // The device's store answers later, as the platform does
    store = _SlowStore();
    cache = OfflineCacheInterceptor(store: store, onOffline: (_) {}, onOnline: () {});
    addTearDown(cache.dispose);
    dio = backend.dio()..interceptors.add(cache);
    backend.on('GET', '/api/v2/lines/*', (request) => FakeResponse({'id': request.uri.pathSegments.last}));
    await Future.wait([for (var i = 0; i < 3; i++) dio.get<Object>('/api/v2/lines/C$i')]);
    await cache.flush();
    expect(store.values.keys.where((key) => key.startsWith('http_cache:')), hasLength(3));

    await cache.clearAll();

    expect(store.values, isEmpty);
  });

  test('shows the oldest data while offline, nothing once online', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final offline = container.read(offlineProvider.notifier);
    final morning = DateTime(2026, 10, 10, 8);

    offline.offline(morning.add(const Duration(hours: 1)));
    offline.offline(morning);
    offline.offline(morning.add(const Duration(hours: 2)));
    expect(container.read(offlineProvider), morning);

    offline.online();
    expect(container.read(offlineProvider), isNull);
  });
}

class _SlowStore extends MemoryStore {
  @override
  Future<Object?> readJson(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return super.readJson(key);
  }
}
