import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/features/about/about_screen.dart';
import 'package:website_app/l10n/l10n.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  test("a build of tool/build.sh shows git's version and its build number", () {
    expect(appVersionLabel(currentL10n, version: '0.4.0', build: '40000'), '0.4.0 (40000)');
    expect(appVersionLabel(currentL10n, version: '0.4.0-12', build: '40012'), '0.4.0-12 (40012)');
  });

  test('a plain flutter build says it is a development build', () {
    expect(appVersionLabel(currentL10n, version: '', build: ''), 'Version de développement');
  });

  test('the details give the commit, the environment, the backend and its release, the platform', () {
    expect(appBuildDetails(currentL10n, commit: '5d6e7f8-dirty', server: '0.6.0'), 'commit 5d6e7f8-dirty · dev · localhost · serveur 0.6.0 · android');
    expect(appBuildDetails(currentL10n, commit: ''), 'dev · localhost · android');
  });
}
