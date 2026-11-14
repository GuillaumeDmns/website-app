
import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/router.dart';
import 'package:website_app/app/routes.dart';
import 'package:website_app/core/api/api_exception.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/auth/account_photo.dart';
import 'package:website_app/features/auth/google/browser_sign_in.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/fake_backend.dart';
import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// Signing in and out, the account page, the welcome pages
void main() {
  testWidgets('signs in with Google from the account menu, then out', (tester) async {
    final backend = standardBackend();
    backend.post('/api/logout', null, status: 204);
    await pumpApp(tester, backend);

    await tapOn(tester, find.byTooltip(currentL10n.account));
    await tapOn(tester, find.text(currentL10n.signInAction));
    await tapOn(tester, find.text(currentL10n.continueWithGoogle));

    expect(backend.requestsTo('/api/auth/google').single.data, {'idToken': 'test-google-id-token'});
    expect(find.text(currentL10n.homeNearby), findsOneWidget);
    expect(backend.requestsTo('/api/v2/me/favorites'), isNotEmpty);

    // The account page
    await tapOn(tester, find.byTooltip(currentL10n.account));
    await tapOn(tester, find.text(currentL10n.accountTitle));
    expect(find.textContaining('ada@example.com'), findsOneWidget);
    // Not an admin: no API tokens
    expect(find.text(currentL10n.apiTokensTitle), findsNothing);

    await tapOn(tester, find.text(currentL10n.signOut));
    expect(backend.requestsTo('/api/logout'), hasLength(1));

    await closeApp(tester);
  });

  testWidgets("the avatar of the search opens who uses the app and its settings; signed in, the Google picture", (tester) async {
    final backend = standardBackend();
    backend.post('/api/logout', null, status: 204);
    const picture = 'https://lh3.googleusercontent.com/a/ada=s96-c';
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final idToken = '${part({'alg': 'RS256'})}.${part({'sub': '42', 'picture': picture})}.signature';
    final store = await pumpApp(tester, backend, googleAccountChooser: () async => idToken);

    // In the search box, not beside it
    final avatar = find.byTooltip(currentL10n.account);
    final photo = find.descendant(of: find.byType(AccountAvatar), matching: find.byType(Image));
    expect(find.descendant(of: find.widgetWithText(InkWell, currentL10n.homeSearchHint), matching: avatar), findsOneWidget);
    await tapOn(tester, avatar);
    // A guest: what signing in adds, then the settings
    expect(find.text(currentL10n.accountSheetGuest), findsOneWidget);
    expect(find.text(currentL10n.guestModeHint), findsOneWidget);
    expect(find.text(currentL10n.language), findsOneWidget);
    expect(find.text(currentL10n.about), findsOneWidget);
    expect(find.text(currentL10n.signOut), findsNothing);
    expect(photo, findsNothing);

    await tapOn(tester, find.text(currentL10n.signInAction));
    await tapOn(tester, find.text(currentL10n.continueWithGoogle));
    // The picture's address from the ID token, kept on the device only
    expect(store.values['account_photo'], jsonEncode(picture));
    expect(tester.widget<Image>(photo).image, isA<NetworkImage>().having((image) => image.url, 'url', picture));

    await tapOn(tester, avatar);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('ada@example.com'), findsOneWidget);
    await tapOn(tester, find.text(currentL10n.signOut));
    expect(store.values.containsKey('account_photo'), isFalse);
    expect(photo, findsNothing);

    await closeApp(tester);
  });

  testWidgets('without Google sign-in on the device, the app goes on as a guest', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend, googleAccountChooser: null);

    await tapOn(tester, find.byTooltip(currentL10n.account));
    await tapOn(tester, find.text(currentL10n.signInAction));

    expect(find.text(currentL10n.googleSignInUnavailable), findsOneWidget);
    expect(find.text(currentL10n.continueWithGoogle), findsNothing);
    await tapOn(tester, find.text(currentL10n.continueAsGuest));
    expect(find.text(currentL10n.homeNearby), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('on Linux and Windows, signs in through the browser', (tester) async {
    final backend = standardBackend();
    final browser = _TestBrowserSignIn();
    await pumpApp(tester, backend, googleAccountChooser: null, googleBrowserSignIn: browser);

    await tapOn(tester, find.byTooltip(currentL10n.account));
    await tapOn(tester, find.text(currentL10n.signInAction));
    await tapOn(tester, find.text(currentL10n.continueWithGoogle));

    // The browser is open on Google's page: the app waits, and offers to give up
    expect(find.text(currentL10n.browserSignInWaiting), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, currentL10n.continueWithGoogle)).onPressed, isNull);

    browser.comesBackWith(const AuthTokens(jwt: 'desktop-access-token', refreshToken: 'desktop-refresh-token', expiresIn: 3600));
    await settle(tester);

    expect(find.text(currentL10n.homeNearby), findsOneWidget);
    expect(backend.requestsTo('/api/v2/me/favorites').last.headers['Authorization'], 'Bearer desktop-access-token');
    // No ID token on these platforms: the backend got it from Google itself
    expect(backend.requestsTo('/api/auth/google'), isEmpty);

    await closeApp(tester);
  });

  testWidgets('giving up the sign-in in the browser leaves the app as it was', (tester) async {
    final backend = standardBackend();
    final browser = _TestBrowserSignIn();
    await pumpApp(tester, backend, googleAccountChooser: null, googleBrowserSignIn: browser);

    await tapOn(tester, find.byTooltip(currentL10n.account));
    await tapOn(tester, find.text(currentL10n.signInAction));
    await tapOn(tester, find.text(currentL10n.continueWithGoogle));
    await tapOn(tester, find.text(MaterialLocalizations.of(tester.element(find.text(currentL10n.browserSignInWaiting))).cancelButtonLabel));

    expect(browser.cancelled, isTrue);
    expect(find.text(currentL10n.browserSignInWaiting), findsNothing);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, currentL10n.continueWithGoogle)).onPressed, isNotNull);

    // A sign-in that fails says so, and can be tried again
    browser.failure = ApiException(currentL10n.browserOpenFailed);
    await tapOn(tester, find.text(currentL10n.continueWithGoogle));
    expect(find.text(currentL10n.browserOpenFailed), findsOneWidget);
    expect(find.text(currentL10n.browserSignInWaiting), findsNothing);

    await closeApp(tester);
  });

  testWidgets('an admin creates an API token for Bruno, sees it once, then revokes it', (tester) async {
    final backend = standardBackend();
    final tokens = <Map<String, Object?>>[];
    backend.get('/api/v2/me', const Account(email: 'admin@example.com', firstName: 'Admin', role: 'ROLE_ADMIN', google: true).toJson());
    backend.on('GET', '/api/v2/me/api-tokens', (_) => FakeResponse(tokens));
    backend.on('POST', '/api/v2/me/api-tokens', (request) {
      final token = {'id': 1, 'name': (request.data as Map)['name'], 'createdAt': '2026-10-11T08:00:00Z', 'expiresAt': '2027-10-11T08:00:00Z'};
      tokens.add(token);
      return FakeResponse({'apiToken': token, 'token': 'gdpat_secret-value'}, status: 201);
    });
    backend.on('DELETE', '/api/v2/me/api-tokens/1', (_) {
      tokens.clear();
      return const FakeResponse(null, status: 204);
    });
    await pumpApp(tester, backend, refreshToken: 'stored');

    await tapOn(tester, find.byTooltip(currentL10n.account));
    await tapOn(tester, find.text(currentL10n.accountTitle));
    expect(find.text(currentL10n.apiTokensEmpty), findsOneWidget);

    await tapOn(tester, find.text(currentL10n.apiTokenCreate));
    await tapOn(tester, find.widgetWithText(FilledButton, currentL10n.apiTokenCreate));
    expect(backend.requestsTo('/api/v2/me/api-tokens', method: 'POST').single.data, {'name': 'Bruno'});
    expect(find.text('gdpat_secret-value'), findsOneWidget);
    expect(find.text(currentL10n.apiTokenCopyNow), findsOneWidget);

    await tapOn(tester, find.text(MaterialLocalizations.of(tester.element(find.byType(AlertDialog))).okButtonLabel));
    expect(find.text('gdpat_secret-value'), findsNothing);
    expect(find.text('Bruno'), findsOneWidget);

    await tapOn(tester, find.byTooltip(currentL10n.apiTokenRevoke('Bruno')));
    expect(backend.requestsTo('/api/v2/me/api-tokens/1', method: 'DELETE'), hasLength(1));
    expect(find.text(currentL10n.apiTokensEmpty), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a signed-in user keeps the session at the next start', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend, refreshToken: 'stored');

    expect(backend.requestsTo('/api/token/refresh'), hasLength(1));
    expect(backend.requestsTo('/api/v2/nearby/departures').first.headers['Authorization'], 'Bearer access-token');
    expect(backend.requestsTo('/api/auth/guest'), isEmpty);

    await closeApp(tester);
  });

  testWidgets('the welcome pages come once, then the home page', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend, onboardingDone: false);

    expect(find.text(currentL10n.welcomeTitle), findsOneWidget);
    await tapOn(tester, find.text(currentL10n.skip));

    expect(find.text(currentL10n.homeNearby), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('welcome pages: an address saved is said above the buttons, not over them', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend, onboardingDone: false);

    await tapOn(tester, find.text(currentL10n.next));
    await tapOn(tester, find.text(currentL10n.next));
    expect(find.text(currentL10n.welcomePlacesTitle), findsOneWidget);
    await tapOn(tester, find.text(currentL10n.home));
    await tester.enterText(find.byType(TextField), 'rivoli');
    await settle(tester);
    await tapOn(tester, find.text('10 Rue de Rivoli (Paris)'));

    final saved = find.text(currentL10n.favoriteSaved(currentL10n.home));
    expect(saved, findsOneWidget);
    final message = tester.getRect(find.ancestor(of: saved, matching: find.byType(SnackBar)));
    final next = tester.getRect(find.widgetWithText(FilledButton, currentL10n.next));
    expect(message.bottom, lessThanOrEqualTo(next.top));
    // Still reachable under it
    await tapOn(tester, find.text(currentL10n.next));
    expect(find.text(currentL10n.welcomeAccountTitle), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('the legal notice is one tap away from About and from the sign-in page', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend);

    await tapOn(tester, find.byTooltip(currentL10n.account));
    await tapOn(tester, find.text(currentL10n.about));
    // The version, for bug reports (a test build is a development build), copied in one tap
    expect(find.text(currentL10n.aboutDevBuild), findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tapOn(tester, find.byTooltip(currentL10n.aboutCopyVersion));
    expect(copied, '${currentL10n.appTitle} ${currentL10n.aboutDevBuild} · dev · localhost · ${currentL10n.aboutServerVersion('0.6.0')} · android');
    expect(find.text(currentL10n.aboutVersionCopied), findsOneWidget);
    await tapOn(tester, find.text(currentL10n.privacy));
    expect(find.text(currentL10n.privacyHost), findsOneWidget);
    expect(find.text(currentL10n.privacyRights), findsOneWidget);
    await tapOn(tester, find.byTooltip(currentL10n.back));
    expect(find.text(currentL10n.aboutData), findsOneWidget);

    await tapOn(tester, find.byTooltip(currentL10n.back));
    await tapOn(tester, find.byTooltip(currentL10n.account));
    await tapOn(tester, find.text(currentL10n.signInAction));
    await tapOn(tester, find.text(currentL10n.privacy));
    expect(find.text(currentL10n.privacyPublisher), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a link to the legal notice opens it before the welcome pages', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend, onboardingDone: false);
    expect(find.text(currentL10n.welcomeTitle), findsOneWidget);

    ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(routerProvider).go(Routes.privacy);
    await settle(tester);

    expect(find.text(currentL10n.privacyPublisher), findsOneWidget);
    expect(find.text(currentL10n.welcomeTitle), findsNothing);

    await closeApp(tester);
  });
}

/// The sign-in through the system browser, with the user in the tests' hands
class _TestBrowserSignIn implements BrowserSignIn {
  Completer<AuthTokens?>? _waiting;
  bool cancelled = false;

  /// What the next sign-in fails with
  ApiException? failure;

  @override
  Future<AuthTokens?> signIn() async {
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    return (_waiting = Completer<AuthTokens?>()).future;
  }

  void comesBackWith(AuthTokens tokens) => _waiting!.complete(tokens);

  @override
  void cancel() {
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) {
      cancelled = true;
      waiting.complete(null);
    }
  }
}
