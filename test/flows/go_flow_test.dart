import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/platform/live_journey.dart';
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

  testWidgets('walking: the next turn in the panel, the turns folded under it, what comes next', (tester) async {
    final along = tracker.steps.first.line.length * 260 / 500;
    await openGo(tester, followed(GoProgress(step: 0, phase: GoPhase.moving, along: along), position: LatLng(chatelet.lat, chatelet.lon)));

    // Once, in the card: nothing over the map
    expect(find.text(currentL10n.goTurnLeft), findsOneWidget);
    expect(find.textContaining('Rue des Halles'), findsWidgets);
    expect(find.textContaining(currentL10n.goVerbTo(currentL10n.goVerbWalk, 'Châtelet')), findsOneWidget);
    expect(find.text(currentL10n.goThen), findsOneWidget);
    // The steps' strip and the journey's progress
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsWidgets);

    // The turns, folded so that the panel stays low
    expect(find.text('Tournez à gauche sur Rue des Halles'), findsNothing);
    await tapOn(tester, find.textContaining(currentL10n.goTurnByTurn));
    expect(find.text('Tournez à gauche sur Rue des Halles'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('waiting: the countdown, where to board, the departures and the next one if missed', (tester) async {
    await openGo(tester, followed(const GoProgress(step: 1, phase: GoPhase.waiting), position: LatLng(chatelet.lat, chatelet.lon)));

    expect(find.textContaining('Métro 1 →'), findsOneWidget);
    // The countdown to the departure (in 6 min): a ring emptying
    expect(find.byWidgetPredicate((widget) => widget is CircularProgressIndicator && widget.value != null), findsOneWidget);
    expect(find.byType(TrainPositions), findsOneWidget);
    expect(find.textContaining(currentL10n.goIfMissed('', 0).split(':').first), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('on board: the stops left with their times, where to get off', (tester) async {
    await openGo(tester, followed(const GoProgress(step: 1, phase: GoPhase.onBoard, stopIndex: 0)));

    expect(find.text(currentL10n.goGetOffIn(2)), findsWidgets);
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
