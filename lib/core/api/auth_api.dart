import 'package:dio/dio.dart';

import '../../l10n/l10n.dart';
import 'api_exception.dart';
import 'models.dart';

/// Auth endpoints. Uses a client without the auth interceptor.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<AuthTokens> signIn(String username, String password) =>
      _tokens('/api/signin', {'username': username, 'password': password});

  Future<AuthTokens> signUp(String username, String email, String password) =>
      _tokens('/api/signup', {'username': username, 'email': email, 'password': password});

  /// Rotates the refresh token: the given one is no longer valid afterwards
  Future<AuthTokens> refresh(String refreshToken) => _tokens('/api/token/refresh', {'refreshToken': refreshToken});

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
      final data = e.response?.data;
      // Sign-in/up errors are meaningful to the user (wrong password, username taken…)
      if (e.response?.statusCode == 401 && path == '/api/signin') {
        throw ApiException(currentL10n.authWrongCredentials, statusCode: 401);
      }
      if (data is Map && data['detail'] is String && (e.response?.statusCode ?? 0) < 500) {
        throw ApiException(_translate(data['detail'] as String), statusCode: e.response?.statusCode);
      }
      throw ApiException.fromDio(e);
    }
  }

  static String _translate(String detail) => switch (detail) {
        'Username already used' => currentL10n.authUsernameTaken,
        'Email already used' => currentL10n.authEmailTaken,
        'Invalid email' => currentL10n.authInvalidEmail,
        'Password is too long' => currentL10n.authPasswordTooLong,
        final d when d.startsWith('Password must be at least') => currentL10n.authPasswordTooShort,
        final d when d.startsWith('Username must be') => currentL10n.authUsernameInvalid(currentL10n.authUsernameRule),
        _ => detail,
      };
}
