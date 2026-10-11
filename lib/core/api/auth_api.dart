import 'package:dio/dio.dart';

import '../../l10n/l10n.dart';
import 'api_exception.dart';
import 'models.dart';

/// Auth endpoints. Uses a client without the auth interceptor.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  /// Rotates the refresh token: the given one is no longer valid afterwards
  Future<AuthTokens> refresh(String refreshToken) => _tokens('/api/token/refresh', {'refreshToken': refreshToken});

  /// Exchanges a Google ID token for the account's tokens (account created at the first sign-in)
  Future<AuthTokens> google(String idToken) => _tokens('/api/auth/google', {'idToken': idToken});

  /// Token of a device used without account (capped usage, about 30 days, no refresh token)
  Future<AuthTokens> guest() => _tokens('/api/auth/guest', const {});

  Future<void> logout(String refreshToken) async {
    try {
      await _dio.post<void>('/api/logout', data: {'refreshToken': refreshToken});
    } on DioException {
      // The token is forgotten locally anyway
    }
  }

  Future<AuthTokens> _tokens(String path, Map<String, String> body) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: body);
      return AuthTokens.fromJson(response.data!);
    } on DioException catch (e) {
      if (path == '/api/auth/google' && e.response != null) {
        throw ApiException(currentL10n.googleSignInFailed, statusCode: e.response?.statusCode);
      }
      throw ApiException.fromDio(e);
    }
  }
}
