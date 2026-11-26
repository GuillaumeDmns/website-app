import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/theme.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/journey/widgets/journey_sections.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  Future<void> pump(WidgetTester tester, JourneySection section) => tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          locale: const Locale('fr'),
          localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: JourneySectionTile(section: section, isFirst: false, onChoose: (_) {}, focused: false, onFocus: (_) {}),
            ),
          ),
        ),
      ));

  testWidgets('a replacement bus is said so above its direction, not taken for the train of its badge', (tester) async {
    // The buses replacing the Transilien L at night: the L's badge
    const bus = LineSummary(id: 'C01847', name: 'L', mode: TransportMode.bus, color: 'D282BE', textColor: 'FFFFFF', replacement: true);
    await pump(tester, transit(DateTime.now().toUtc(), 32 * 60, line: bus));
    expect(find.text(currentL10n.replacementBus), findsOneWidget);
    expect(find.text(currentL10n.direction('Nation')), findsOneWidget);

    await pump(tester, transit(DateTime.now().toUtc(), 32 * 60, line: rerA));
    expect(find.text(currentL10n.replacementBus), findsNothing);
  });
}
