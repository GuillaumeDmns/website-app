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
  DateTime? offlineSince;
  var online = 0;

  setUp(() {
    backend = FakeBackend();
    store = MemoryStore();
    offlineSince = null;
    online = 0;
    dio = backend.dio()
      ..interceptors.add(OfflineCacheInterceptor(store: store, onOffline: (at) => offlineSince = at, onOnline: () => online++));
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

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

  test('keeps each query apart', () async {
    backend.on('GET', '/api/v2/stops/*/departures', (request) => FakeResponse({'stop': request.uri.pathSegments[3]}));
    await dio.get<Object>('/api/v2/stops/IDFM:1/departures');
    await settle();
    backend.on('GET', '/api/v2/stops/*/departures', (_) => const FakeResponse.unreachable());

    await expectLater(dio.get<Object>('/api/v2/stops/IDFM:2/departures'), throwsA(isA<DioException>()));
    expect((await dio.get<Object>('/api/v2/stops/IDFM:1/departures')).data, {'stop': 'IDFM:1'});
  });

  test('never keeps real-time-only answers nor the account', () async {
    for (final path in ['/api/v2/lines/C1/vehicles', '/api/v2/lines/C1/rides', '/api/v2/bikes/nearby', '/api/v2/search', '/api/v2/me', '/api/v2/me/export']) {
      backend.get(path, {'path': path});
      await dio.get<Object>(path);
    }
    await settle();

    expect(store.values.keys.where((key) => key.startsWith('http_cache:')), isEmpty);
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

    await OfflineCacheInterceptor.clear(store);

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
