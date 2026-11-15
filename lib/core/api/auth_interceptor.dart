import 'package:dio/dio.dart';

import '../auth/token_store.dart';
import 'api_exception.dart';
import 'auth_api.dart';

enum _RenewResult { ok, unreachable }

/// Adds the access token: the account's, renewed from the refresh token when it is about to expire or rejected, else
/// the device's guest token, fetched when missing or rejected. A rejected refresh token ends the account's session
/// (reported) and the request goes on as a guest. Concurrent requests wait for a single renewal ([_renew]): the refresh
/// token rotates on each use, and the same one sent twice revokes every session of the account. The queue alone doesn't
/// see to it: it moves on when the request it holds is given up (a page left while it waits for the renewal), and
/// requests and rejected answers have a queue each.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({required this.tokenStore, required this.authApi, required this.dio, required this.onSessionLost});

  final TokenStore tokenStore;
  final AuthApi authApi;

  /// Client used to retry a request after a renewal
  final Dio dio;
  final void Function() onSessionLost;

  static const _retriedKey = 'authRetried';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!tokenStore.hasValidAccessToken && await _renew() == _RenewResult.unreachable) {
      // The next interceptors still see it (offline cache)
      handler.reject(DioException.connectionError(requestOptions: options, reason: 'Token renewal failed'), true);
      return;
    }
    options.headers['Authorization'] = 'Bearer ${tokenStore.accessToken}';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 || options.extra[_retriedKey] == true) {
      handler.next(err);
      return;
    }
    // A guest token the server rejects (e.g. its key changed) is replaced
    if (!tokenStore.signedIn) {
      await tokenStore.clearGuest();
    }
    if (await _renew(force: true) != _RenewResult.ok) {
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

  /// The renewal in progress, shared by whoever needs one meanwhile
  Future<_RenewResult>? _renewal;

  /// One renewal at a time, whatever asks for it: see the class. [force]: renew the account's access token even if it
  /// looks valid (the server rejected it).
  Future<_RenewResult> _renew({bool force = false}) =>
      _renewal ??= _renewOnce(force: force).whenComplete(() => _renewal = null);

  Future<_RenewResult> _renewOnce({required bool force}) async {
    // The latest tokens stored: the home screen widget may have renewed them in the background (a used refresh token
    // revokes the session)
    await tokenStore.load();
    if (tokenStore.signedIn) {
      try {
        await tokenStore.save(await authApi.refresh(tokenStore.refreshToken!));
        return _RenewResult.ok;
      } on ApiException catch (e) {
        // Only a rejected refresh token ends the session; a network error keeps it for the next attempt
        if (!e.isUnauthorized) {
          return _RenewResult.unreachable;
        }
        await tokenStore.clear();
        onSessionLost();
      }
    }

    if (!force && tokenStore.hasValidAccessToken) {
      return _RenewResult.ok;
    }
    try {
      await tokenStore.saveGuest(await authApi.guest());
      return _RenewResult.ok;
    } on ApiException {
      return _RenewResult.unreachable;
    }
  }
}
