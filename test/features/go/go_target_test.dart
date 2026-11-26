import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/go/go_guidance.dart';

import '../../support/samples.dart';

/// The departure GO aims at before the user is on the ride: the one they can catch arriving first
void main() {
  final start = DateTime.utc(2026, 11, 25, 8, 0);
  DateTime at(int minutes, [int seconds = 0]) => start.add(Duration(minutes: minutes, seconds: seconds));
  Ride train(String number, int leaves, int arrives) =>
      ride(at(leaves), trainNumber: number, ride: Duration(minutes: arrives - leaves));

  // The line L at Bécon: a stopping train at 8:14 arriving 8:24, a direct at 8:16 arriving 8:23, the next stopping
  // train at 8:25 arriving 8:35
  final stopping = train('135060', 14, 24);
  final direct = train('134540', 16, 23);
  final next = train('135064', 25, 35);
  final rides = [stopping, direct, next];

  test('of those the user can catch, the one arriving first: never a stopping train leaving first', () {
    // At the stop by 8:10: the direct, though the stopping train leaves before it
    expect(targetRide(rides, at(10)), direct);
    // At 8:15:40, the direct is still there to catch (30 s to spare)
    expect(targetRide(rides, at(15, 30)), direct);
    // At 8:16, too late for it: the next one
    expect(targetRide(rides, at(16)), next);
  });

  test('the one aimed at kept while it can still be caught hurrying, and none arrives a minute earlier', () {
    // Aiming at the stopping train: the direct arrives a minute earlier and can be caught, it is aimed at instead
    expect(targetRide(rides, at(10), current: stopping), direct);
    // A pace measured a little slower: 30 s late for the direct, it is kept (the user may hurry)
    expect(targetRide(rides, at(16, 30), current: direct), direct);
    // A minute and a half late: gone
    expect(targetRide(rides, at(17, 30), current: direct), next);
    // Another one arriving only 30 s earlier: the one aimed at stays
    final close = train('135062', 15, 22);
    final almost = close.copyWith(arrivalAt: at(22, 30));
    expect(targetRide([direct, almost], at(10), current: direct), direct);
    expect(targetRide([direct, close], at(10), current: direct), close);
  });

  test('a cancelled departure is never aimed at; without any to catch, the one aimed at stays', () {
    final cancelled = direct.copyWith(departure: direct.departure.copyWith(status: 'cancelled'));
    expect(targetRide([stopping, cancelled, next], at(10)), stopping);
    expect(targetRide([direct], at(20), current: direct), direct);
    expect(targetRide([], at(20)), isNull);
  });
}
