import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/utils/auth_utils.dart';

void main() {
  group('AuthUtils Tests', () {
    test('isTokenExpired returns true for null token', () {
      expect(AuthUtils.isTokenExpired(null), isTrue);
    });

    test('isTokenExpired returns true for invalid token string', () {
      expect(AuthUtils.isTokenExpired('invalid.token'), isTrue);
    });

    test('isTokenExpired returns true for expired token', () {
      final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
      final expiredTimestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 3600;
      final payload = base64Url.encode(utf8.encode('{"exp":$expiredTimestamp}'));
      final token = '$header.$payload.signature';

      expect(AuthUtils.isTokenExpired(token), isTrue);
    });

    test('isTokenExpired returns false for valid future token', () {
      final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
      final futureTimestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600;
      final payload = base64Url.encode(utf8.encode('{"exp":$futureTimestamp}'));
      final token = '$header.$payload.signature';

      expect(AuthUtils.isTokenExpired(token), isFalse);
    });
  });
}
