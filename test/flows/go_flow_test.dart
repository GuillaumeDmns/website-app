import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/platform/live_journey.dart';
import 'package:website_app/features/go/go_bar.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_screen.dart';
import 'package:website_app/features/go/go_state.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/go/widgets/go_ride_card.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/samples.dart';
import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// A journey followed in GO mode at its different moments: the controller is replaced by one holding the state (no
/// GPS in tests), the screens are the app's
class _FollowedJourney extends GoController {
  _FollowedJourney(this.initial);

  final GoState initial;

  @override
  GoState? build() => initial;
}

void main() {
  final now = DateTime.now().toUtc();
  DateTime inMinutes(int minutes) => now.add(Duration(minutes: minutes));

  // Walk 4 min to Châtelet (two turns), metro 1 in 6 min to Nation through Gare de Lyon, walk 3 min
  final plan = journey([
    walk(inMinutes(0), 240).copyWith(length: 500, steps: const [
      WalkStep(instruction: "Marchez vers l'est sur Rue de Rivoli", length: 300, offset: 0),
      WalkStep(instruction: 'Tournez à gauche sur Rue des Halles', length: 200, offset: 300, direction: -90, name: 'Rue des Halles'),
    ]),
    transit(inMinutes(6), 480, via: [gareDeLyon]).copyWith(boardingPositions: ['front']),
    walk(inMinutes(14), 180, from: point(nation), to: const JourneyPoint(name: 'Cours de Vincennes', lat: 48.8475, lon: 2.4000)),
  ]);
  final tracker = GoTracker(plan);

  GoState followed(GoProgress progress, {LatLng? position}) => GoState(
        tracker: tracker,
        request: const JourneyRequest(),
        progress: progress.copyWith(lastFixAt: DateTime.now()),
        startedAt: now,
        plannedArrival: plan.arrival,
        position: position,
      );

  Future<void> openGo(WidgetTester tester, GoState state) async {
    await pumpApp(tester, standardBackend(), overrides: [goControllerProvider.overrideWith(() => _FollowedJourney(state))]);
    // The bar over the map opens GO
    await tapOn(tester, find.text(currentL10n.go).first);
    expect(find.byType(GoScreen), findsOneWidget);
  }

  testWidgets('walking: the next turn over the map, the time to spare under it, the turns folded, what comes next', (tester) async {
    final along = tracker.steps.first.line.length * 260 / 500;
    await openGo(tester, followed(GoProgress(step: 0, phase: GoPhase.moving, along: along), position: LatLng(chatelet.lat, chatelet.lon)));

    // Once, in the banner over the map: what to do, its distance, where
    final banner = find.byType(GoBanner);
    expect(banner, findsOneWidget);
    expect(find.text(currentL10n.goTurnLeft), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text(currentL10n.goKickerTowards(currentL10n.goKickerOnFoot, 'Châtelet'))),
        findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text('Rue des Halles')), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text('m')), findsOneWidget);
    // In the capsule: the time to spare on the metro, the following step, the correction at hand
    expect(find.textContaining("d'avance sur le Métro 1 de"), findsOneWidget);
    expect(find.text(currentL10n.goThen), findsOneWidget);
    expect(find.text(currentL10n.goTracking), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsWidgets);

    // The turns, folded so that the panel stays low
    expect(find.text('Tournez à gauche sur Rue des Halles'), findsNothing);
    await tapOn(tester, find.textContaining(currentL10n.goTurnByTurn));
    expect(find.text('Tournez à gauche sur Rue des Halles'), findsOneWidget);

    // GO got it wrong: the user says where they are
    await tapOn(tester, find.text(currentL10n.goCorrect));
    expect(find.text(currentL10n.goCorrectTitle), findsOneWidget);
    expect(find.text(currentL10n.goImArrived), findsOneWidget);
    expect(find.text('Métro 1 → ${tracker.steps[1].section.headsign}'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('waiting: the countdown over the map, where to board, the departures and the next one if missed', (tester) async {
    await openGo(tester, followed(const GoProgress(step: 1, phase: GoPhase.waiting), position: LatLng(chatelet.lat, chatelet.lon)));

    // The banner: the line to take and the minutes left (6 at most)
    final banner = find.byType(GoBanner);
    expect(find.descendant(of: banner, matching: find.text(currentL10n.goTake('Métro 1'))), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text(currentL10n.minutesUnit)), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.textContaining(currentL10n.goBoard(currentL10n.boardFront))), findsOneWidget);
    // Where to board along the train, once, in the capsule
    expect(find.byType(TrainPositions), findsOneWidget);
    expect(find.textContaining(currentL10n.goIfMissed('', 0).split(':').first), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('looking at the other steps leaves the sheet where it is: it fits the step in progress', (tester) async {
    await openGo(tester, followed(GoProgress(step: 0, phase: GoPhase.moving, along: 40), position: LatLng(chatelet.lat, chatelet.lon)));
    double sheetTop() => tester
        .getTopLeft(find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Material)).first)
        .dy;
    final top = sheetTop();
    // The map keeps at least half of the screen
    expect(top, greaterThanOrEqualTo(915 * 0.5 - 1));

    // The metro's card, then the arrival's: swiped to, the sheet stays
    for (var card = 0; card < 3; card++) {
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settle(tester);
      expect(sheetTop(), closeTo(top, 1));
    }
    // The arrival's card shown
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 3);
    // Back to the step in progress
    for (var card = 0; card < 3; card++) {
      await tester.drag(find.byType(PageView), const Offset(300, 0));
      await settle(tester);
    }
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    expect(sheetTop(), closeTo(top, 1));

    await closeApp(tester);
  });

  testWidgets('on board: the stops left counted over the map, on a rail, then with their times', (tester) async {
    await openGo(tester, followed(const GoProgress(step: 1, phase: GoPhase.onBoard, stopIndex: 0)));

    final banner = find.byType(GoBanner);
    expect(find.descendant(of: banner, matching: find.text(currentL10n.goGetOffAtStop('Nation'))), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text('2')), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text(currentL10n.goStopsUnit(2))), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.textContaining(currentL10n.goNextStopShort('Gare de Lyon'))), findsOneWidget);
    expect(find.text(currentL10n.goNextStopLabel), findsOneWidget);
    expect(find.text(currentL10n.goGetOffHere), findsOneWidget);
    expect(find.text('Nation'), findsWidgets);

    await closeApp(tester);
  });

  testWidgets('missed: the next departure, taken in one tap', (tester) async {
    await openGo(tester,
        followed(const GoProgress(step: 1, phase: GoPhase.waiting, issue: GoIssue.missed), position: LatLng(chatelet.lat, chatelet.lon)));

    expect(find.text(currentL10n.goTakeThisOne), findsOneWidget);
    expect(find.text(currentL10n.recalculate), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('waiting: GO and its ride card ask the departures once, for both', (tester) async {
    // A device whose GPS gives nothing yet: GO starts from the app's position
    final messenger = tester.binding.defaultBinaryMessenger;
    const updates = EventChannel('flutter.baseflow.com/geolocator_updates');
    const geolocator = MethodChannel('flutter.baseflow.com/geolocator');
    messenger.setMockStreamHandler(updates, MockStreamHandler.inline(onListen: (_, _) {}));
    messenger.setMockMethodCallHandler(geolocator, (_) async => null);
    addTearDown(() {
      messenger.setMockStreamHandler(updates, null);
      messenger.setMockMethodCallHandler(geolocator, null);
    });
    final backend = standardBackend();
    await pumpApp(tester, backend, overrides: [liveJourneyProvider.overrideWithValue(_NoLiveJourney())]);
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(goControllerProvider.notifier)
      ..start(plan, const JourneyRequest())
      ..jumpTo(1);
    await settle(tester);
    await tapOn(tester, find.text(currentL10n.go).first);
    expect(find.byType(GoScreen), findsOneWidget);

    // The card lists them, the controller follows the planned vehicle in them
    expect(find.textContaining(currentL10n.goIfMissed('', 0).split(':').first), findsOneWidget);
    expect(backend.requests.where((request) => request.uri.path.endsWith('/rides')), hasLength(1));

    await closeApp(tester);
  });

  testWidgets('arrived: the summary, the way back', (tester) async {
    await openGo(tester, followed(GoProgress(step: 3, phase: GoPhase.arrived, arrivedAt: inMinutes(17))));

    expect(find.text(currentL10n.goArrived), findsWidgets);
    expect(find.text(currentL10n.goWayBack), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('missed at the stop: the next departure is kept on its own and said over the map', (tester) async {
    // The métro left 2 min ago; the user is still on the platform
    final missedPlan = journey([
      walk(inMinutes(-6), 240),
      transit(inMinutes(-2), 480, via: [gareDeLyon]),
    ]);
    final messenger = tester.binding.defaultBinaryMessenger;
    const updates = EventChannel('flutter.baseflow.com/geolocator_updates');
    const geolocator = MethodChannel('flutter.baseflow.com/geolocator');
    final fix = {
      'latitude': chatelet.lat,
      'longitude': chatelet.lon,
      'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
      'accuracy': 5.0,
      'altitude': 0.0,
      'altitude_accuracy': 0.0,
      'heading': 0.0,
      'heading_accuracy': 0.0,
      'speed': 0.0,
      'speed_accuracy': 0.0,
      'is_mocked': false,
    };
    messenger.setMockStreamHandler(updates, MockStreamHandler.inline(onListen: (_, sink) => sink.success(fix)));
    messenger.setMockMethodCallHandler(geolocator, (_) async => null);
    addTearDown(() {
      messenger.setMockStreamHandler(updates, null);
      messenger.setMockMethodCallHandler(geolocator, null);
    });
    final backend = standardBackend();
    await pumpApp(tester, backend, overrides: [liveJourneyProvider.overrideWithValue(_NoLiveJourney())]);
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(goControllerProvider.notifier).start(missedPlan, const JourneyRequest());
    // The first fix, GO open, then the user says they are at the stop
    await settle(tester, const Duration(seconds: 1));
    await tapOn(tester, find.text(currentL10n.go).first);
    container.read(goControllerProvider.notifier).jumpTo(1);
    await settle(tester, const Duration(seconds: 8));

    final state = container.read(goControllerProvider)!;
    // The next métro (in 7 min) is now the plan, without a tap
    expect(state.retained, isNotNull);
    expect(state.progress.issue, isNull);
    expect(state.journey.rides.single.departure.isAfter(DateTime.now().toUtc()), isTrue);
    expect(backend.requestsTo('/api/v2/journeys'), isEmpty);
    expect(find.descendant(of: find.byType(GoBanner), matching: find.text(currentL10n.goMissedShort('Métro 1'))), findsOneWidget);
    expect(find.text(currentL10n.goRecalculateJourney), findsOneWidget);

    await closeApp(tester);
  });
}

/// No notification nor screen kept on in the tests
class _NoLiveJourney implements LiveJourney {
  @override
  bool get systemAlerts => false;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> update(LiveJourneyUpdate update) async {}

  @override
  Future<void> alert(String title, String body, {bool urgent = false, String kind = 'info'}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> keepScreenOn(bool on) async {}
}
