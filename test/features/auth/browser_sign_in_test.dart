import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/api_exception.dart';
import 'package:website_app/core/api/auth_api.dart';
import 'package:website_app/features/auth/google/browser_sign_in_io.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/fake_backend.dart';

/// The desktop apps' Google sign-in, on a real port of the loopback: the tests play the browser
void main() {
  late FakeBackend backend;
  late HttpOverrides? overrides;

  /// The port the app said it listens on
  int port() => (backend.requestsTo('/api/auth/google/desktop').single.data as Map)['port'] as int;

  /// The browser, sent to the app's port by the backend: status and page
  Future<(int, String)> visit(String pathAndQuery) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:${port()}$pathAndQuery'));
      final response = await request.close();
      return (response.statusCode, await utf8.decodeStream(response));
    } finally {
      client.close(force: true);
    }
  }

  setUp(() {
    // flutter_test answers 400 to every HttpClient: the browser of these tests is a real one
    overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    useLocale(const Locale('fr'));
    backend = FakeBackend()
      ..post('/api/auth/google/desktop', {
        'authorizationUrl': 'https://accounts.example.com/auth?state=the-state',
        'state': 'the-state',
        'verifier': 'the-verifier',
      })
      ..post('/api/auth/google/desktop/token', {'jwt': 'access', 'refreshToken': 'refresh', 'expiresIn': 3600});
  });

  tearDown(() => HttpOverrides.global = overrides);

  test('opens Google\'s page, waits for the browser to come back, exchanges its code with the verifier', () async {
    final opened = <Uri>[];
    final pages = <(int, String)>[];
    final signIn = LoopbackBrowserSignIn(AuthApi(backend.dio()), openBrowser: (url) async {
      opened.add(url);
      unawaited(visit('/?code=one-time-code&state=the-state').then(pages.add));
    });

    final tokens = await signIn.signIn();

    expect(opened, [Uri.parse('https://accounts.example.com/auth?state=the-state')]);
    expect(tokens?.jwt, 'access');
    expect(tokens?.refreshToken, 'refresh');
    expect(backend.requestsTo('/api/auth/google/desktop/token').single.data, {'code': 'one-time-code', 'verifier': 'the-verifier'});
    expect(pages.single.$1, 200);
    expect(pages.single.$2, contains('Vous pouvez fermer cet onglet et revenir à l&#39;application.'));
    // The page takes the code out of the address bar
    expect(pages.single.$2, contains('history.replaceState'));
    // Nothing listens once the sign-in is over
    await expectLater(visit('/'), throwsA(isA<SocketException>()));
  });

  test('a visit that is not this sign-in is not answered', () async {
    final others = <int>[];
    final signIn = LoopbackBrowserSignIn(AuthApi(backend.dio()), openBrowser: (url) async {
      unawaited(() async {
        others.add((await visit('/favicon.ico')).$1);
        others.add((await visit('/?code=someone-elses&state=another-state')).$1);
        others.add((await visit('/?code=no-state')).$1);
        await visit('/?code=one-time-code&state=the-state');
      }());
    });

    await signIn.signIn();

    expect(others, [404, 404, 404]);
    expect(backend.requestsTo('/api/auth/google/desktop/token').single.data, {'code': 'one-time-code', 'verifier': 'the-verifier'});
  });

  test('a refusal on Google\'s page gives up quietly', () async {
    final pages = <(int, String)>[];
    final signIn = LoopbackBrowserSignIn(AuthApi(backend.dio()), openBrowser: (url) async {
      unawaited(visit('/?error=access_denied&state=the-state').then(pages.add));
    });

    expect(await signIn.signIn(), isNull);

    expect(pages.single.$2, contains('Connexion annulée'));
    expect(backend.requestsTo('/api/auth/google/desktop/token'), isEmpty);
  });

  test('a sign-in the backend could not finish with Google is an error', () async {
    final pages = <(int, String)>[];
    final signIn = LoopbackBrowserSignIn(AuthApi(backend.dio()), openBrowser: (url) async {
      unawaited(visit('/?error=failed&state=the-state').then(pages.add));
    });

    await expectLater(signIn.signIn(), throwsA(isA<ApiException>().having((e) => e.message, 'message', currentL10n.googleSignInFailed)));

    expect(pages.single.$2, contains(currentL10n.googleSignInFailed));
    expect(backend.requestsTo('/api/auth/google/desktop/token'), isEmpty);
  });

  test('a code the backend refuses is an error', () async {
    backend.on('POST', '/api/auth/google/desktop/token', (_) => FakeResponse.problem(401, detail: 'Invalid or expired sign-in code'));
    final signIn = LoopbackBrowserSignIn(AuthApi(backend.dio()), openBrowser: (url) async {
      unawaited(visit('/?code=expired&state=the-state'));
    });

    await expectLater(signIn.signIn(), throwsA(isA<ApiException>().having((e) => e.message, 'message', currentL10n.googleSignInFailed)));
  });

  test('the user gives up in the app: the port is closed', () async {
    late LoopbackBrowserSignIn signIn;
    signIn = LoopbackBrowserSignIn(AuthApi(backend.dio()), openBrowser: (url) async {
      Timer(const Duration(milliseconds: 20), signIn.cancel);
    });

    expect(await signIn.signIn(), isNull);

    await expectLater(visit('/?code=late&state=the-state'), throwsA(isA<SocketException>()));
    expect(backend.requestsTo('/api/auth/google/desktop/token'), isEmpty);
  });

  test('gives up when the browser never comes back', () async {
    final signIn = LoopbackBrowserSignIn(AuthApi(backend.dio()), openBrowser: (url) async {}, patience: const Duration(milliseconds: 30));

    expect(await signIn.signIn(), isNull);
  });

  test('a new sign-in replaces the one going on', () async {
    final ports = <int>[];
    late LoopbackBrowserSignIn signIn;
    signIn = LoopbackBrowserSignIn(AuthApi(backend.dio()), openBrowser: (url) async {
      ports.add((backend.requestsTo('/api/auth/google/desktop').last.data as Map)['port'] as int);
    });

    final first = signIn.signIn();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final second = signIn.signIn();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await first, isNull);
    final client = HttpClient();
    await (await client.getUrl(Uri.parse('http://127.0.0.1:${ports.last}/?code=second&state=the-state'))).close();
    client.close(force: true);
    expect((await second)?.jwt, 'access');
  });

  test('says so when no browser can be opened', () async {
    final signIn = LoopbackBrowserSignIn(AuthApi(backend.dio()),
        openBrowser: (url) async => throw const ProcessException('xdg-open', [], 'No such file or directory', 2));

    await expectLater(signIn.signIn(), throwsA(isA<ApiException>().having((e) => e.message, 'message', currentL10n.browserOpenFailed)));
  });

  test('without the backend\'s Google secret, nothing is opened', () async {
    backend.on('POST', '/api/auth/google/desktop',
        (_) => FakeResponse.problem(503, detail: 'Sign-in with Google is not configured for desktop apps'));
    final opened = <Uri>[];
    final signIn = LoopbackBrowserSignIn(AuthApi(backend.dio()), openBrowser: (url) async => opened.add(url));

    await expectLater(signIn.signIn(), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)));

    expect(opened, isEmpty);
  });

  test('only web pages are handed to the system', () async {
    await expectLater(openInSystemBrowser(Uri.parse('file:///etc/passwd')), throwsArgumentError);
    await expectLater(openInSystemBrowser(Uri.parse('javascript:alert(1)')), throwsArgumentError);
  });
}
