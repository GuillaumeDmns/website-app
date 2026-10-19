import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_screen.dart';
import 'package:website_app/features/go/go_tracker.dart';
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

  testWidgets('walking: the next turn in large, the turns listed, the time to spare, what comes next', (tester) async {
    final along = tracker.steps.first.line.length * 260 / 500;
    await openGo(tester, followed(GoProgress(step: 0, phase: GoPhase.moving, along: along), position: LatLng(chatelet.lat, chatelet.lon)));

    expect(find.text(currentL10n.goTurnLeft), findsOneWidget);
    expect(find.textContaining('Rue des Halles'), findsWidgets);
    expect(find.text('Tournez à gauche sur Rue des Halles'), findsOneWidget);
    expect(find.text(currentL10n.goThen), findsOneWidget);
    // The steps' strip and the journey's progress
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsWidgets);

    await closeApp(tester);
  });

  testWidgets('waiting: the countdown, where to board, the departures and the next one if missed', (tester) async {
    await openGo(tester, followed(const GoProgress(step: 1, phase: GoPhase.waiting), position: LatLng(chatelet.lat, chatelet.lon)));

    expect(find.text(currentL10n.goTake('Métro 1')), findsOneWidget);
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

  testWidgets('arrived: the summary, the way back', (tester) async {
    await openGo(tester, followed(GoProgress(step: 3, phase: GoPhase.arrived, arrivedAt: inMinutes(17))));

    expect(find.text(currentL10n.goArrived), findsWidgets);
    expect(find.text(currentL10n.goWayBack), findsOneWidget);

    await closeApp(tester);
  });
}
