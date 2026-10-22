import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/features/journey/widgets/journey_time_bar.dart';

import '../../support/samples.dart';

void main() {
  final now = DateTime.utc(2026, 10, 10, 8, 10);
  DateTime at(int minutes) => now.add(Duration(minutes: minutes));

  test('spans the results with a little air, round times every quarter of an hour, now marked', () {
    final axis = TimeAxis.of([
      journey([walk(at(2), 360), transit(at(9), 2700)]),
      journey([walk(at(11), 360), transit(at(17), 2700)]),
    ], now);
    expect(axis.now, now);
    // From now to the latest arrival (09:12), padded
    expect(axis.start.isBefore(now), isTrue);
    expect(axis.end.isAfter(at(62)), isTrue);
    expect(axis.ticks.map((tick) => tick.toLocal().minute % 15), everyElement(0));
    expect(axis.ticks.length, inInclusiveRange(3, 5));
    expect(axis.fraction(now), greaterThan(0));
    expect(axis.fraction(at(62)), lessThan(1));
    expect(axis.fraction(at(-60)), 0);
  });

  test('a search for later leaves now out', () {
    final axis = TimeAxis.of([journey([transit(at(120), 600)])], now);
    expect(axis.now, isNull);
    expect(axis.fraction(at(120)), closeTo(0.03 / 1.06, 0.01));
  });
}
