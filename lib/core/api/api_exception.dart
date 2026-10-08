import 'package:dio/dio.dart';

import '../../l10n/l10n.dart';

/// Error returned by the backend, built from its problem details (`detail`) when present. Messages in the app's
/// language, except the backend's own details.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  bool get isNotFound => statusCode == 404;

  factory ApiException.fromDio(DioException error) {
    final l10n = currentL10n;
    final response = error.response;
    if (response == null) {
      return ApiException(l10n.errorServerUnreachable);
    }

    final data = response.data;
    final detail = data is Map ? data['detail'] as String? : null;
    final message = switch (response.statusCode) {
      401 => l10n.errorSessionExpired,
      404 => l10n.errorNotFound,
      429 => l10n.errorTooManyRequests,
      final code? when code >= 500 => l10n.errorServer,
      _ => detail ?? l10n.errorUnexpected,
    };
    return ApiException(message, statusCode: response.statusCode);
  }

  @override
  String toString() => message;
}
