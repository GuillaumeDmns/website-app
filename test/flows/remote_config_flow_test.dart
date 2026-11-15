import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/remote_config/remote_config.dart';
import 'package:website_app/features/remote_config/remote_config_widgets.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// What the backend tells the app at start-up
void main() {
  testWidgets('a version the backend no longer supports only asks to be updated', (tester) async {
    final backend = standardBackend()..get('/api/v2/app-config', const RemoteConfig(minVersions: {'android': '1.0.0'}).toJson());
    await pumpApp(tester, backend, overrides: [appVersionProvider.overrideWithValue('0.14.0')]);

    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    expect(find.text(currentL10n.updateRequiredTitle), findsOneWidget);
    expect(find.text(currentL10n.updateRequiredAction), findsOneWidget);
    expect(find.text(currentL10n.homeSearchHint), findsNothing);
    await closeApp(tester);
  });

  testWidgets('a supported version shows the app, with the message for everyone on its home page', (tester) async {
    final backend = standardBackend()
      ..get('/api/v2/app-config', const RemoteConfig(minVersions: {'android': '0.14.0'}, notice: {'fr': 'Grève mardi : trafic très perturbé'}).toJson());
    await pumpApp(tester, backend, overrides: [appVersionProvider.overrideWithValue('0.14.0')]);

    expect(find.byType(UpdateRequiredScreen), findsNothing);
    expect(find.text(currentL10n.homeSearchHint), findsOneWidget);
    expect(find.text('Grève mardi : trafic très perturbé'), findsOneWidget);
    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('no message: nothing more on the home page', (tester) async {
    await pumpApp(tester, standardBackend());
    expect(find.text(currentL10n.homeSearchHint), findsOneWidget);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
    await closeApp(tester);
  });
}
