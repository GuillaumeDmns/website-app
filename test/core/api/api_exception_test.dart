import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/api_exception.dart';
import 'package:website_app/l10n/l10n.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  ApiException fromStatus(int status, [Object? data]) {
    final request = RequestOptions(path: '/api/v2/journeys');
    return ApiException.fromDio(DioException.badResponse(
      statusCode: status,
      requestOptions: request,
      response: Response<Object>(requestOptions: request, statusCode: status, data: data),
    ));
  }

  test('explains the guest limits and offers to sign in', () {
    final journeys = fromStatus(429, {'status': 429, 'detail': 'used up', 'code': 'guest_journey_limit'});
    expect(journeys.code, 'guest_journey_limit');
    expect(journeys.signInHelps, isTrue);
    expect(journeys.message, currentL10n.errorGuestJourneyLimit);

    final quota = fromStatus(503, {'code': 'guest_quota_exhausted'});
    expect(quota.signInHelps, isTrue);
    expect(quota.message, currentL10n.errorGuestQuota);

    expect(fromStatus(429, {'code': 'journey_limit'}).signInHelps, isFalse);
  });

  test('turns statuses into messages in the app language', () {
    expect(fromStatus(401).isUnauthorized, isTrue);
    expect(fromStatus(401).message, currentL10n.errorSessionExpired);
    expect(fromStatus(404).isNotFound, isTrue);
    expect(fromStatus(429).message, currentL10n.errorTooManyRequests);
    expect(fromStatus(502).message, currentL10n.errorServer);
    // The backend's own detail otherwise
    expect(fromStatus(400, {'detail': 'Invalid position'}).message, 'Invalid position');
    expect(fromStatus(400, 'not json').message, currentL10n.errorUnexpected);
  });

  test('says when the server is unreachable', () {
    final error = ApiException.fromDio(DioException.connectionError(requestOptions: RequestOptions(path: '/'), reason: 'down'));

    expect(error.statusCode, isNull);
    expect(error.message, currentL10n.errorServerUnreachable);
    expect(error.toString(), error.message);
  });
}
