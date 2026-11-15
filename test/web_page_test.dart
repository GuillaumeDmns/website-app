import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the web page loads no file of another site itself, and MapLibre at exact versions', () {
    final page = File('web/index.html').readAsStringSync();
    final external = RegExp(r'<(script|link)\b[^>]*\b(?:src|href)="https?://[^"]+"[^>]*>', dotAll: true)
        .allMatches(page)
        .map((tag) => tag.group(0)!)
        .where((tag) => tag.startsWith('<script') || tag.contains('rel="stylesheet"'))
        .toList();
    expect(external, isEmpty);

    // The package maplibre loads maplibre-gl-js and PMTiles from jsDelivr: a version, never a range ("^6.0.0" by
    // default), so that a new release only comes with a change of the page
    for (final option in ['maplibreGlVersion', 'pmtilesVersion']) {
      expect(page, contains(RegExp("$option: '\\d+\\.\\d+\\.\\d+'")), reason: option);
    }
    expect(page, isNot(contains('maplibreGlBaseUrl')));
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
