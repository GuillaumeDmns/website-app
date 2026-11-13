import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test("the web page only runs another site's files with their integrity checked", () {
    final page = File('web/index.html').readAsStringSync();
    final external = RegExp(r'<(script|link)\b[^>]*\b(?:src|href)="https?://[^"]+"[^>]*>', dotAll: true)
        .allMatches(page)
        .map((tag) => tag.group(0)!)
        .where((tag) => tag.startsWith('<script') || tag.contains('rel="stylesheet"'))
        .toList();

    // MapLibre's script and style, from a CDN: a file changed there would run in the page, next to the session
    expect(external, hasLength(2));
    for (final tag in external) {
      expect(tag, contains(RegExp(r'integrity="sha384-[A-Za-z0-9+/=]{64}"')), reason: tag);
      expect(tag, contains('crossorigin="anonymous"'), reason: tag);
      // A version, never "latest"
      expect(tag, contains(RegExp(r'@\d+\.\d+\.\d+/')), reason: tag);
    }
  });

  test('the web page names the app and links its privacy policy without JavaScript', () {
    // Google checks the OAuth consent screen's home page (app.guillaumedamiens.com): the app's name, its privacy policy
    final page = File('web/index.html').readAsStringSync();
    expect(page, contains("<title>Nav'</title>"));
    final noscript = RegExp(r'<noscript>(.*?)</noscript>', dotAll: true).firstMatch(page)?.group(1);
    expect(noscript, isNotNull);
    expect(noscript, contains("Nav'"));
    expect(noscript, contains('href="/privacy"'));
  });
}
