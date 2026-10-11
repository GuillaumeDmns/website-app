import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// The whole app, tapped through like a user (the backend is faked)
void main() {
  testWidgets('a new guest sees the departures around them', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend);

    expect(find.text(currentL10n.homeNearby), findsOneWidget);
    expect(find.text('Châtelet'), findsWidgets);
    expect(find.text('Nation'), findsWidgets);
    expect(backend.requestsTo('/api/auth/guest'), hasLength(1));
    expect(backend.requestsTo('/api/v2/nearby/departures').first.headers['Authorization'], 'Bearer guest-token');

    await closeApp(tester);
  });
}
