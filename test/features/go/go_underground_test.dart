import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

/// Underground, the GPS freezes where it last was before the station, or rough positions come now and then, often as
/// the metro gets to a station: the clock leads, set right by them, never held back by a frozen one
void main() {
  setUp(() => useLocale(const Locale('fr')));

  final start = DateTime.utc(2026, 10, 10, 8, 0);
  DateTime at(int minutes, [int seconds = 0]) => start.add(Duration(minutes: minutes, seconds: seconds));

  // A metro line straight east, a station every 800 m or so, two minutes apart: S0 at 8:00 to S6 at 8:12
  final stations = [
    for (var k = 0; k < 7; k++)
      StopAreaSummary(id: 'IDFM:7100$k', name: 'S$k', lat: 48.85, lon: 2.30 + 0.011 * k, lines: const [metro1]),
  ];
  final tracker = GoTracker(journey([
    transit(at(0), 720, from: stations.first, to: stations.last, via: stations.sublist(1, 6)),
    walk(at(12), 180, from: point(stations.last), to: const JourneyPoint(name: 'Bureau', lat: 48.8510, lon: 2.3680)),
  ]));
  final ride = tracker.steps[0];
  LatLng station(int k) => LatLng(stations[k].lat, stations[k].lon);
  final onBoard = tracker.next(tracker.initial());

  GoInput rough(DateTime now, LatLng position, {double accuracy = 120, DateTime? fixAt}) =>
      GoInput(now: now, position: position, accuracy: accuracy, fixAt: fixAt ?? now);

  test('the GPS frozen at the station boarded at for five stations: the clock goes on, nothing goes back', () {
    var progress = onBoard;
    // The last position before going underground, given again and again (as old as when first given: positionSince)
    for (var minute = 1; minute <= 11; minute++) {
      final (next, _) = tracker.update(progress, GoInput(now: at(minute), position: station(0), accuracy: 15, fixAt: at(0)));
      expect(next.stopIndex, greaterThanOrEqualTo(progress.stopIndex), reason: '8:${minute.toString().padLeft(2, '0')}');
      progress = next;
    }
    // S5 left at 8:10:20: S6 is next
    expect(progress.stopIndex, 5);
    expect(progress.phase, GoPhase.onBoard);

    // A rough position frozen there (the system's, a cell tower) is no fresher
    final (frozen, _) = tracker.update(onBoard, rough(at(9), station(0), accuracy: 60, fixAt: at(0, 30)));
    expect(frozen.stopIndex, 4);
  });

  test('rough positions now and then near the stations: the clock set on them, "get off" on time', () {
    // The metro runs two minutes late; positions come near S2 and S4 as it stands there
    var (progress, _) = tracker.update(onBoard, rough(at(6, 10), station(2)));
    expect(progress.hintStop, 2);
    expect(progress.shift.inSeconds, closeTo(120, 10));
    // On its clock now: S3 not left at 8:06:30, as the plan would say
    expect(progress.stopIndex, 1);

    // A second one on time with it: nothing to change
    final shift = progress.shift;
    (progress, _) = tracker.update(progress, rough(at(10, 10), station(4)));
    expect(progress.shift, shift);

    // Off at S6 at 8:14, not 8:12
    var alerts = <GoAlert>[];
    (progress, alerts) = tracker.update(progress, GoInput(now: at(13, 50)));
    expect(progress.phase, GoPhase.onBoard);
    expect(alerts.where((alert) => alert.id == 'alight-0'), isEmpty);
    (progress, alerts) = tracker.update(progress, GoInput(now: at(14, 5)));
    expect(alerts.map((alert) => alert.id), contains('alight-0'));
  });

  test('one rough position stations behind the clock is the GPS stuck there; a second one further on, the metro late', () {
    // At 8:10 the clock says S5; a position at S1
    var (progress, _) = tracker.update(onBoard, rough(at(10), station(1)));
    expect(progress.shift, Duration.zero);
    expect(progress.pendingHintStop, 1);
    expect(progress.stopIndex, 4);

    // The same station again later: still nothing
    (progress, _) = tracker.update(progress, rough(at(10, 30), station(1).offset(30)));
    expect(progress.shift, Duration.zero);

    // Then S2: the metro really is six minutes late, back to S1 left
    (progress, _) = tracker.update(progress, rough(at(10, 40), station(2)));
    expect(progress.hintStop, 2);
    expect(progress.shift.inMinutes, 6);
    expect(progress.stopIndex, 1);
  });

  test('a rough position further than the next station is not believed', () {
    final (progress, _) = tracker.update(onBoard, rough(at(3), station(5)));
    expect(progress.shift, Duration.zero);
    expect(progress.hintStop, 0);
  });

  test('a precise fix seen within the minute leads: no rough position nor clock moves the stops', () {
    final along = ride.stopAlongs[2] - 300;
    var (progress, _) = tracker.update(onBoard, GoInput(now: at(5), position: ride.line.pointAt(along - 100), accuracy: 10, speed: 9, fixAt: at(5)));
    (progress, _) = tracker.update(progress, GoInput(now: at(5, 10), position: ride.line.pointAt(along), accuracy: 10, speed: 9, fixAt: at(5, 10)));
    expect(progress.stopIndex, 1);
    (progress, _) = tracker.update(progress, rough(at(5, 40), station(3)));
    expect(progress.hintStop, 0);
    expect(progress.stopIndex, 1);
  });

  test('into a tunnel at speed, the clock bounded by how far the metro can have gone since', () {
    // Seen at S1 at 8:02 on time, then nothing
    var (progress, _) = tracker.update(onBoard, GoInput(now: at(2), position: station(1), accuracy: 10, fixAt: at(2)));
    expect(progress.preciseAlong, isNotNull);
    // The clock alone would say S6 at 8:12; the metro was seen at S1 ten seconds before a plan running five minutes
    // late would leave it. With its delay measured on it, at most 22 m/s since
    progress = progress.copyWith(shift: const Duration(minutes: -5));
    (progress, _) = tracker.update(progress, GoInput(now: at(3, 30)));
    expect(ride.stopAlongs[progress.stopIndex], lessThanOrEqualTo(ride.stopAlongs[1] + 22 * 90 + 1));
  });
}

extension on LatLng {
  LatLng offset(double meters) => const Distance().offset(this, meters, 90);
}
