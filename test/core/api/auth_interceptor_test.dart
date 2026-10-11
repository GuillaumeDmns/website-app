import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/auth_api.dart';
import 'package:website_app/core/api/auth_interceptor.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/auth/token_store.dart';
import 'package:website_app/core/config.dart';

import '../../support/fake_backend.dart';

void main() {
  final refreshTokenKey = '${AppConfig.storagePrefix}refresh_token';
  late FakeBackend backend;
  late TokenStore tokens;
  late Dio dio;
  late int sessionsLost;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    backend = FakeBackend();
    tokens = TokenStore();
    sessionsLost = 0;
    dio = backend.dio();
    dio.interceptors.add(AuthInterceptor(tokenStore: tokens, authApi: AuthApi(backend.dio()), dio: dio, onSessionLost: () => sessionsLost++));
    backend.on('GET', '/api/v2/traffic', (request) => FakeResponse([], status: request.headers['Authorization'] == 'Bearer expired' ? 401 : 200));
    backend.post('/api/auth/guest', {'jwt': 'guest-1', 'expiresIn': 2592000});
  });

  String? bearer(RequestOptions request) => request.headers['Authorization'] as String?;

  test('a new device gets a guest token', () async {
    await dio.get<Object>('/api/v2/traffic');

    expect(backend.requestsTo('/api/auth/guest'), hasLength(1));
    expect(bearer(backend.requestsTo('/api/v2/traffic').single), 'Bearer guest-1');

    // Kept for the next requests and the next starts
    await dio.get<Object>('/api/v2/traffic');
    expect(backend.requestsTo('/api/auth/guest'), hasLength(1));
    final restarted = TokenStore();
    await restarted.load();
    expect(restarted.accessToken, 'guest-1');
  });

  test('an account renews its access token with its refresh token, once for concurrent requests', () async {
    FlutterSecureStorage.setMockInitialValues({refreshTokenKey: 'refresh-1'});
    var refreshes = 0;
    backend.on('POST', '/api/token/refresh', (request) {
      refreshes++;
      return FakeResponse({'jwt': 'access-$refreshes', 'refreshToken': 'refresh-${refreshes + 1}', 'expiresIn': 3600});
    });

    await Future.wait([for (var i = 0; i < 5; i++) dio.get<Object>('/api/v2/traffic')]);

    expect(refreshes, 1);
    expect(backend.requestsTo('/api/v2/traffic').map(bearer).toSet(), {'Bearer access-1'});
    expect(tokens.refreshToken, 'refresh-2');
    expect(backend.requestsTo('/api/auth/guest'), isEmpty);
  });

  test('a rejected access token is renewed and the request retried once', () async {
    await tokens.saveGuest(const AuthTokens(jwt: 'expired', expiresIn: 3600));

    final response = await dio.get<Object>('/api/v2/traffic');

    expect(response.statusCode, 200);
    expect(backend.requestsTo('/api/v2/traffic').map(bearer), ['Bearer expired', 'Bearer guest-1']);
  });

  test('a rejected refresh token ends the session and goes on as a guest', () async {
    FlutterSecureStorage.setMockInitialValues({refreshTokenKey: 'revoked'});
    backend.post('/api/token/refresh', null, status: 401);

    await dio.get<Object>('/api/v2/traffic');

    expect(sessionsLost, 1);
    expect(tokens.signedIn, isFalse);
    expect(bearer(backend.requestsTo('/api/v2/traffic').single), 'Bearer guest-1');
  });

  test('an unreachable server keeps the session for the next attempt', () async {
    FlutterSecureStorage.setMockInitialValues({refreshTokenKey: 'refresh-1'});
    backend.on('POST', '/api/token/refresh', (_) => const FakeResponse.unreachable());

    await expectLater(dio.get<Object>('/api/v2/traffic'), throwsA(isA<DioException>()));

    expect(sessionsLost, 0);
    expect(tokens.refreshToken, 'refresh-1');
    expect(backend.requestsTo('/api/v2/traffic'), isEmpty);
  });
}
