import 'package:dio/dio.dart';

/// Error returned by the backend, built from its problem details (`detail`) when present.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  bool get isNotFound => statusCode == 404;

  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    if (response == null) {
      return const ApiException('Connexion au serveur impossible');
    }

    final data = response.data;
    final detail = data is Map ? data['detail'] as String? : null;
    final message = switch (response.statusCode) {
      401 => 'Session expirée, reconnectez-vous',
      404 => 'Introuvable',
      429 => 'Trop de requêtes, réessayez dans un instant',
      final code? when code >= 500 => 'Le serveur rencontre un problème',
      _ => detail ?? 'Erreur inattendue',
    };
    return ApiException(message, statusCode: response.statusCode);
  }

  @override
  String toString() => message;
}
