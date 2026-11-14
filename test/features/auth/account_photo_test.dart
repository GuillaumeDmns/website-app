import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/features/auth/account_photo.dart';

/// A token as Google signs them, for its claims only
String idToken(Map<String, Object?> claims) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part(claims)}.signature';
}

void main() {
  test("the picture of a Google ID token: its `picture` claim", () {
    const picture = 'https://lh3.googleusercontent.com/a/photo=s96-c';
    expect(googlePhotoOf(idToken({'sub': '42', 'email': 'ada@example.com', 'picture': picture})), picture);
    // Accents in the name: base64url of UTF-8
    expect(googlePhotoOf(idToken({'given_name': 'Zoé', 'picture': picture})), picture);
  });

  test('no picture: an account without one, an address that is not https, a token that is not one', () {
    expect(googlePhotoOf(idToken({'sub': '42'})), isNull);
    expect(googlePhotoOf(idToken({'picture': 'http://example.com/photo.jpg'})), isNull);
    expect(googlePhotoOf(idToken({'picture': 42})), isNull);
    expect(googlePhotoOf('test-google-id-token'), isNull);
    expect(googlePhotoOf('a.b.c'), isNull);
    expect(googlePhotoOf(''), isNull);
  });
}
