import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/geo.dart';
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

    // A walk drawn as Navitia's path, from points in meters east and north of 3 Avenue Léon de Bertalot
    GoStep walkAlong(List<(double, double)> path, {required int length, required List<WalkStep> steps}) {
      const origin = LatLng(48.905168, 2.274459);
      final perDegree = 111195.0;
      final shape = [
        for (final (east, north) in path)
          [origin.longitude + east / (perDegree * math.cos(origin.latitude * math.pi / 180)), origin.latitude + north / perDegree],
      ];
      return GoStep(walk(at(0), 300).copyWith(length: length, steps: steps, shape: shape), 0);
    }

    test("stands each turn on the path's corner, later than the offsets scaled to the path say", () {
      // From the address, 60 m to the avenue that Navitia's lengths don't count; the avenue 50 m north, Rue Cantin
      // 80 m west, Rue Watteau 90 m north
      final step = walkAlong(const [(0, 0), (48, 36), (48, 86), (-32, 86), (-32, 176)], length: 220, steps: const [
        WalkStep(instruction: 'Marchez vers le nord sur Avenue Léon de Bertalot', length: 50, offset: 0),
        WalkStep(instruction: 'Tournez à gauche dans Rue Cantin', length: 80, offset: 50, direction: -91, name: 'Rue Cantin'),
        WalkStep(instruction: 'Tournez à droite dans Rue Watteau', length: 90, offset: 130, direction: 92, name: 'Rue Watteau'),
        WalkStep(instruction: 'Vous êtes arrivé à votre destination.', length: 0, offset: 220),
      ]);
      // Scaled to the path, Rue Cantin stood 46 m before its corner
      expect(50 * step.line.length / 220, closeTo(64, 1));

      final cantin = nextManeuver(step, 0)!;
      expect(cantin.walk.name, 'Rue Cantin');
      expect(cantin.meters, closeTo(110, 1));
      // The callout on the corner
      expect(metersBetween(step.line.pointAt(cantin.meters), step.line.points[2]), lessThan(0.01));
      // Navitia's 80 m on, the next one on its own corner; the arrival at the end
      final watteau = nextManeuver(step, 120)!;
      expect(watteau.walk.name, 'Rue Watteau');
      expect(watteau.meters, closeTo(70, 1));
      expect(walkStepAlongs(step), [0, closeTo(110, 1), closeTo(190, 1), closeTo(280, 1)]);

      // The card's instruction says the same distance
      final followed = GoState(
        tracker: GoTracker(journey([step.section, transit(at(6), 480)])),
        request: const JourneyRequest(),
        progress: const GoProgress(step: 0, phase: GoPhase.moving, along: 10),
        startedAt: at(0),
        plannedArrival: at(14),
      );
      final instruction = goInstruction(followed, at(1));
      expect(instruction.subtitle, startsWith('Dans 100'));
      expect(instruction.subtitle, endsWith('Rue Cantin'));
    });

    test('moves the offsets by what a station counts and the path draws shorter', () {
      // Out of the station: Navitia counts 167 m of corridors, drawn as 16 m; then 13 m on, right, 29 m on, left
      final step = walkAlong(const [(0, 0), (0, 16), (0, 29), (29, 29), (29, 218)], length: 233, steps: const [
        WalkStep(instruction: 'Sortez de Charles de Gaulle - Étoile (Paris) via av. de la Grande Armée.', length: 167, offset: 0),
        WalkStep(instruction: "Marchez vers le nord sur l'allée", length: 13, offset: 167),
        WalkStep(instruction: 'Tournez à droite dans Avenue de la Grande Armée', length: 29, offset: 180, direction: 85),
        WalkStep(instruction: 'Tournez à gauche pour rester sur Avenue de la Grande Armée', length: 189, offset: 209, direction: -76),
        WalkStep(instruction: 'Vous êtes arrivé à votre destination.', length: 0, offset: 398),
      ]);

      expect(walkStepAlongs(step), [0, closeTo(16, 1), closeTo(29, 1), closeTo(58, 1), closeTo(247, 1)]);
      expect(nextManeuver(step, 0)!.meters, closeTo(29, 1));
    });

    test('keeps the offsets scaled to a path without corners', () {
      // Straight on, a slight bend: no corner where Navitia says to turn
      final step = walkAlong(const [(0, 0), (0, 100), (10, 250)], length: 200, steps: const [
        WalkStep(instruction: 'Marchez vers le nord', length: 120, offset: 0),
        WalkStep(instruction: 'Tournez à droite', length: 80, offset: 120, direction: 90),
        WalkStep(instruction: 'Vous êtes arrivé à votre destination.', length: 0, offset: 200),
      ]);
      final scale = step.line.length / 200;

      expect(walkStepAlongs(step), [0, closeTo(120 * scale, 0.01), closeTo(200 * scale, 0.01)]);
      expect(nextManeuver(step, 0)!.meters, closeTo(120 * scale, 0.01));
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
