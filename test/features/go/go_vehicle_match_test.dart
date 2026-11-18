import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/go/go_vehicle_match.dart';
import 'package:website_app/features/go/go_tracker.dart';

import '../../support/samples.dart';

typedef _Position = ({DateTime time, double along});

void main() {
  final start = DateTime.utc(2026, 10, 30, 7, 10);
  DateTime at(int seconds) => start.add(Duration(seconds: seconds));

  const vincennes = StopAreaSummary(id: 'IDFM:70004', name: 'Vincennes', lat: 48.8474, lon: 2.4334);
  const fontenay = StopAreaSummary(id: 'IDFM:70005', name: 'Fontenay-sous-Bois', lat: 48.8432, lon: 2.4878);

  /// A train of the RER A leaving Châtelet at [departs], stopping at [stops]
  Ride train(String number, DateTime departs, List<StopAreaSummary> stops) => ride(departs, trainNumber: number).copyWith(stops: [
        for (final (index, stop) in stops.indexed)
          JourneyStop(name: stop.name, lat: stop.lat, lon: stop.lon, time: departs.add(Duration(minutes: 3 * index))),
      ]);

  /// The ride followed in GO: along the tracks through [through], stopping where [followed] does
  GoStep stepOf(Ride followed, List<StopAreaSummary> through, {StopAreaSummary to = nation}) =>
      GoStep(transit(followed.departure.time, 600, line: rerA, to: to, via: through).copyWith(stops: followed.stops), 0);

  /// Fixes every 3 s along [step]'s way at [speeds] (m/s, one per fix), from [from]; where they end
  _Position travel(VehicleMatch guess, GoStep step, _Position from, List<double> speeds) {
    var (:time, :along) = from;
    for (final speed in speeds) {
      guess.observe(time, step.line.pointAt(along), speed: speed, accuracy: 10);
      along += speed * 3;
      time = time.add(const Duration(seconds: 3));
    }
    return (time: time, along: along);
  }

  // From Châtelet to Nation: the stopping train of 7:10 through Gare de Lyon, the express of 7:10:30 straight there
  final stopping = train('1', at(0), [chatelet, gareDeLyon, nation]);
  final express = train('2', at(30), [chatelet, nation]);
  final onStopping = stepOf(stopping, [gareDeLyon]);
  final onExpress = stepOf(express, [gareDeLyon]);
  final lyon = onStopping.stopAlongs[1];

  test('the departure that left when the user did, among those seen at the stop', () {
    final later = train('3', at(150), [chatelet, nation]);
    final rides = [stopping, later, train('4', at(600), [chatelet, nation]), ride(at(140), trainNumber: '5')];

    // Seen leaving at 7:12:35: the train of 7:12:30, not the one followed two minutes before (nor one leaving too far
    // from then, nor one whose stops aren't known)
    final guess = VehicleMatch.start(0, onStopping, rides, departed: at(155));
    expect(guess.candidates, [stopping, later]);
    expect(guess.better, later);
    guess.follow(later);
    expect(guess.better, isNull);

    // Seen leaving when the one followed did: nothing to change
    expect(VehicleMatch.start(0, onStopping, rides, departed: at(5)).better, isNull);
  });

  test('the stops followed being none of theirs: the one that left when the user did, if any', () {
    final unknown = GoStep(transit(at(0), 600, line: rerA, via: [gareDeLyon]).copyWith(stops: const []), 0);

    expect(VehicleMatch.start(0, unknown, [stopping, express], departed: at(25)).better, express);
    expect(VehicleMatch.start(0, unknown, [express], departed: at(-60)).better, isNull);
  });

  test('a station run through: not the train stopping there', () {
    // Left 30 s apart: the times alone don't tell them apart
    final guess = VehicleMatch.start(0, onStopping, [stopping, express], departed: at(10));
    expect(guess.better, isNull);

    // At 15 m/s by Gare de Lyon
    travel(guess, onStopping, (time: at(150), along: lyon - 600), List.filled(30, 15));

    expect(guess.better, express);
  });

  test('a stop at a station only the stopping train serves: that one', () {
    final guess = VehicleMatch.start(0, onExpress, [stopping, express], departed: at(25));
    expect(guess.better, isNull);

    // Slowing down by Gare de Lyon, 30 s there, leaving again
    var position = travel(guess, onExpress, (time: at(150), along: lyon - 400), [15, 15, 15, 15, 12, 9, 6, 3]);
    position = travel(guess, onExpress, position, List.filled(10, 0));
    travel(guess, onExpress, position, [2, 5, 8, 11, 14, 15, 15, 15, 15, 15, 15, 15]);

    expect(guess.better, stopping);
  });

  test('fixes too far apart, too slow or too blurred tell nothing', () {
    // Before Gare de Lyon, then 40 s later past it: it may have stopped in between
    final sparse = VehicleMatch.start(0, onStopping, [stopping, express], departed: at(10));
    var position = travel(sparse, onStopping, (time: at(150), along: lyon - 300), [15, 15]);
    travel(sparse, onStopping, (time: position.time.add(const Duration(seconds: 37)), along: lyon + 300), [15, 15]);
    expect(sparse.better, isNull);

    // Through it at 4 m/s (works on the line)
    final slow = VehicleMatch.start(0, onStopping, [stopping, express], departed: at(10));
    travel(slow, onStopping, (time: at(150), along: lyon - 300), List.filled(60, 4));
    expect(slow.better, isNull);

    // Fixes within 80 m only
    final blurred = VehicleMatch.start(0, onStopping, [stopping, express], departed: at(10));
    for (var k = 0; k < 30; k++) {
      blurred.observe(at(150 + 3 * k), onStopping.line.pointAt(lyon - 600 + 45.0 * k), speed: 15, accuracy: 80);
    }
    expect(blurred.better, isNull);
  });

  test('the same stops: nothing to tell them apart but the time', () {
    final other = train('3', at(40), [chatelet, gareDeLyon, nation]);
    final guess = VehicleMatch.start(0, onStopping, [stopping, other], departed: at(10));

    travel(guess, onStopping, (time: at(150), along: lyon - 600), List.filled(30, 15));

    expect(guess.better, isNull);
  });

  test('checked again at each station: a stop at a signal is put right further on', () {
    // To Fontenay: the stopping train serves Gare de Lyon, Nation and Vincennes, the express only Nation
    final everyStation = train('1', at(0), [chatelet, gareDeLyon, nation, vincennes, fontenay]);
    final fewStations = train('2', at(30), [chatelet, nation, fontenay]);
    final step = stepOf(fewStations, [gareDeLyon, nation, vincennes], to: fontenay);
    double alongOf(StopAreaSummary stop) => step.line.project(LatLng(stop.lat, stop.lon))!.along;
    final guess = VehicleMatch.start(0, step, [everyStation, fewStations], departed: at(30));
    expect(guess.better, isNull);

    // Held 30 s at a signal by Gare de Lyon: the stopping train, for now
    var position = travel(guess, step, (time: at(150), along: alongOf(gareDeLyon) - 300), List.filled(6, 15));
    position = travel(guess, step, position, List.filled(10, 0));
    position = travel(guess, step, position, List.filled(12, 15));
    expect(guess.better, everyStation);
    guess.follow(everyStation);

    // Through Vincennes at full speed: the express after all
    travel(guess, step, (time: position.time, along: alongOf(vincennes) - 600), List.filled(30, 20));
    expect(guess.better, fewStations);
  });

  group('from the platform on', () {
    // The planned train of 7:10 six minutes late, seated in it at the platform; another one leaves on time at 7:11
    final late = train('1', at(360), [chatelet, gareDeLyon, nation]).copyWith(
        departure: departure(at(360), aimed: at(0), trainNumber: '1').copyWith(atStop: true));
    final onTime = train('2', at(60), [chatelet, gareDeLyon, nation]);
    final step = stepOf(train('1', at(0), [chatelet, gareDeLyon, nation]), [gareDeLyon]);

    test('a train gone while the user stays at the platform is not theirs', () {
      // Its real time a little off: said leaving at 7:11:30
      final lateSoon = late.copyWith(departure: late.departure.copyWith(time: at(90), atStop: null));
      final match = VehicleMatch(0, step)..seen([lateSoon, onTime], at(-120));
      for (var second = 0; second <= 150; second += 30) {
        match.stillAtPlatform(at(second));
      }
      // Leaving assumed at 7:11 (underground, no GPS to see it), when the other one left: not that one
      match.departed(at(60));
      expect(match.candidates, containsAll([lateSoon, onTime]));
      expect(match.better, isNull);
      match.follow(onTime);
      expect(match.better, lateSoon);

      // Had the user not been seen still on the platform, nothing to tell them apart
      final unseen = VehicleMatch.start(0, step, [lateSoon, onTime], departed: at(60));
      unseen.follow(onTime);
      expect(unseen.better, isNull);
    });

    test('a train the real time says is at the platform has not left, however late its time', () {
      final match = VehicleMatch(0, step)
        ..seen([late.copyWith(departure: late.departure.copyWith(time: at(30))), onTime], at(240));
      match.stillAtPlatform(at(300));
      match.departed(at(330));
      expect(match.better, isNull);
    });

    test('one leaving minutes after the user did had not left', () {
      final match = VehicleMatch.start(0, step, [onTime, late.copyWith(departure: late.departure.copyWith(time: at(220), atStop: null))],
          departed: at(60));
      expect(match.candidates, hasLength(2));
      // The planned one (7:10, its real time 7:13:40) is followed until then: the one that left with the user instead
      expect(match.better, onTime);
    });

    test('on board, the real time says another one is still at the stop: not that one', () {
      final other = train('3', at(90), [chatelet, gareDeLyon, nation]);
      final match = VehicleMatch.start(0, step, [onTime, other], departed: at(75));
      expect(match.better, isNull);
      match.seen([other.copyWith(departure: other.departure.copyWith(atStop: true))], at(150), userGone: true);
      expect(match.better, isNull);
      match.follow(other);
      expect(match.better, onTime);
    });

    test('where each one should be by its times, against where the GPS puts the user', () {
      // Same stops, 2 min 30 apart: at 7:14, the user where the one of 7:11 is
      final next = train('3', at(210), [chatelet, gareDeLyon, nation]);
      final match = VehicleMatch.start(0, step, [onTime, next], departed: at(135));
      match.follow(next);
      final lyonAt = step.line.project(LatLng(gareDeLyon.lat, gareDeLyon.lon))!.along;
      // 7:14 is Gare de Lyon for the one of 7:11 (3 min a stop), half of the way for the other
      match.observe(at(240), step.line.pointAt(lyonAt), speed: 0, accuracy: 10);
      match.observe(at(300), step.line.pointAt(lyonAt + 20), speed: 2, accuracy: 10);
      expect(match.better, onTime);
    });
  });
}
