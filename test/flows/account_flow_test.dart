import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// Signing in and out, the account page, the welcome pages
void main() {
  testWidgets('signs in with a password from the account menu, then out', (tester) async {
    final backend = standardBackend();
    backend.post('/api/signin', {'jwt': 'jwt', 'refreshToken': 'refresh', 'expiresIn': 3600});
    backend.post('/api/logout', null, status: 204);
    await pumpApp(tester, backend);

    await tapOn(tester, find.byTooltip(currentL10n.account));
    await tapOn(tester, find.text(currentL10n.signInAction));
    await tester.enterText(find.widgetWithText(TextField, currentL10n.username), 'ada');
    await tester.enterText(find.widgetWithText(TextField, currentL10n.password), 'correct horse');
    await tapOn(tester, find.widgetWithText(FilledButton, currentL10n.signInAction));

    expect(backend.requestsTo('/api/signin').single.data, {'username': 'ada', 'password': 'correct horse'});
    expect(find.text(currentL10n.homeNearby), findsOneWidget);
    expect(backend.requestsTo('/api/v2/me/favorites'), isNotEmpty);

    // The account page
    await tapOn(tester, find.byTooltip(currentL10n.account));
    await tapOn(tester, find.text(currentL10n.accountTitle));
    expect(find.textContaining('ada@example.com'), findsOneWidget);

    await tapOn(tester, find.text(currentL10n.signOut));
    expect(backend.requestsTo('/api/logout'), hasLength(1));

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
}
