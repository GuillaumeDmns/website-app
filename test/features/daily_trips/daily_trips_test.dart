import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/daily_trips/daily_trip_widgets.dart';
import 'package:website_app/features/daily_trips/daily_trips.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/features/journey/journey_retime.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/fake_backend.dart';
import '../../support/memory_store.dart';
import '../../support/samples.dart';
import '../../support/test_container.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  // Saved a week ago: 5 min on foot, métro 1 Châtelet → Gare de Lyon (8 min), RER A Gare de Lyon → Nation (4 min)
  final saved = DateTime.utc(2026, 10, 7, 7);
  final trip = journey([
    walk(saved, 300),
    transit(saved.add(const Duration(minutes: 5)), 480, to: gareDeLyon),
    walk(saved.add(const Duration(minutes: 13)), 120, from: point(gareDeLyon), to: point(gareDeLyon)),
    transit(saved.add(const Duration(minutes: 15)), 240, line: rerA, from: gareDeLyon, to: nation),
  ]);
  final now = DateTime.utc(2026, 10, 14, 7, 30);

  test('takes the way back on the same lines, with the same durations', () {
    final back = reverseJourney(trip);

    expect(back.sections.map((section) => section.line?.id), [rerA.id, null, metro1.id, null]);
    expect(back.sections.first.from?.name, 'Nation');
    expect(back.sections.first.to?.name, 'Gare de Lyon');
    expect(back.sections.last.to?.name, address.name);
    expect(back.sections.map((section) => section.duration), [240, 120, 480, 300]);
    expect(back.sections[1].departure, back.sections.first.arrival);
    expect(back.duration, trip.duration);
    // Its destination comes with the departures
    expect(back.sections.first.headsign, isNull);
  });

  test('gives the next ways of making the trip from the departures of its lines', () {
    DateTime at(int minutes) => now.add(Duration(minutes: minutes));
    List<Ride>? lookup(RideKey key) => switch (key.lineId) {
          // From 5 min (the walk): leaves at +7, +12, +17, 8 min to Gare de Lyon
          'C01371' => [ride(at(3)), ride(at(7)), ride(at(12)), ride(at(17))],
          // Every 5 min, 4 min to Nation
          'C01742' => [for (var m = 10; m < 60; m += 5) ride(at(m), ride: const Duration(minutes: 4))],
          _ => null,
        };

    final options = upcomingTrips(trip, lookup: lookup, now: now);

    expect(options, hasLength(3));
    // Leave so as to be at the stop when the métro leaves
    expect(options.map((option) => option.departure), [at(2), at(7), at(12)]);
    // The métro at +7 gets to Gare de Lyon at +15, then 2 min on foot: the RER at +20, at Nation at +24
    expect(options.map((option) => option.arrival), [at(24), at(29), at(34)]);
    // Without departures yet: the planned times, from now
    expect(upcomingTrips(trip, lookup: (_) => null, now: now), hasLength(1));
  });

  group('the last metro', () {
    DateTime at(int hour, int minute) => DateTime.utc(2026, 10, 14, hour, minute);
    ScheduledRide scheduled(DateTime departure) => ScheduledRide(departure: departure, arrival: departure.add(const Duration(minutes: 8)));
    RideSpan span(DateTime last, {DateTime? first, DateTime? next}) =>
        RideSpan(first: scheduled(first ?? at(3, 30)), last: scheduled(last), next: scheduled(next ?? at(27, 30)));

    test('sets when to leave at the latest, from the ride whose last departure comes first', () {
      // Métro's last at 22:41 (5 min from the start), RER's at 22:50 (15 min from the start, waits aside)
      final alert = lastTripAlert(trip, (ride) => ride.line == metro1 ? span(at(22, 41)) : span(at(22, 50)), at(22, 0));

      expect(alert?.over, isFalse);
      expect(alert?.leaveBy, at(22, 35));
      expect(alert?.ride.line, rerA);
      expect(lastTripText(alert, at(22, 0)), 'Dernier RER A à ${formatLocal(at(22, 50))} · partir avant ${formatLocal(at(22, 35))}');
      // Said from an hour before
      expect(lastTripText(alert, at(21, 30)), isNull);
    });

    test('says when it is too late, and when the trip can be made again', () {
      final alert = lastTripAlert(trip, (ride) => span(at(22, 41), next: at(27, 30)), at(22, 40));

      expect(alert?.over, isTrue);
      // The métro's first ride tomorrow, 5 min from the start (the RER's comes after it)
      expect(alert?.resumesAt, at(27, 25));
      expect(lastTripText(alert, at(22, 40)), 'Service terminé · reprise vers ${formatLocal(at(27, 25))}');

      // At night, the spans already are the next service day's
      final night = lastTripAlert(trip, (ride) => span(at(46, 41), first: at(27, 30)), at(25, 0));
      expect(night?.over, isTrue);
      expect(night?.resumesAt, at(27, 25));
    });

    test('has nothing to say of lines running all night, or without their spans', () {
      expect(lastTripAlert(trip, (ride) => span(at(22, 41), next: at(23, 1)), at(22, 0)), isNull);
      expect(lastTripAlert(trip, (ride) => null, at(22, 0)), isNull);
    });
  });

  test('keeps the trips on the device, once each, and forgets them', () async {
    final store = MemoryStore();
    final container = testContainer(FakeBackend(), store: store);
    await sessionOf(container);
    final trips = container.read(dailyTripsProvider.notifier);
    await container.read(dailyTripsProvider.future);

    await trips.save(trip, const JourneyRequest(from: JourneyPlace.currentLocation()), now: now);
    await trips.save(trip, const JourneyRequest(), now: now.add(const Duration(minutes: 1)));
    expect(container.read(dailyTripsProvider).value, hasLength(1));
    expect(trips.find(trip), isNotNull);
    // The way back is that trip too
    expect(trips.find(reverseJourney(trip)), isNotNull);
    expect(trips.find(journey([walk(saved, 300)])), isNull);

    // Read back as saved, "Ma position" replaced by where the trip starts
    final read = DailyTrip.fromJson((await store.readJson(DailyTrips.key) as List).single as Map<String, dynamic>)!;
    expect(read.lines, '${metro1.id},${rerA.id}');
    expect(read.journey.sections.first.from?.name, address.name);

    await trips.remove(trips.find(trip)!);
    expect(container.read(dailyTripsProvider).value, isEmpty);
  });
}

/// As the app shows a time
String formatLocal(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
