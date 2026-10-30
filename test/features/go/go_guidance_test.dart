import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/time_format.dart';
import 'package:website_app/features/go/go_guidance.dart';
import 'package:website_app/features/go/go_instruction.dart';
import 'package:website_app/features/go/go_state.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  final start = DateTime.utc(2026, 10, 10, 8, 0);
  DateTime at(int minutes, [int seconds = 0]) => start.add(Duration(minutes: minutes, seconds: seconds));

  // A walk of 500 m with two turns (Navitia's offsets along it), then the metro 1 at 8:06 to Nation, then a walk
  final firstWalk = walk(at(0), 240).copyWith(length: 500, steps: const [
    WalkStep(instruction: "Marchez vers l'est sur Rue de Rivoli", length: 300, offset: 0),
    WalkStep(instruction: 'Tournez à gauche sur Rue des Halles', length: 150, offset: 300, direction: -90, name: 'Rue des Halles'),
    WalkStep(instruction: 'Légèrement à droite sur Rue Saint-Denis', length: 40, offset: 450, direction: 30),
    // Navitia's last ones: nothing to do there
    WalkStep(instruction: 'Vous êtes arrivé à votre destination.', length: 10, offset: 490),
  ]);
  final plan = journey([
    firstWalk,
    transit(at(6), 480, via: [gareDeLyon]),
    walk(at(14), 180, from: point(nation), to: const JourneyPoint(name: 'Cours de Vincennes', lat: 48.8475, lon: 2.4000)),
  ]);
  final tracker = GoTracker(plan);
  final walkStep = tracker.steps.first;
  // Navitia's meters to the path drawn
  final scale = walkStep.line.length / 500;

  GoState state(GoProgress progress, {LatLng? position, double? walkSpeed}) => GoState(
        tracker: tracker,
        request: const JourneyRequest(),
        progress: progress,
        startedAt: at(0),
        plannedArrival: plan.arrival,
        position: position,
        walkSpeed: walkSpeed,
      );

  group('turn by turn', () {
    test('gives the next turn along the walk, scaled to the path drawn', () {
      final first = nextManeuver(walkStep, 0)!;
      expect(first.walk.name, 'Rue des Halles');
      expect(first.meters, closeTo(300 * scale, 0.5));
      expect(first.label, 'Tournez à gauche');
      expect(first.icon, Icons.turn_left);

      // Past it: the next one
      expect(nextManeuver(walkStep, 300 * scale + 10)!.walk.direction, 30);
      // None left after the last turn (arriving is no turn), none on a ride
      expect(nextManeuver(walkStep, 460 * scale), isNull);
      expect(nextManeuver(tracker.steps[1], 0), isNull);
    });

    test('shows a turn close ahead as the instruction', () {
      final close = state(GoProgress(step: 0, phase: GoPhase.moving, along: 300 * scale - 40), position: LatLng(chatelet.lat, chatelet.lon));
      final instruction = goInstruction(close, at(1));

      expect(instruction.title, 'Tournez à gauche');
      expect(instruction.subtitle, startsWith('Dans 40'));
      expect(instruction.subtitle, endsWith('Rue des Halles'));
      expect(instruction.icon, Icons.turn_left);

      // Far from it: where to walk to
      final far = goInstruction(state(tracker.initial(), position: const LatLng(48.86, 2.34)), at(0));
      expect(far.title, contains('Châtelet'));
    });

    test('draws an arrow for each turn', () {
      expect([-170, -90, -40, 0, 40, 90, 170].map(turnIcon), [
        Icons.u_turn_left,
        Icons.turn_left,
        Icons.turn_slight_left,
        Icons.straight,
        Icons.turn_slight_right,
        Icons.turn_right,
        Icons.u_turn_right,
      ]);
      expect(turnLabel(170), 'Faites demi-tour');
    });
  });

  group('time to spare walking to the ride', () {
    // From the walk's start, about the length of the path to walk, the metro leaving at 8:06
    final walking = tracker.initial();
    const from = LatLng(48.86, 2.34);

    test('depends on the pace: ahead, hurry, late', () {
      final meters = metersToGo(state(walking, position: from));
      Duration spare(double pace) => at(6).difference(at(0)) - Duration(seconds: (meters / pace).round());

      final fast = walkMargin(state(walking, position: from, walkSpeed: 2.0), at(0))!;
      expect(fast.margin, spare(2.0));
      expect(fast.level, spare(2.0) >= const Duration(minutes: 1) ? MarginLevel.ahead : MarginLevel.hurry);

      // Now, later: a minute less each minute
      final later = walkMargin(state(walking, position: from, walkSpeed: 2.0), at(5))!;
      expect(later.level, MarginLevel.late);
      expect(later.departure, at(6));
    });

    test("uses the usual pace until the user's own is known, within what is usual", () {
      expect(movePace(state(walking), walkStep), defaultWalkSpeed);
      expect(movePace(state(walking, walkSpeed: 5), walkStep), 2.0);
      expect(movePace(state(walking, walkSpeed: 0.3), walkStep), 0.8);
    });

    test('only while walking to a ride', () {
      expect(walkMargin(state(const GoProgress(step: 1, phase: GoPhase.waiting)), at(0)), isNull);
      expect(walkMargin(state(const GoProgress(step: 2, phase: GoPhase.moving)), at(15)), isNull);
    });
  });

  test('waiting, the map frames where to board, with the user when close to it', () {
    final ride = GoTracker(plan).steps[1];
    final stop = LatLng(chatelet.lat, chatelet.lon);

    expect(goWaitingFit(ride, null), [stop]);
    // On the platform's other end, 200 m away: both
    const along = LatLng(48.8602, 2.3470);
    expect(goWaitingFit(ride, along), [stop, along]);
    // Still far (a correction, no GPS): the stop alone
    expect(goWaitingFit(ride, LatLng(nation.lat, nation.lon)), [stop]);
  });

  test('tells the share of the journey done, by the planned durations', () {
    expect(journeyFraction(state(tracker.initial())), 0);
    // Walk done, halfway through the ride (stop 1 of 2)
    final onBoard = journeyFraction(state(const GoProgress(step: 1, phase: GoPhase.onBoard, stopIndex: 1)));
    expect(onBoard, closeTo((240 + 240) / (240 + 480 + 180), 0.001));
    expect(journeyFraction(state(const GoProgress(step: 3, phase: GoPhase.arrived))), 1);
  });

  test('alerts are felt apart', () {
    expect(const GoAlert(id: 'prepare-1', title: '').kind, 'prepare');
    expect(const GoAlert(id: 'alight-1', title: '', urgent: true).kind, 'alight');
    expect(const GoAlert(id: 'platform-1-B', title: '').kind, 'platform');
    expect(const GoAlert(id: 'cancel-1', title: '', urgent: true).kind, 'urgent');
    expect(const GoAlert(id: 'delay-1', title: '').kind, 'info');
  });

  test('tells the minutes left like the departure lists, rounded down', () {
    final waiting = state(const GoProgress(step: 1, phase: GoPhase.waiting));
    // The metro at 8:06: at 8:02:30, 3 min left and a half
    expect(goInstruction(waiting, at(2, 30)).detail, startsWith(currentL10n.goDeparture(currentL10n.inMinutes(3), formatClock(at(6)))));
    expect(goInstruction(waiting, at(5, 40)).detail, startsWith(currentL10n.goDeparture(currentL10n.now, formatClock(at(6)))));
  });
}
