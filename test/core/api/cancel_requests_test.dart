import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/api_exception.dart';
import 'package:website_app/core/api/api_providers.dart';
import 'package:website_app/core/offline/offline_cache.dart';
import 'package:website_app/features/traffic/traffic_providers.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/standard_backend.dart';
import '../../support/test_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useLocale(const Locale('fr'));

  test('a provider left gives up its request still on its way', () async {
    final backend = standardBackend();
    final container = testContainer(backend);
    // The device's guest token first
    await container.read(mobilityApiProvider).lineDisruptions('C01371');
    backend.held = Completer<void>();

    final page = container.listen(trafficProvider, (_, _) {});
    await pumpEventQueue();
    expect(backend.requestsTo('/api/v2/traffic'), hasLength(1));
    expect(backend.cancelled, isEmpty);

    // The page is left before the answer
    page.close();
    await pumpEventQueue();
    expect(backend.cancelled.map((request) => request.uri.path), ['/api/v2/traffic']);
    backend.held!.complete();
  });

  test('a provider shown until its answer gives nothing up', () async {
    final backend = standardBackend();
    final container = testContainer(backend);
    container.listen(trafficProvider, (_, _) {});
    expect(await container.read(trafficProvider.future), isNotEmpty);
    expect(backend.cancelled, isEmpty);
  });

  test('a request given up is not a server out of reach: nothing served from the offline cache, no offline notice', () async {
    final backend = standardBackend();
    final container = testContainer(backend);
    final api = container.read(mobilityApiProvider);
    // Kept by the offline cache
    await api.traffic();
    await pumpEventQueue();

    backend.held = Completer<void>();
    final cancelToken = CancelToken();
    final request = api.cancelledWith(cancelToken).traffic();
    await pumpEventQueue();
    cancelToken.cancel();
    await expectLater(request, throwsA(isA<ApiException>()));
    expect(container.read(offlineProvider), isNull);
    backend.held!.complete();
  });

  test('a request given up while the session is renewed does not have the next one renew it again', () async {
    // The refresh token rotates at each use: the same one sent twice revokes every session of the account
    final backend = standardBackend();
    final container = testContainer(backend, refreshToken: 'stored');
    await sessionOf(container);
    final api = container.read(mobilityApiProvider);
    backend.held = Completer<void>();

    // A page asks, and is left while its request waits for the renewal; another page asks meanwhile
    final cancelToken = CancelToken();
    final left = api.cancelledWith(cancelToken).traffic();
    await pumpEventQueue();
    cancelToken.cancel();
    await expectLater(left, throwsA(isA<ApiException>()));
    final shown = api.lineDisruptions('C01371');
    await pumpEventQueue();
    backend.held!.complete();
    await shown;

    expect(backend.requestsTo('/api/token/refresh'), hasLength(1));
    expect(container.read(tokenStoreProvider).signedIn, isTrue);
  });

  test('what changes something on the server is never given up', () async {
    final backend = standardBackend()..post('/api/v2/me/favorites', {'id': 1, 'kind': 'LINE', 'lineId': 'C01371'});
    final container = testContainer(backend, refreshToken: 'refresh-token');
    await sessionOf(container);
    final cancelToken = CancelToken()..cancel();
    await container.read(mobilityApiProvider).cancelledWith(cancelToken).addFavorite({'kind': 'LINE', 'lineId': 'C01371'});
    expect(backend.requestsTo('/api/v2/me/favorites', method: 'POST'), hasLength(1));
  });
}
