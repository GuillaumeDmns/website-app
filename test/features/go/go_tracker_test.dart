import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  final start = DateTime.utc(2026, 10, 10, 8, 0);
  DateTime at(int minutes, [int seconds = 0]) => start.add(Duration(minutes: minutes, seconds: seconds));

  // Walk 4 min to Châtelet, metro 1 at 8:06 to Nation through Gare de Lyon (8 min), walk 3 min
  final plan = journey([
    walk(at(0), 240),
    transit(at(6), 480, via: [gareDeLyon]),
    walk(at(14), 180, from: point(nation), to: const JourneyPoint(name: 'Cours de Vincennes', lat: 48.8475, lon: 2.4000)),
  ]);
  final tracker = GoTracker(plan);

  LatLng position(StopAreaSummary stop) => LatLng(stop.lat, stop.lon);

  GoInput input(DateTime now,
          {LatLng? position, double speed = 0, double accuracy = 10, DateTime? fixAt, Departure? vehicle, int? vehicleStep, bool realtime = false}) =>
      GoInput(
        now: now,
        position: position,
        accuracy: accuracy,
        speed: speed,
        fixAt: fixAt ?? now,
        vehicle: vehicle,
        vehicleStep: vehicleStep,
        realtimeDepartures: realtime,
      );

  test('has a step per walk and ride', () {
    expect(tracker.steps.map((step) => step.isRide), [false, true, false]);
    expect(tracker.initial().phase, GoPhase.moving);
    expect(tracker.steps[1].stopAlongs, hasLength(3));
    expect(tracker.steps[1].stopTime(1), at(10));
  });

  test('waits at the stop once the walk is done', () {
    final (progress, alerts) = tracker.update(tracker.initial(), input(at(3), position: position(chatelet)));

    expect(progress.step, 1);
    expect(progress.phase, GoPhase.waiting);
    expect(alerts, isEmpty);
  });

  test('follows the schedule without position (underground)', () {
    var (progress, _) = tracker.update(tracker.initial(), GoInput(now: at(5)));
    expect(progress.phase, GoPhase.waiting);

    // A minute after the departure: on board
    (progress, _) = tracker.update(progress, GoInput(now: at(7, 1)));
    expect(progress.phase, GoPhase.onBoard);

    // Gare de Lyon reached by the stop times, Nation is the next stop: get ready
    final List<GoAlert> alerts;
    (progress, alerts) = tracker.update(progress, GoInput(now: at(10, 30)));
    expect(progress.stopIndex, 1);
    expect(alerts.map((alert) => alert.id), ['prepare-1']);

    // Arrived at Nation: get off, then walk
    final List<GoAlert> last;
    (progress, last) = tracker.update(progress, GoInput(now: at(14, 1)));
    expect(last.map((alert) => alert.id), ['alight-1']);
    expect(last.single.urgent, isTrue);
    expect(progress.step, 2);
    expect(progress.phase, GoPhase.moving);
  });

  test('says "next stop" only once the stop before is left, not while the vehicle pulls in to it', () {
    final onBoard = tracker.jumpTo(tracker.initial(), 1).copyWith(phase: GoPhase.onBoard);
    final ride = tracker.steps[1];
    LatLng along(double meters) => ride.line.pointAt(meters);
    final gareDeLyonAlong = ride.stopAlongs[1];

    // 30 m before Gare de Lyon, then standing there: two stops to go, no alert
    var (progress, alerts) = tracker.update(onBoard, input(at(9, 50), position: along(gareDeLyonAlong - 30), speed: 3));
    expect(progress.stopIndex, 0);
    expect(alerts, isEmpty);
    (progress, alerts) = tracker.update(progress, input(at(10, 10), position: along(gareDeLyonAlong)));
    expect(progress.stopIndex, 0);
    expect(alerts, isEmpty);

    // Gone from Gare de Lyon: Nation is the next stop
    (progress, alerts) = tracker.update(progress, input(at(10, 40), position: along(gareDeLyonAlong + 60), speed: 10));
    expect(progress.stopIndex, 1);
    expect(alerts.map((alert) => alert.id), ['prepare-1']);
    expect(alerts.single.body, currentL10n.goNextStop('Nation'));

    // Pulling in to Nation: get off
    (progress, alerts) = tracker.update(progress, input(at(13, 50), position: along(ride.stopAlongs[2] - 30), speed: 3));
    expect(alerts.map((alert) => alert.id), ['alight-1']);
    expect(progress.step, 2);
  });

  test('a direct train: get ready a few minutes before its only stop, not when boarding', () {
    // RER A from Châtelet to Nation without a stop, 12 min
    final direct = GoTracker(journey([transit(at(0), 720, line: rerA)]));
    final onBoard = direct.initial().copyWith(phase: GoPhase.onBoard);

    var (progress, alerts) = direct.update(onBoard, GoInput(now: at(1)));
    expect(direct.stopsLeft(progress), 1);
    expect(alerts, isEmpty);
    (progress, alerts) = direct.update(progress, GoInput(now: at(7)));
    expect(alerts, isEmpty);
    (progress, alerts) = direct.update(progress, GoInput(now: at(8, 30)));
    expect(alerts.map((alert) => alert.id), ['prepare-0']);
  });

  test('underground, a stop is left a little after its time', () {
    final onBoard = tracker.jumpTo(tracker.initial(), 1).copyWith(phase: GoPhase.onBoard);

    // The metro stands at Gare de Lyon (10:00)
    var (progress, alerts) = tracker.update(onBoard, GoInput(now: at(10, 5)));
    expect(progress.stopIndex, 0);
    expect(alerts, isEmpty);

    (progress, alerts) = tracker.update(progress, GoInput(now: at(10, 25)));
    expect(progress.stopIndex, 1);
    expect(alerts.map((alert) => alert.id), ['prepare-1']);
  });

  test('on board underground, the user is between two stops by the clock: from the stop left to the next one', () {
    final onBoard = tracker.jumpTo(tracker.initial(), 1).copyWith(phase: GoPhase.onBoard);

    // Châtelet left at 8:06, Gare de Lyon at 8:10: a quarter of the way at 8:07, not halfway
    expect(tracker.betweenStops(onBoard, at(7)), 0.25);
    expect(tracker.betweenStops(onBoard, at(8)), 0.5);
    // At Gare de Lyon until it is left
    expect(tracker.betweenStops(onBoard, at(10, 10)), 1);

    // Left 20 s after its time: Nation at 8:14 is next, from there
    final (pastLyon, _) = tracker.update(onBoard, GoInput(now: at(10, 25)));
    expect(pastLyon.stopIndex, 1);
    expect(tracker.betweenStops(pastLyon, at(10, 20)), 0);
    expect(tracker.betweenStops(pastLyon, at(12, 10)), 0.5);

    // Four minutes late since the departure: the stops' times shifted
    expect(tracker.betweenStops(onBoard.copyWith(shift: const Duration(minutes: 4)), at(12)), 0.5);
    // Not on board: nowhere between stops
    expect(tracker.betweenStops(tracker.jumpTo(tracker.initial(), 1), at(7)), isNull);
  });

  test('on board above ground, the GPS puts the user between the stops; in a tunnel, the clock, never behind it', () {
    final onBoard = tracker.jumpTo(tracker.initial(), 1).copyWith(phase: GoPhase.onBoard);
    final ride = tracker.steps[1];
    LatLng along(double meters) => ride.line.pointAt(meters);
    final lyon = ride.stopAlongs[1];

    // A late train: seen 30 % of the way to Gare de Lyon at 8:09, when the clock says 75 %
    var (late, _) = tracker.update(onBoard, input(at(9), position: along(lyon * 0.3), speed: 10));
    expect(tracker.betweenStops(late, at(9)), closeTo(0.3, 0.01));
    // The map fades the ride up to there
    expect(late.along, closeTo(lyon * 0.3, 1));
    // Then nothing (a tunnel): the last fix says it a few seconds more, then the clock leads
    (late, _) = tracker.update(late, GoInput(now: at(9, 6)));
    expect(tracker.betweenStops(late, at(9, 6)), closeTo(0.3, 0.01));
    expect(tracker.betweenStops(late, at(9, 20)), closeTo(200 / 240, 0.01));

    // An early train: seen 60 % of the way at 8:07, then only the network's positions, staying behind
    var (early, _) = tracker.update(onBoard, input(at(7), position: along(lyon * 0.6), speed: 10));
    (early, _) = tracker.update(early, input(at(7, 20), position: along(lyon * 0.4), accuracy: 60));
    expect(early.preciseAt, at(7));
    // The clock says 35 % at 8:07:30: never behind where the GPS saw the user
    expect(tracker.betweenStops(early, at(7, 30)), closeTo(0.6, 0.01));
    expect(tracker.betweenStops(early, at(9)), 0.75);

    // Boarding again (a correction) starts without it
    final boarded = tracker.next(early.copyWith(phase: GoPhase.waiting));
    expect(boarded.phase, GoPhase.onBoard);
    expect(boarded.preciseAlong, isNull);
  });

  test('warns when the vehicle comes soon and when it is late', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);

    final (_, soon) = tracker.update(waiting, input(at(4, 30), position: position(chatelet)));
    expect(soon.map((alert) => alert.id), ['soon-1']);

    final late = departure(at(10), aimed: at(6));
    final (_, delayed) = tracker.update(waiting, input(at(3), position: position(chatelet), vehicle: late, vehicleStep: 1));
    expect(delayed.map((alert) => alert.id), contains('delay-1'));
  });

  test('says when the vehicle is cancelled, once', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);
    final cancelled = departure(at(6), status: 'cancelled');

    final (progress, alerts) = tracker.update(waiting, input(at(3), position: position(chatelet), vehicle: cancelled, vehicleStep: 1));
    expect(progress.issue, GoIssue.cancelled);
    expect(alerts.single.urgent, isTrue);

    final (_, again) = tracker.update(progress, input(at(4), position: position(chatelet), vehicle: cancelled, vehicleStep: 1));
    expect(again, isEmpty);
  });

  test('says when the vehicle was missed', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);

    // The line's departures have real time: gone from them, the vehicle has left
    final (progress, alerts) = tracker.update(waiting, input(at(8), position: position(chatelet), vehicleStep: 1, realtime: true));

    expect(progress.issue, GoIssue.missed);
    expect(progress.phase, GoPhase.waiting);
    expect(alerts.map((alert) => alert.id), ['missed-1']);
  });

  test('a vehicle only scheduled may come a few minutes late: given up 3 min after its time', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);

    final (late, alerts) = tracker.update(waiting, input(at(8), position: position(chatelet)));
    expect(late.issue, isNull);
    expect(alerts, isEmpty);

    final (given, _) = tracker.update(waiting, input(at(9), position: position(chatelet)));
    expect(given.issue, GoIssue.missed);
  });

  test('underground, positions staying at the station never say the vehicle was missed: on board once it left', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);

    // The network's positions (Wi-Fi, cell towers) stay at Châtelet while the metro takes the user away
    var (progress, alerts) = tracker.update(waiting, input(at(8), position: position(chatelet), accuracy: 60, vehicleStep: 1, realtime: true));
    expect(progress.issue, isNull);
    expect(progress.phase, GoPhase.onBoard);
    expect(alerts, isEmpty);

    // Gare de Lyon left by its time though they stay there: Nation is next
    (progress, alerts) = tracker.update(progress, input(at(10, 30), position: position(chatelet), accuracy: 60));
    expect(progress.stopIndex, 1);
    expect(alerts.map((alert) => alert.id), ['prepare-1']);

    // The last precise position given again since before the departure is as old as then (see positionSince)
    final (seen, _) = tracker.update(waiting, input(at(5, 50), position: position(chatelet)));
    final (given, again) = tracker.update(seen, input(at(8), position: position(chatelet), fixAt: at(5, 50), vehicleStep: 1, realtime: true));
    expect(given.issue, isNull);
    expect(given.phase, GoPhase.onBoard);
    expect(again, isEmpty);
  });

  test('back from a tunnel, seen far along the line: on board whatever the speed, past the stops gone by', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);
    final ride = tracker.steps[1];

    // No speed: the network's positions have none
    final (progress, _) = tracker.update(waiting, input(at(10, 40), position: ride.line.pointAt(ride.stopAlongs[1] + 200)));

    expect(progress.phase, GoPhase.onBoard);
    expect(progress.stopIndex, 1);
    // The planned metro: there about when it should be
    expect(progress.shift, Duration.zero);

    // Nobody waits down the line, but its stop may be passed again by the line: not there
    final (atStop, _) = tracker.update(waiting, input(at(5), position: ride.line.pointAt(100)));
    expect(atStop.phase, GoPhase.waiting);
  });

  test('back from a tunnel on the metro given up for missed: followed on its own times, not on the one retained', () {
    // The metro of 8:06 given up for missed at Châtelet: the journey moved to the next one, at 8:14
    final retainedPlan = journey([
      walk(at(0), 240),
      transit(at(14), 480, via: [gareDeLyon]),
      walk(at(22), 180, from: point(nation), to: const JourneyPoint(name: 'Cours de Vincennes', lat: 48.8475, lon: 2.4000)),
    ]);
    final retained = GoTracker(retainedPlan);
    final waiting = retained.chosen(retained.jumpTo(retained.initial(), 1), 1);
    final ride = retained.steps[1];

    // Past Gare de Lyon at 8:10:40: on the 8:06, by the ride's times
    final (progress, _) = retained.update(
        waiting, input(at(10, 40), position: ride.line.pointAt(ride.stopAlongs[1] + 200), vehicle: departure(at(14)), vehicleStep: 1));

    expect(progress.phase, GoPhase.onBoard);
    expect(progress.stopIndex, 1);
    expect(progress.shift.inSeconds, closeTo(-8 * 60, 30));
    expect(ride.scheduledTo(ride.stopAlongs[1]), const Duration(minutes: 4));
  });

  test('walking to the stop along the line is no ride; seen far along it off the walk, the user rides it', () {
    final line = tracker.steps[1].line;
    // Walking to Châtelet from 800 m down the metro line, along it
    final downTheLine = line.pointAt(800);
    final along = GoTracker(journey([
      walk(at(0), 600, from: JourneyPoint(name: 'Quai de la Rapée', lat: downTheLine.latitude, lon: downTheLine.longitude)),
      transit(at(10), 480, via: [gareDeLyon]),
    ]));
    final (walking, _) = along.update(along.initial(), input(at(2), position: line.pointAt(600), speed: 1.3));
    expect(walking.step, 0);
    expect(walking.phase, GoPhase.moving);

    // The walk never seen done (underground), the GPS back past Gare de Lyon: on board
    final ride = tracker.steps[1];
    final (riding, _) = tracker.update(tracker.initial(), input(at(10, 40), position: ride.line.pointAt(ride.stopAlongs[1] + 200)));
    expect(riding.step, 1);
    expect(riding.phase, GoPhase.onBoard);
  });

  test('detects boarding from a fast move along the line', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);
    final onTheWay = LatLng((chatelet.lat + gareDeLyon.lat) / 2, (chatelet.lon + gareDeLyon.lon) / 2);

    final late = departure(at(8), aimed: at(6));

    final (progress, _) = tracker.update(waiting, input(at(8, 30), position: onTheWay, speed: 10, vehicle: late, vehicleStep: 1));

    expect(progress.phase, GoPhase.onBoard);
    // Left two minutes late: the rest of the journey follows
    expect(progress.shift, const Duration(minutes: 2));
    // The arrival shown stays the API's: the delay measured is GO's own
    expect(tracker.eta(progress, null), plan.arrival);
  });

  test('seen on board only far down the line: never left before the GPS last saw the user on the platform', () {
    // Like the line L at Bécon: the metro of 8:06 late beyond what the real time said, the user still on the platform
    // at 8:08:30 by the GPS, then only rough positions until one far down the line
    final waiting = tracker.jumpTo(tracker.initial(), 1);
    final platform = tracker.steps[1].line.pointAt(20);
    var progress = waiting;
    for (var second = 0; second <= 150; second += 10) {
      (progress, _) = tracker.update(progress, input(at(6, second), position: platform, accuracy: 5));
    }
    for (var second = 0; second <= 150; second += 10) {
      (progress, _) = tracker.update(progress, input(at(7, second), position: platform, accuracy: 5));
    }
    expect(progress.phase, GoPhase.waiting);

    (progress, _) = tracker.update(progress, input(at(9, 30), position: tracker.steps[1].line.pointAt(900), accuracy: 100));

    expect(progress.phase, GoPhase.onBoard);
    expect(progress.departedAt!.isBefore(at(8, 30)), isFalse);
    expect(progress.shift, greaterThanOrEqualTo(const Duration(minutes: 2, seconds: 30)));
  });

  test('boarding another vehicle than the one expected: the times follow the one taken', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);
    // 150 m along the line at 10 m/s: seen leaving 15 s before
    final nearStop = tracker.steps[1].line.pointAt(150);

    // The one before the planned one (8:06)
    final (earlier, _) = tracker.update(waiting, input(at(1), position: nearStop, speed: 10));
    expect(earlier.phase, GoPhase.onBoard);
    expect(earlier.shift, -const Duration(minutes: 5, seconds: 15));

    // The planned one, late without its real time saying so
    final (late, _) = tracker.update(waiting, input(at(7, 45), position: nearStop, speed: 10, vehicle: departure(at(6)), vehicleStep: 1));
    expect(late.shift, const Duration(minutes: 1, seconds: 30));

    // About when its real time said: that time, the more precise
    final (onTime, _) = tracker.update(waiting, input(at(6, 30), position: nearStop, speed: 10, vehicle: departure(at(6, 10)), vehicleStep: 1));
    expect(onTime.shift, const Duration(seconds: 10));
  });

  test('the late vehicle taken after the next one was retained in its place: followed, not the next one', () {
    // The metro of 8:06 given up for missed: the journey moved to the next one, at 8:14
    final retainedPlan = journey([
      walk(at(0), 240),
      transit(at(14), 480, via: [gareDeLyon]),
      walk(at(22), 180, from: point(nation), to: const JourneyPoint(name: 'Cours de Vincennes', lat: 48.8475, lon: 2.4000)),
    ]);
    final retained = GoTracker(retainedPlan);
    final waiting = retained.chosen(retained.jumpTo(retained.initial(), 1), 1);

    // The late one comes at 8:08 and is taken
    final (progress, _) = retained.update(
        waiting, input(at(8, 15), position: retained.steps[1].line.pointAt(150), speed: 10, vehicle: departure(at(14)), vehicleStep: 1));

    expect(progress.phase, GoPhase.onBoard);
    expect(progress.shift, -const Duration(minutes: 6));
    expect(retained.eta(progress, null), retainedPlan.arrival);
    // Its stops come on its own times: Gare de Lyon at 8:12, not 8:18
    expect(retained.steps[1].stopTime(1).add(progress.shift), at(12));
  });

  test('says when the walk goes away from the path for a minute', () {
    const elsewhere = LatLng(48.8700, 2.3000);
    var (progress, alerts) = tracker.update(tracker.initial(), input(at(1), position: elsewhere));
    expect(progress.issue, isNull);

    (progress, alerts) = tracker.update(progress, input(at(2, 5), position: elsewhere));
    expect(progress.issue, GoIssue.offRoute);
    expect(alerts.map((alert) => alert.id), ['offroute-0']);

    expect(tracker.dismissIssue(progress).issue, isNull);
  });

  test('out of a train, the platform far from where the walk is drawn from is not off the way', () {
    // Off the metro at Nation, the walk goes east; the user is still 250 m west of where it starts, for minutes
    final lastWalk = tracker.jumpTo(tracker.initial(), 2);
    const platform = LatLng(48.8484, 2.3925);
    var (progress, alerts) = tracker.update(lastWalk, input(at(14), position: platform));
    (progress, alerts) = tracker.update(progress, input(at(16), position: platform));
    expect(progress.issue, isNull);
    expect(alerts, isEmpty);

    // Leaving the other way, further than a station is long: off the way after a minute
    const away = LatLng(48.8484, 2.3875);
    (progress, alerts) = tracker.update(progress, input(at(17), position: away));
    (progress, alerts) = tracker.update(progress, input(at(18, 5), position: away));
    expect(progress.issue, GoIssue.offRoute);
  });

  test('once on the walk, leaving it is off the way even close to its start; a rough fix is not', () {
    final lastWalk = tracker.jumpTo(tracker.initial(), 2);
    final onPath = tracker.steps[2].line.pointAt(20);
    const beside = LatLng(48.8504, 2.3959);
    var (progress, _) = tracker.update(lastWalk, input(at(14), position: onPath));
    expect(progress.joined, isTrue);

    // 220 m beside it by a fix that may be 95 m off: not sure enough
    (progress, _) = tracker.update(progress, input(at(15), position: beside, accuracy: 95));
    (progress, _) = tracker.update(progress, input(at(16, 5), position: beside, accuracy: 95));
    expect(progress.issue, isNull);

    (progress, _) = tracker.update(progress, input(at(17), position: beside));
    (progress, _) = tracker.update(progress, input(at(18, 5), position: beside));
    expect(progress.issue, GoIssue.offRoute);
  });

  test('arrives near the destination', () {
    final lastWalk = tracker.jumpTo(tracker.initial(), 2);

    final (progress, alerts) = tracker.update(lastWalk, input(at(17), position: const LatLng(48.8475, 2.4000)));

    expect(progress.phase, GoPhase.arrived);
    expect(progress.arrivedAt, at(17));
    expect(alerts.map((alert) => alert.id), ['arrived']);
    expect(tracker.eta(progress, null), at(17));
  });

  test('arrives right by the destination, not 35 m before it as the progress along the path would say', () {
    final lastWalk = tracker.jumpTo(tracker.initial(), 2);
    final walk = tracker.steps[2];

    var (progress, alerts) = tracker.update(lastWalk, input(at(16), position: walk.line.pointAt(walk.line.length - 35), speed: 1.3));
    expect(progress.phase, GoPhase.moving);
    expect(alerts, isEmpty);

    (progress, alerts) = tracker.update(progress, input(at(16, 30), position: walk.line.pointAt(walk.line.length - 20), speed: 1.3));
    expect(progress.phase, GoPhase.arrived);
    expect(alerts.map((alert) => alert.id), ['arrived']);
  });

  test('a rough fix at the destination ends nothing before its time; well past it, near is enough (indoors)', () {
    final lastWalk = tracker.jumpTo(tracker.initial(), 2);
    const destination = LatLng(48.8475, 2.4000);

    final (early, _) = tracker.update(lastWalk, input(at(15), position: destination, accuracy: 60));
    expect(early.phase, GoPhase.moving);
    // Planned at 8:17: two minutes later, 40 m from it by the network's positions
    final (late, _) = tracker.update(lastWalk, input(at(19, 1), position: const Distance().offset(destination, 40, 0), accuracy: 60));
    expect(late.phase, GoPhase.arrived);
  });

  test("a big place, whose point can't be walked to: 40 m from it is enough once its time is well past", () {
    final lastWalk = tracker.jumpTo(tracker.initial(), 2);
    final aside = const Distance().offset(const LatLng(48.8475, 2.4000), 40, 0);

    final (early, _) = tracker.update(lastWalk, input(at(16), position: aside));
    expect(early.phase, GoPhase.moving);
    final (late, _) = tracker.update(lastWalk, input(at(19, 1), position: aside));
    expect(late.phase, GoPhase.arrived);
  });

  test('moves on when the user says so', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);

    expect(tracker.next(waiting).phase, GoPhase.onBoard);
    expect(tracker.next(tracker.initial()).step, 1);
    expect(tracker.jumpTo(waiting, tracker.steps.length).phase, GoPhase.arrived);
  });

  test('waits for a newly chosen departure, whose alerts can come again', () {
    final missed = tracker.jumpTo(tracker.initial(), 1).copyWith(issue: () => GoIssue.missed, fired: {'soon-1', 'missed-1', 'soon-0'});

    final chosen = tracker.chosen(missed, 1);

    expect(chosen.issue, isNull);
    expect(chosen.fired, {'soon-0'});
    expect(tracker.chosen(missed, 2), missed);
  });

  test('on board, another vehicle guessed: the stops left counted on its own, its times from when the user left', () {
    // On the metro 300 m past Gare de Lyon, left a minute late
    final onBoard = tracker.next(tracker.jumpTo(tracker.initial(), 1));
    final past = onBoard.copyWith(along: tracker.steps[1].stopAlongs[1] + 300, stopIndex: 1, shift: const Duration(minutes: 1));
    // The journey now follows a train on the same tracks straight to Nation, leaving at 8:06:30 by its real time
    final direct = GoTracker(plan.copyWith(sections: [
      plan.sections[0],
      transit(at(6, 30), 300).copyWith(shape: plan.sections[1].shape),
      plan.sections[2],
    ]));

    final followed = direct.onAnotherVehicle(past, at(7));

    expect(followed.phase, GoPhase.onBoard);
    expect(followed.along, past.along);
    expect(followed.stopIndex, 0);
    expect(direct.stopsLeft(followed), 1);
    // Seen leaving at 8:07, about when its real time said: that one holds
    expect(followed.shift, Duration.zero);
    // Seen leaving 3 min after it: from then on
    expect(direct.onAnotherVehicle(past, at(9, 30)).shift, const Duration(minutes: 3));
  });

  test('counts what is left', () {
    final onBoard = tracker.next(tracker.jumpTo(tracker.initial(), 1));

    expect(tracker.stopsLeft(onBoard), 2);
    expect(tracker.metersLeft(tracker.initial()), greaterThan(0));
  });

  test('keeps its progress across restarts', () {
    final progress = tracker.jumpTo(tracker.initial(), 1).copyWith(shift: const Duration(minutes: 3), fired: {'soon-1'});

    final restored = GoProgress.fromJson(progress.toJson());

    expect(restored.step, 1);
    expect(restored.phase, GoPhase.waiting);
    expect(restored.shift, const Duration(minutes: 3));
    expect(restored.fired, {'soon-1'});
    expect(GoProgress.fromJson(const {}).phase, GoPhase.moving);
  });

  group('still at home, the GPS indoors', () {
    // 10 Rue de Rivoli, where the walk starts, 540 m from Châtelet
    final home = LatLng(address.lat, address.lon);
    // The walk at a brisk 2 m/s: more than its 4 min
    final walkable = Duration(seconds: (tracker.steps[0].line.length / 2).ceil());
    // Seen at home at 8:00, when the walk starts
    final (atHome, _) = tracker.update(tracker.initial(), input(at(0), position: home));

    test('a minute of positions hundreds of meters off ends no walk the user can\'t have done since the GPS saw them', () {
      expect(atHome.joined, isTrue);
      expect(walkable, greaterThan(const Duration(minutes: 4, seconds: 10)));
      // The network's positions, too rough to say anything: past the walk's time (8:04), the clock leads, as far as the
      // user can have walked
      var (progress, _) = tracker.update(atHome, input(at(4, 1), position: home, accuracy: 180));
      expect(progress.step, 0);
      final before = at(0).add(walkable).subtract(const Duration(seconds: 5));
      (progress, _) = tracker.update(progress, input(before, position: home, accuracy: 180));
      expect(progress.step, 0);
      expect(tracker.followsSchedule(progress, before), isTrue);

      // Walkable since the GPS saw them: they may be at the stop
      (progress, _) = tracker.update(progress, input(at(0).add(walkable), position: home, accuracy: 180));
      expect(progress.step, 1);
      expect(progress.phase, GoPhase.waiting);
      expect(progress.byClock, isTrue);
    });

    test('never seen on the walk (the GPS lost from the start), the schedule alone ends it', () {
      final (progress, _) = tracker.update(tracker.initial(), GoInput(now: at(4, 1)));
      expect(progress.step, 1);
    });

    test('waiting, a rough position between precise ones at home is not the user underground in the vehicle gone', () {
      final waiting = tracker.jumpTo(tracker.initial(), 1);
      // The metro left at 8:06; at home by the GPS, then by the Wi-Fi a moment later
      var (progress, _) = tracker.update(waiting, input(at(7), position: home));
      expect(progress.phase, GoPhase.waiting);
      (progress, _) = tracker.update(progress, input(at(7, 10), position: home, accuracy: 78));
      expect(progress.phase, GoPhase.waiting);
      // Precise, at home well after it left: not on it either (a later one may be taken)
      (progress, _) = tracker.update(progress, input(at(7, 40), position: home));
      expect(progress.phase, GoPhase.waiting);
      expect(progress.issue, isNull);

      // Then nothing for a minute and more (underground): on board by the clock, as ever
      (progress, _) = tracker.update(progress, GoInput(now: at(8, 50)));
      expect(progress.phase, GoPhase.onBoard);
      (progress, _) = tracker.update(waiting, input(at(9), position: home, accuracy: 78, fixAt: at(9)));
      expect(progress.phase, GoPhase.onBoard);
    });

    test('taken by the clock to the stop, then on board, then off: the GPS at home takes the user back to the walk', () {
      // No usable position since 8:00: at the stop, then on board, then off at Nation by the clock
      var (progress, _) = tracker.update(atHome, GoInput(now: at(6)));
      expect((progress.step, progress.phase, progress.byClock), (1, GoPhase.waiting, true));
      (progress, _) = tracker.update(progress, GoInput(now: at(7, 1)));
      expect(progress.phase, GoPhase.onBoard);
      (progress, _) = tracker.update(progress, GoInput(now: at(14, 1)));
      expect((progress.step, progress.phase), (2, GoPhase.moving));
      expect(progress.seenStep, 0);

      // A precise fix at home: still at the start of the walk, never left
      (progress, _) = tracker.update(progress, input(at(14, 10), position: home));
      expect((progress.step, progress.phase, progress.byClock), (0, GoPhase.moving, false));
      expect(progress.along, lessThan(30));
      // The walk is done by the GPS, or by the clock as far as the user can have gone since
      (progress, _) = tracker.update(progress, GoInput(now: at(15, 30)));
      expect(progress.step, 0);
    });

    test('seen at the stop, the clock taking them on from there: a fix back at home is off the way, not the walk', () {
      final waiting = tracker.jumpTo(tracker.initial(), 1);
      var (progress, _) = tracker.update(waiting, input(at(5, 30), position: position(chatelet)));
      // Underground from there: on board by the clock
      (progress, _) = tracker.update(progress, GoInput(now: at(7, 1)));
      expect((progress.phase, progress.byClock, progress.seenStep), (GoPhase.onBoard, true, 1));

      (progress, _) = tracker.update(progress, input(at(7, 30), position: home));
      expect((progress.step, progress.phase), (1, GoPhase.onBoard));
    });
  });

  group('the GPS first', () {
    // Walk to Châtelet, RER A from there (its head of platform in this sample, as in a terminus) at 8:06 to Nation
    // through Gare de Lyon (8 min), walk 3 min
    final rerPlan = journey([
      walk(at(0), 240),
      transit(at(6), 480, line: rerA, via: [gareDeLyon]),
      walk(at(14), 180, from: point(nation), to: const JourneyPoint(name: 'Cours de Vincennes', lat: 48.8475, lon: 2.4000)),
    ]);
    final rer = GoTracker(rerPlan);
    final ride = rer.steps[1];
    LatLng along(double meters) => ride.line.pointAt(meters);
    final waiting = rer.jumpTo(rer.initial(), 1);
    // The planned train, six minutes late, standing at the platform
    final late = departure(at(12), aimed: at(6)).copyWith(atStop: true);

    test('seated early in a train standing at the platform, 420 m from the stop\'s point: waiting, then on board when it '
        'leaves, six minutes late, never on another train', () {
      var (progress, alerts) = rer.update(waiting, input(at(4), position: along(420), vehicle: late, vehicleStep: 1, realtime: true));
      expect(progress.phase, GoPhase.waiting);
      expect(progress.preciseAlong, closeTo(420, 1));

      // Another train left on time meanwhile: still there, neither on board nor missed
      for (final minute in [6, 7, 9, 11]) {
        (progress, alerts) = rer.update(progress, input(at(minute), position: along(420), vehicle: late, vehicleStep: 1, realtime: true));
        expect(progress.phase, GoPhase.waiting, reason: '8:0$minute');
        expect(progress.issue, isNull);
      }

      // It leaves at 8:12: on board, 20 s after the train moved 240 m from where the user sat
      (progress, alerts) = rer.update(progress, input(at(12, 20), position: along(660), speed: 12, vehicle: late, vehicleStep: 1));
      expect(progress.phase, GoPhase.onBoard);
      expect(progress.byClock, isFalse);
      expect(progress.departedAt, at(12));
      expect(progress.shift, const Duration(minutes: 6));

      // Its own times on: Gare de Lyon at 8:16, not 8:10; never off before Nation
      final lyon = ride.stopAlongs[1];
      (progress, alerts) = rer.update(progress, input(at(15), position: along(lyon - 800), speed: 15));
      expect(progress.stopIndex, 0);
      (progress, alerts) = rer.update(progress, input(at(16, 40), position: along(lyon + 100), speed: 12));
      expect(progress.stopIndex, 1);
      expect(progress.phase, GoPhase.onBoard);
      // The network's positions only a little while: the GPS seen within the minute still leads, not the clock
      (progress, alerts) = rer.update(progress, input(at(17, 20), position: along(lyon + 400), accuracy: 60));
      expect(progress.phase, GoPhase.onBoard);
      expect(alerts.where((alert) => alert.id.startsWith('alight')), isEmpty);
    });

    test('a train stopped at a signal well down the line, the user still in it: on board', () {
      final (progress, _) = rer.update(waiting, input(at(7), position: along(ride.platformZone.to + 300)));
      expect(progress.phase, GoPhase.onBoard);
    });

    test('a train the real time says is still at the platform is not missed, however late', () {
      final (stillThere, _) = rer.update(waiting, input(at(9), position: along(100), vehicle: late.copyWith(time: at(6)), vehicleStep: 1, realtime: true));
      expect(stillThere.issue, isNull);
      expect(stillThere.phase, GoPhase.waiting);

      final (gone, alerts) = rer.update(waiting, input(at(9), position: along(100), vehicle: departure(at(6)), vehicleStep: 1, realtime: true));
      expect(gone.issue, GoIssue.missed);
      expect(alerts.map((alert) => alert.id), ['missed-1']);
    });

    test('on board, the GPS a minute far from the line: off the way (the wrong train, off too early)', () {
      final onBoard = rer.next(waiting);
      const away = LatLng(48.8700, 2.3000);
      var (progress, alerts) = rer.update(onBoard, input(at(8), position: away));
      expect(progress.issue, isNull);
      (progress, alerts) = rer.update(progress, input(at(9, 5), position: away));
      expect(progress.issue, GoIssue.offRoute);
      expect(alerts.map((alert) => alert.id), ['offroute-1']);

      // Back on it: nothing to do
      (progress, alerts) = rer.update(progress, input(at(9, 10), position: along(ride.stopAlongs[1] - 200), speed: 12));
      expect(progress.issue, isNull);
    });

    test('got off by the clock, the GPS back on the line well before the stop: back on board, "get off" to come again', () {
      final onBoard = rer.next(waiting);
      // Underground all along: off at 8:14 by the clock
      var (progress, alerts) = rer.update(onBoard, GoInput(now: at(14, 1)));
      expect(progress.step, 2);
      expect(progress.byClock, isTrue);
      expect(alerts.map((alert) => alert.id), contains('alight-1'));

      // The train was late: the GPS sees it 1 km before Nation, moving
      (progress, alerts) = rer.update(progress, input(at(14, 30), position: along(ride.stopAlongs[2] - 1000), speed: 14));
      expect(progress.step, 1);
      expect(progress.phase, GoPhase.onBoard);
      expect(progress.stopIndex, 1);
      expect(progress.fired, isNot(contains('alight-1')));

      // Then it gets there
      (progress, alerts) = rer.update(progress, input(at(15, 40), position: along(ride.stopAlongs[2] - 20), speed: 3));
      expect(alerts.map((alert) => alert.id), ['alight-1']);
      expect(progress.step, 2);
      expect(progress.byClock, isFalse);

      // Off by the GPS: walking along the line out of the station is no ride
      final (walking, _) = rer.update(progress, input(at(16, 30), position: along(ride.stopAlongs[2] - 600)));
      expect(walking.step, 2);
    });

    test('above ground, the precise fixes measure the delay: the clock in a tunnel goes on from it', () {
      final onBoard = rer.next(waiting);
      final lyon = ride.stopAlongs[1];
      // A minute and a half late on its way to Gare de Lyon (planned there at 8:10), fixes every 5 s
      var progress = onBoard;
      for (var second = 0; second <= 60; second += 5) {
        final time = at(8, 30).add(Duration(seconds: second));
        final scheduledAlong = lyon * (time.difference(at(6, 90)).inSeconds / 240);
        (progress, _) = rer.update(progress, input(time, position: along(scheduledAlong), speed: 10));
      }
      expect(progress.shift.inSeconds, closeTo(90, 10));

      // Into a tunnel: Gare de Lyon left by the clock at 8:11:50, not 8:10:20
      (progress, _) = rer.update(progress, GoInput(now: at(10, 40)));
      expect(progress.stopIndex, 0);
      (progress, _) = rer.update(progress, GoInput(now: at(11, 55)));
      expect(progress.stopIndex, 1);
    });
  });

  group('platform', () {
    // Walk to Châtelet, RER A at 8:06 to Nation
    final rerPlan = journey([walk(at(0), 240), transit(at(6), 480, line: rerA)]);
    final rerTracker = GoTracker(rerPlan);
    Departure withPlatform(String? platform) => departure(at(6)).copyWith(platform: platform);

    test('a train\'s platform is announced once known, and again when it changes', () {
      final waiting = rerTracker.jumpTo(rerTracker.initial(), 1);

      var (progress, alerts) = rerTracker.update(waiting, input(at(3), position: position(chatelet), vehicle: withPlatform(null), vehicleStep: 1));
      expect(alerts.where((alert) => alert.id.startsWith('platform')), isEmpty);

      (progress, alerts) = rerTracker.update(progress, input(at(3, 30), position: position(chatelet), vehicle: withPlatform('2'), vehicleStep: 1));
      expect(alerts.single.id, 'platform-1-2');
      expect(alerts.single.title, currentL10n.alertPlatform('RER A', '2'));
      expect(alerts.single.urgent, isFalse);

      // Same platform: said once
      (progress, alerts) = rerTracker.update(progress, input(at(4), position: position(chatelet), vehicle: withPlatform('2'), vehicleStep: 1));
      expect(alerts.where((alert) => alert.id.startsWith('platform')), isEmpty);

      (progress, alerts) = rerTracker.update(progress, input(at(4, 10), position: position(chatelet), vehicle: withPlatform('4'), vehicleStep: 1));
      expect(alerts.single.title, currentL10n.alertPlatformChanged('RER A', '4'));
      expect(alerts.single.urgent, isTrue);
    });

    test('also while walking to the station', () {
      final (_, alerts) = rerTracker.update(rerTracker.initial(), input(at(1), vehicle: withPlatform('1'), vehicleStep: 1));
      expect(alerts.map((alert) => alert.id), contains('platform-1-1'));
    });

    test('nothing for the metro, whose platform never changes', () {
      final waiting = tracker.jumpTo(tracker.initial(), 1);
      final (_, alerts) = tracker.update(waiting, input(at(3), position: position(chatelet), vehicle: withPlatform('1'), vehicleStep: 1));
      expect(alerts.where((alert) => alert.id.startsWith('platform')), isEmpty);
    });
  });
}
