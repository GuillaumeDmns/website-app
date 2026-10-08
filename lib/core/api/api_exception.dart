import 'package:dio/dio.dart';

import '../../l10n/l10n.dart';

/// Error returned by the backend, built from its problem details (`detail`, `code`) when present. Messages in the
/// app's language, except the backend's own details.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// Problem detail `code` of the backend (`guest_journey_limit`, `guest_quota_exhausted`…), when given
  final String? code;

  bool get isUnauthorized => statusCode == 401;

  bool get isNotFound => statusCode == 404;

  /// A limit of the use without account: signing in lifts it
  bool get signInHelps => code == 'guest_journey_limit' || code == 'guest_quota_exhausted';

  factory ApiException.fromDio(DioException error) {
    final l10n = currentL10n;
    final response = error.response;
    if (response == null) {
      return ApiException(l10n.errorServerUnreachable);
    }

    final data = response.data;
    final detail = data is Map ? data['detail'] as String? : null;
    final code = data is Map ? data['code'] as String? : null;
    final message = switch ((response.statusCode, code)) {
      (_, 'guest_journey_limit') => l10n.errorGuestJourneyLimit,
      (_, 'guest_quota_exhausted') => l10n.errorGuestQuota,
      (_, 'journey_limit') => l10n.errorJourneyLimit,
      (401, _) => l10n.errorSessionExpired,
      (404, _) => l10n.errorNotFound,
      (429, _) => l10n.errorTooManyRequests,
      (final status?, _) when status >= 500 => l10n.errorServer,
      _ => detail ?? l10n.errorUnexpected,
    };
    return ApiException(message, statusCode: response.statusCode, code: code);
  }

  @override
  String toString() => message;
}
