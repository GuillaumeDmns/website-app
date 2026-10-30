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

  GoInput input(DateTime now, {LatLng? position, double speed = 0, Departure? vehicle, int? vehicleStep, bool realtime = false}) =>
      GoInput(
        now: now,
        position: position,
        accuracy: 10,
        speed: speed,
        fixAt: now,
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

  test('detects boarding from a fast move along the line', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);
    final onTheWay = LatLng((chatelet.lat + gareDeLyon.lat) / 2, (chatelet.lon + gareDeLyon.lon) / 2);

    final late = departure(at(8), aimed: at(6));

    final (progress, _) = tracker.update(waiting, input(at(8, 30), position: onTheWay, speed: 10, vehicle: late, vehicleStep: 1));

    expect(progress.phase, GoPhase.onBoard);
    // Left two minutes late: the rest of the journey follows
    expect(progress.shift, const Duration(minutes: 2));
    expect(tracker.eta(progress, null), plan.arrival.add(const Duration(minutes: 2)));
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
    expect(retained.eta(progress, null), retainedPlan.arrival.subtract(const Duration(minutes: 6)));
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

  test('arrives near the destination', () {
    final lastWalk = tracker.jumpTo(tracker.initial(), 2);

    final (progress, alerts) = tracker.update(lastWalk, input(at(17), position: const LatLng(48.8475, 2.4000)));

    expect(progress.phase, GoPhase.arrived);
    expect(progress.arrivedAt, at(17));
    expect(alerts.map((alert) => alert.id), ['arrived']);
    expect(tracker.eta(progress, null), at(17));
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
