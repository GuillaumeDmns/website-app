import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:website_app/app/app.dart';
import 'package:website_app/app/router.dart';
import 'package:website_app/app/routes.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/widgets/line_badge.dart';
import 'package:website_app/features/home/home_screen.dart';
import 'package:website_app/features/home_widget/widget_setup_screen.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/fake_backend.dart';
import '../support/fake_home_widget.dart';
import '../support/memory_store.dart';
import '../support/samples.dart';
import '../support/standard_backend.dart';
import '../support/test_app.dart';

class _FakeBridge implements WidgetBridge {
  _FakeBridge(this.allowed);

  bool allowed;
  int asked = 0;

  @override
  Future<bool> canShowTimeLeft() async => allowed;

  @override
  Future<void> askTimeLeft() async => asked++;
}

/// Android's home screen widget: its user chooses the stop it shows, then its lines if they want
void main() {
  late _FakeBridge bridge;
  setUp(() => widgetBridge = bridge = _FakeBridge(false));

  Finder lineChip(String lineId) => find.ancestor(
        of: find.byWidgetPredicate((widget) => widget is LineBadge && widget.line.id == lineId),
        matching: find.byType(FilterChip),
      );

  Future<void> open(WidgetTester tester, String location) async {
    ProviderScope.containerOf(tester.element(find.byType(MobilityApp))).read(routerProvider).go(location);
    await settle(tester);
  }

  testWidgets('a stop searched, one of its lines, saved for the widget', (tester) async {
    final widgets = FakeHomeWidget(widgetIds: [7]);
    final backend = standardBackend();
    await pumpApp(tester, backend);
    await open(tester, Routes.widgetSetup(7));
    expect(find.text(currentL10n.widgetSetupTitle), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'chat');
    await settle(tester);
    // Stops only: no address nor place; never the user's position
    expect(find.text('10 Rue de Rivoli (Paris)'), findsNothing);
    expect(backend.requestsTo('/api/v2/search').last.queryParameters, isNot(contains('lat')));
    await tapOn(tester, find.text('Châtelet (Paris)'));

    // Its lines, all of them at first
    expect(find.text(currentL10n.widgetSetupLines), findsOneWidget);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, currentL10n.widgetSetupAll)).selected, isTrue);
    await tapOn(tester, lineChip(metro1.id));
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, currentL10n.widgetSetupAll)).selected, isFalse);

    // The time left needs Android's exact alarms: the page offers to allow them
    await tapOn(tester, find.text(currentL10n.widgetTimeLeftTitle));
    expect(bridge.asked, 1);

    await tapOn(tester, find.text(currentL10n.widgetSetupConfirm));
    expect(widgets.data['w7_stop_id'], 'IDFM:70001');
    expect(widgets.data['w7_stop_name'], 'Châtelet (Paris)');
    expect(widgets.data['w7_filter'], metro1.id);
    expect(widgets.data['w7_rows']!.trimRight().split('\n'), [startsWith('1|')]);
    expect(widgets.redraws, greaterThan(0));
    // Opened from the widget in the app: back to the home page
    expect(find.byType(HomeScreen), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a favorite stop in one tap; the time left already shown says nothing', (tester) async {
    bridge.allowed = true;
    final widgets = FakeHomeWidget(widgetIds: [9]);
    final favorite = Favorite(id: -2, kind: FavoriteKind.stop, stopAreaId: chatelet.id, label: chatelet.name, stop: chatelet);
    await pumpApp(tester, standardBackend(), store: MemoryStore({'favorites': [favorite.toJson()]}));
    await open(tester, Routes.widgetSetup(9));

    expect(find.text(currentL10n.widgetSetupFavorites), findsOneWidget);
    await tapOn(tester, find.text(chatelet.name));
    expect(find.text(currentL10n.widgetTimeLeftTitle), findsNothing);
    await tapOn(tester, find.text(currentL10n.widgetSetupConfirm));

    expect(widgets.data['w9_stop_id'], chatelet.id);
    // Every direction
    expect(widgets.data['w9_filter'], isNull);

    await closeApp(tester);
  });

  testWidgets('placed by the launcher: saving ends the system setup', (tester) async {
    final widgets = FakeHomeWidget(widgetIds: [4]);
    final favorite = Favorite(id: -2, kind: FavoriteKind.stop, stopAreaId: chatelet.id, label: chatelet.name, stop: chatelet);
    await pumpApp(tester, standardBackend(), store: MemoryStore({'favorites': [favorite.toJson()]}));
    await open(tester, Routes.widgetSetup(4, configure: true));

    await tapOn(tester, find.text(chatelet.name));
    await tapOn(tester, find.text(currentL10n.widgetSetupConfirm));
    expect(widgets.configureFinished, isTrue);

    await closeApp(tester);
  });

  testWidgets('reconfigured: it opens on the stop and lines it shows', (tester) async {
    FakeHomeWidget(widgetIds: [5], data: {'w5_stop_id': chatelet.id, 'w5_stop_name': 'Châtelet', 'w5_filter': metro1.id});
    await pumpApp(tester, standardBackend());
    await open(tester, Routes.widgetSetup(5, configure: true));

    expect(find.text(currentL10n.widgetSetupLines), findsOneWidget);
    expect(tester.widget<FilterChip>(lineChip(metro1.id)).selected, isTrue);
    // Another stop is a tap away
    await tapOn(tester, find.text(currentL10n.widgetSetupChange));
    expect(find.text(currentL10n.widgetSetupTitle), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a line under two ids and modes (RER D: RATP and SNCF) is one chip, for both', (tester) async {
    final widgets = FakeHomeWidget(widgetIds: [8]);
    final backend = standardBackend();
    const sncfA = LineSummary(id: 'C99999', name: 'A', mode: TransportMode.transilien, color: 'EB2132', textColor: 'FFFFFF');
    const replacementA = LineSummary(id: 'C99998', name: 'A', mode: TransportMode.bus, color: 'EB2132', textColor: 'FFFFFF');
    backend.on('GET', '/api/v2/stops/IDFM:70001/departures', (_) => FakeResponse(StopDepartures(
          stop: chatelet,
          realtimeAvailable: true,
          lines: [
            LineDepartures(line: rerA, destination: 'Boissy', departures: [departure(DateTime.now().add(const Duration(minutes: 3)))]),
            LineDepartures(line: sncfA, destination: 'CERGY', departures: [departure(DateTime.now().add(const Duration(minutes: 5)))]),
            LineDepartures(line: metro1, destination: 'Nation', departures: [departure(DateTime.now().add(const Duration(minutes: 4)))]),
            // A replacement bus named after the RER: a line of its own, its mode beside its badge
            LineDepartures(line: replacementA, destination: 'BOISSY', departures: [departure(DateTime.now().add(const Duration(minutes: 6)))]),
          ],
        ).toJson()));
    await pumpApp(tester, backend);
    await open(tester, Routes.widgetSetup(8));
    await tester.enterText(find.byType(TextField), 'chat');
    await settle(tester);
    await tapOn(tester, find.text('Châtelet (Paris)'));

    expect(lineChip(rerA.id), findsOneWidget);
    expect(find.descendant(of: lineChip(replacementA.id), matching: find.text(TransportMode.bus.label)), findsOneWidget);
    await tapOn(tester, lineChip(rerA.id));
    await tapOn(tester, find.text(currentL10n.widgetSetupConfirm));
    expect(widgets.data['w8_filter']!.split('\n').toSet(), {rerA.id, sncfA.id});
    expect(widgets.data['w8_rows']!.trimRight().split('\n'), hasLength(2));

    await closeApp(tester);
  });

  testWidgets('a widget placed before the welcome pages were seen opens its setup, not them', (tester) async {
    FakeHomeWidget(widgetIds: [6]);
    await pumpApp(tester, standardBackend(), onboardingDone: false);
    await open(tester, Routes.widgetSetup(6, configure: true));
    expect(find.text(currentL10n.widgetSetupTitle), findsOneWidget);

    await closeApp(tester);
  });
}
