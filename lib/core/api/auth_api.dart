import 'package:dio/dio.dart';

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
        throw const ApiException('Identifiant ou mot de passe incorrect', statusCode: 401);
      }
      if (data is Map && data['detail'] is String && (e.response?.statusCode ?? 0) < 500) {
        throw ApiException(_translate(data['detail'] as String), statusCode: e.response?.statusCode);
      }
      throw ApiException.fromDio(e);
    }
  }

  static String _translate(String detail) => switch (detail) {
        'Username already used' => 'Ce nom d\'utilisateur est déjà pris',
        'Email already used' => 'Cet email est déjà utilisé',
        'Invalid email' => 'Email invalide',
        'Password is too long' => 'Mot de passe trop long',
        final d when d.startsWith('Password must be at least') => 'Le mot de passe doit faire au moins 8 caractères',
        final d when d.startsWith('Username must be') =>
          'Nom d\'utilisateur : 3 à 50 lettres, chiffres, « . », « _ » ou « - »',
        _ => detail,
      };
}
