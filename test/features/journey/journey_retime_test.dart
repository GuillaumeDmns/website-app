import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/journey/journey_retime.dart';

import '../../support/samples.dart';

void main() {
  final now = DateTime.utc(2026, 10, 10, 8, 0);
  DateTime at(int minutes) => now.add(Duration(minutes: minutes));

  // Walk 5 min to Châtelet, metro 1 planned at 8:10 to Gare de Lyon (8 min), wait, RER A at 8:25 to Nation (6 min)
  final planned = journey([
    walk(at(0), 300),
    transit(at(10), 480, to: gareDeLyon),
    wait(at(18), 420),
    transit(at(25), 360, line: rerA, from: gareDeLyon, to: nation),
  ]);

  RideLookup lookupOf(Map<String, List<Ride>> byLine) => (key) => byLine[key.lineId];

  group('rideKey', () {
    test('starts now for a ride boarded soon, at the minute otherwise', () {
      final section = planned.sections[1];

      expect(rideKey(section, at(3), now), (lineId: 'C01371', from: 'IDFM:70001', to: 'IDFM:70002', after: null));
      expect(rideKey(section, now.add(const Duration(minutes: 12, seconds: 40)), now)!.after, DateTime.utc(2026, 10, 10, 8, 12));
    });

    test('needs a GTFS line and two stop areas', () {
      final unknownLine = planned.sections[1].copyWith(line: const LineSummary(id: '', mode: TransportMode.bus));

      expect(rideKey(unknownLine, now, now), isNull);
      expect(rideKey(planned.sections[0], now, now), isNull);
    });
  });

  test('recognizes the same departure across refreshes', () {
    expect(sameRide(ride(at(10), trainNumber: '1'), ride(at(14), trainNumber: '1')), isTrue);
    expect(sameRide(ride(at(10), trainNumber: '1'), ride(at(10), trainNumber: '2')), isFalse);
    expect(sameRide(ride(at(10), aimed: at(9)), ride(at(12), aimed: at(9))), isTrue);
    expect(sameRide(ride(at(10)), ride(at(12))), isFalse);
  });

  test('finds the planned departure among the next ones', () {
    final rides = [ride(at(4)), ride(at(11), aimed: at(10)), ride(at(16))];

    expect(plannedRide(rides, at(10)), rides[1]);
    expect(plannedRide(rides, at(30)), isNull);
  });

  test('keeps the plan when its departures are unknown', () {
    final retimed = retimeJourney(planned, lookup: (_) => null, now: now);

    // The rides keep their times; the walk ends when the metro leaves
    expect(retimed.journey.sections.skip(1).map((section) => section.departure),
        planned.sections.skip(1).map((section) => section.departure));
    expect(retimed.journey.sections.first.departure, at(5));
    expect(retimed.rides.keys, [1, 3]);
    expect(retimed.rides[1]!.ride, isNull);
  });

  test('follows the real time of the planned departures', () {
    final metro = ride(at(12), aimed: at(10));
    final rer = ride(at(27), aimed: at(25), ride: const Duration(minutes: 6));

    final retimed = retimeJourney(planned, lookup: lookupOf({'C01371': [metro], 'C01742': [rer]}), now: now).journey;

    expect(retimed.sections[1].departure, at(12));
    expect(retimed.sections[1].delay, 120);
    expect(retimed.sections[1].realtime, isTrue);
    // The walk leaves later to get there when the metro leaves
    expect(retimed.sections[0].departure, at(7));
    // The wait fills the time until the RER
    expect(retimed.sections[2].departure, metro.arrivalAt);
    expect(retimed.sections[2].arrival, at(27));
    expect(retimed.arrival, at(33));
    expect(retimed.duration, at(33).difference(at(7)).inSeconds);
  });

  test('takes the next departure when the planned one can no longer be caught', () {
    final later = DateTime.utc(2026, 10, 10, 8, 8);
    // Leaving now, the walk ends at 8:13: the metro of 8:10 is gone
    final retimed = retimeJourney(
      planned,
      lookup: lookupOf({'C01371': [ride(at(10)), ride(at(15)), ride(at(20))]}),
      now: later,
    );

    expect(retimed.journey.sections[1].departure, at(15));
    expect(retimed.rides[1]!.earliest, at(13));
  });

  test('skips cancelled departures', () {
    final retimed = retimeJourney(
      planned,
      lookup: lookupOf({'C01371': [ride(at(10), status: 'cancelled'), ride(at(14))]}),
      now: now,
    );

    expect(retimed.journey.sections[1].departure, at(14));
  });

  test('takes the departure chosen by the user, with its latest real time', () {
    final chosen = ride(at(20), trainNumber: '42');
    final retimed = retimeJourney(
      planned,
      lookup: lookupOf({'C01371': [ride(at(10)), ride(at(21), aimed: at(20), trainNumber: '42')]}),
      now: now,
      choices: {1: chosen},
    ).journey;

    expect(retimed.sections[1].departure, at(21));
    // The connection: first RER after the metro's arrival
    expect(retimed.sections[3].departure.isBefore(retimed.sections[1].arrival), isFalse);
  });

  test('stops where the departure taken does: an express train skips some of the planned one', () {
    // Planned: the RER A of 8:10 through Gare de Lyon (6 min). The express of 8:11 goes straight to Nation: its
    // schedule shifted by its delay says 8:12 → 8:16, the real time 8:17
    final stopping = journey([transit(at(10), 360, line: rerA, via: [gareDeLyon])]);
    final express = ride(at(12), aimed: at(11), ride: const Duration(minutes: 5)).copyWith(stops: [
      JourneyStop(name: 'Châtelet', lat: chatelet.lat, lon: chatelet.lon, time: at(12)),
      JourneyStop(name: 'Nation', lat: nation.lat, lon: nation.lon, time: at(16)),
    ]);

    final direct = retimeJourney(stopping, lookup: lookupOf({'C01742': [express]}), now: now, choices: {0: express}).journey;

    expect(direct.sections.single.stops.map((stop) => stop.name), ['Châtelet', 'Nation']);
    expect(direct.sections.single.stops.map((stop) => stop.time), [at(12), at(17)]);

    // The other way round: the train taken stops on the way, at its times shifted with it
    final stoppingRide = ride(at(13), aimed: at(12), ride: const Duration(minutes: 6)).copyWith(stops: [
      JourneyStop(name: 'Châtelet', lat: chatelet.lat, lon: chatelet.lon, time: at(13)),
      JourneyStop(name: 'Gare de Lyon', lat: gareDeLyon.lat, lon: gareDeLyon.lon, time: at(16)),
      JourneyStop(name: 'Nation', lat: nation.lat, lon: nation.lon, time: at(19)),
    ]);
    final through = retimeJourney(direct, lookup: lookupOf({'C01742': [stoppingRide]}), now: now, choices: {0: stoppingRide}).journey;

    expect(through.sections.single.stops.map((stop) => stop.name), ['Châtelet', 'Gare de Lyon', 'Nation']);
    expect(through.sections.single.stops[1].time, at(16));

    // Stops not known: the planned ones, at times moved with the departure
    final unknown = retimeJourney(stopping, lookup: lookupOf({'C01742': [ride(at(12), aimed: at(11))]}), now: now).journey;

    expect(unknown.sections.single.stops.map((stop) => stop.name), ['Châtelet', 'Gare de Lyon', 'Nation']);
    expect(unknown.sections.single.stops.first.time, at(12));
  });

  test('moves the later rides after a late one', () {
    final retimed = retimeJourney(
      planned,
      lookup: lookupOf({'C01371': [ride(at(30), aimed: at(10))]}),
      now: now,
    ).journey;

    // Planned at 8:25, the RER (departures unknown) leaves when the traveller gets there
    expect(retimed.sections[3].departure, retimed.sections[1].arrival);
  });

  test('leaves the part already done in GO mode', () {
    final retimed = retimeJourney(
      planned,
      lookup: lookupOf({'C01742': [ride(at(29), aimed: at(25))]}),
      now: at(20),
      from: 3,
    ).journey;

    expect(retimed.sections.take(3), planned.sections.take(3));
    expect(retimed.sections[3].departure, at(29));
    expect(earliestBoarding(planned, 3, now), planned.sections[1].arrival);
  });

  test('shifts the end of a journey', () {
    final shifted = shiftJourney(planned, from: 2, by: const Duration(minutes: 5));

    expect(shifted.sections[1].departure, planned.sections[1].departure);
    expect(shifted.sections[3].departure, at(30));
    expect(shifted.arrival, planned.arrival.add(const Duration(minutes: 5)));
    // Stop times move too
    expect(shifted.sections[3].stops.last.time, planned.sections[3].stops.last.time!.add(const Duration(minutes: 5)));
  });
}
