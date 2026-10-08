import 'package:dio/dio.dart';

import '../auth/token_store.dart';
import 'api_exception.dart';
import 'auth_api.dart';

enum _RefreshResult { ok, sessionLost, unreachable }

/// Adds the access token, renews it from the refresh token when it is about to expire or rejected, and reports a
/// lost session. Queued: concurrent requests wait for a single refresh (the refresh token rotates on each use).
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({required this.tokenStore, required this.authApi, required this.dio, required this.onSessionLost});

  final TokenStore tokenStore;
  final AuthApi authApi;

  /// Client used to retry a request after a refresh
  final Dio dio;
  final void Function() onSessionLost;

  static const _retriedKey = 'authRetried';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!tokenStore.hasValidAccessToken) {
      switch (await _refresh()) {
        case _RefreshResult.ok:
          break;
        case _RefreshResult.sessionLost:
          handler.reject(DioException(requestOptions: options, response: Response(requestOptions: options, statusCode: 401)));
          return;
        case _RefreshResult.unreachable:
          // The next interceptors still see it (offline cache)
          handler.reject(DioException.connectionError(requestOptions: options, reason: 'Token refresh failed'), true);
          return;
      }
    }
    options.headers['Authorization'] = 'Bearer ${tokenStore.accessToken}';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 || options.extra[_retriedKey] == true || await _refresh() != _RefreshResult.ok) {
      handler.next(err);
      return;
    }

    options.extra[_retriedKey] = true;
    options.headers['Authorization'] = 'Bearer ${tokenStore.accessToken}';
    try {
      handler.resolve(await dio.fetch(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<_RefreshResult> _refresh() async {
    // The latest one stored: the home screen widget may have renewed it in the background (a used one revokes the
    // session)
    await tokenStore.load();
    final refreshToken = tokenStore.refreshToken;
    if (refreshToken == null) {
      onSessionLost();
      return _RefreshResult.sessionLost;
    }

    try {
      await tokenStore.save(await authApi.refresh(refreshToken));
      return _RefreshResult.ok;
    } on ApiException catch (e) {
      // Only a rejected refresh token ends the session; a network error keeps it for the next attempt
      if (e.isUnauthorized) {
        await tokenStore.clear();
        onSessionLost();
        return _RefreshResult.sessionLost;
      }
      return _RefreshResult.unreachable;
    }
  }
}
