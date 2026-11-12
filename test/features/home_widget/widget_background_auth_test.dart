import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/auth/token_store.dart';
import 'package:website_app/core/config.dart';
import 'package:website_app/features/home_widget/home_widget_sync.dart';

import '../../support/fake_backend.dart';

/// The widget's fetches in the background never touch the account's session: the device's guest token, whatever
void main() {
  final refreshTokenKey = '${AppConfig.storagePrefix}refresh_token';
  late FakeBackend backend;
  late TokenStore tokens;

  String? bearer(RequestOptions request) => request.headers['Authorization'] as String?;

  setUp(() {
    backend = FakeBackend()
      ..post('/api/auth/guest', {'jwt': 'guest-1', 'expiresIn': 2592000})
      ..post('/api/token/refresh', {'jwt': 'account', 'refreshToken': 'rotated', 'expiresIn': 3600})
      ..on('GET', '/api/v2/traffic', (request) => FakeResponse([], status: bearer(request) == 'Bearer revoked' ? 401 : 200));
  });

  Future<TokenStore> store(Map<String, String> values) async {
    FlutterSecureStorage.setMockInitialValues(values);
    final store = TokenStore();
    await store.load();
    return store;
  }

  test('signed in: the guest token, the refresh token never used (nor rotated)', () async {
    tokens = await store({refreshTokenKey: 'account-refresh'});
    final dio = await widgetBackgroundDio(backend.dio(), tokens);

    await dio.get<Object>('/api/v2/traffic');

    expect(backend.requestsTo('/api/token/refresh'), isEmpty);
    expect(bearer(backend.requestsTo('/api/v2/traffic').single), 'Bearer guest-1');
    expect(tokens.refreshToken, 'account-refresh');
  });

  test('a guest token still valid: no authentication call at all', () async {
    tokens = await store({});
    await tokens.saveGuest(const AuthTokens(jwt: 'kept', expiresIn: 86400));

    final dio = await widgetBackgroundDio(backend.dio(), tokens);
    await dio.get<Object>('/api/v2/traffic');

    expect(backend.requestsTo('/api/auth/guest'), isEmpty);
    expect(bearer(backend.requestsTo('/api/v2/traffic').single), 'Bearer kept');
  });

  test('a guest token rejected: a new one, the request retried once', () async {
    tokens = await store({});
    await tokens.saveGuest(const AuthTokens(jwt: 'revoked', expiresIn: 86400));

    final dio = await widgetBackgroundDio(backend.dio(), tokens);
    final response = await dio.get<Object>('/api/v2/traffic');

    expect(response.statusCode, 200);
    expect(backend.requestsTo('/api/v2/traffic').map(bearer), ['Bearer revoked', 'Bearer guest-1']);
    expect(tokens.guestToken, 'guest-1');
  });
}
