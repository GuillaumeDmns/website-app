import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/geo.dart';
import 'package:website_app/features/lines/line_vehicles.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  final fetchedAt = DateTime.utc(2026, 10, 10, 8, 0);

  Vehicle vehicle({String? from = 'IDFM:1', String to = 'IDFM:2', double progress = 0.5, Duration toNext = const Duration(minutes: 1)}) =>
      Vehicle(
        id: 'v1',
        destination: 'Nation',
        direction: 0,
        branch: 0,
        fromStopId: from,
        toStopId: to,
        toStopName: 'Gare de Lyon',
        progress: progress,
        expectedAt: fetchedAt.add(toNext),
      );

  group('vehicleProgress', () {
    test('keeps moving between two fetches', () {
      // Halfway with a minute to go: the segment takes 2 min
      final moving = vehicle();

      expect(vehicleProgress(moving, fetchedAt, fetchedAt), 0.5);
      expect(vehicleProgress(moving, fetchedAt, fetchedAt.add(const Duration(seconds: 30))), closeTo(0.75, 0.001));
      expect(vehicleProgress(moving, fetchedAt, fetchedAt.add(const Duration(minutes: 5))), 1);
    });

    test('never goes back and stays at the stop when due', () {
      expect(vehicleProgress(vehicle(), fetchedAt, fetchedAt.subtract(const Duration(minutes: 1))), 0.5);
      expect(vehicleProgress(vehicle(toNext: Duration.zero), fetchedAt, fetchedAt), 1);
      expect(vehicleProgress(vehicle(from: null), fetchedAt, fetchedAt), 1);
    });
  });

  group('vehicleAt', () {
    // Halfway to Gare de Lyon (in a minute), then Bastille 2 min later, then Nation 2 min after that
    VehicleCall call(String stopId, String name, Duration fromFetch, {Duration? departure}) => VehicleCall(
          stopId: stopId,
          stopName: name,
          expectedAt: fetchedAt.add(fromFetch),
          departureAt: departure == null ? null : fetchedAt.add(departure),
        );
    final calls = [
      call('IDFM:2', 'Gare de Lyon', const Duration(minutes: 1)),
      call('IDFM:3', 'Bastille', const Duration(minutes: 3)),
      call('IDFM:4', 'Nation', const Duration(minutes: 5)),
    ];
    final moving = vehicle().copyWith(calls: calls);
    ({Vehicle vehicle, double progress}) at(Duration fromFetch, {Vehicle? of, TransportMode mode = TransportMode.metro}) =>
        vehicleAt(of ?? moving, fetchedAt, fetchedAt.add(fromFetch), mode);

    test('moves along its segment, then stands at the stop a while', () {
      expect(at(const Duration(seconds: 30)).vehicle.toStopId, 'IDFM:2');
      expect(at(const Duration(seconds: 30)).progress, closeTo(0.75, 0.001));
      // Arrived; a metro stands 20 s
      final standing = at(const Duration(minutes: 1, seconds: 15));
      expect(standing.vehicle.toStopId, 'IDFM:2');
      expect(standing.progress, 1);
      expect(vehicleLabel(standing.vehicle, fetchedAt.add(const Duration(minutes: 1, seconds: 15)), TransportMode.metro),
          '→ Nation · Gare de Lyon à quai');
    });

    test('moves on to the following stops by itself, on their times', () {
      // Left Gare de Lyon at 1:20, at Bastille at 3:00: halfway at 2:10
      final on = at(const Duration(minutes: 2, seconds: 10));
      expect(on.vehicle.id, 'v1');
      expect(on.vehicle.fromStopId, 'IDFM:2');
      expect(on.vehicle.toStopId, 'IDFM:3');
      expect(on.vehicle.toStopName, 'Bastille');
      expect(on.vehicle.calls.map((call) => call.stopName), ['Bastille', 'Nation']);
      expect(on.progress, closeTo(0.5, 0.001));
      // Then towards Nation, and at the last stop it stays
      expect(at(const Duration(minutes: 4)).vehicle.toStopId, 'IDFM:4');
      expect(at(const Duration(minutes: 9)).vehicle.toStopId, 'IDFM:4');
      expect(at(const Duration(minutes: 9)).progress, 1);
    });

    test('stands until the departure the real time gives, or longer for a train', () {
      final standing = moving.copyWith(calls: [
        call('IDFM:2', 'Gare de Lyon', const Duration(minutes: 1), departure: const Duration(minutes: 2)),
        ...calls.skip(1),
      ]);
      expect(at(const Duration(minutes: 1, seconds: 50), of: standing).vehicle.toStopId, 'IDFM:2');
      expect(at(const Duration(minutes: 2, seconds: 10), of: standing).vehicle.toStopId, 'IDFM:3');
      // A RER stands 40 s without a departure given
      expect(at(const Duration(minutes: 1, seconds: 30), mode: TransportMode.rer).vehicle.toStopId, 'IDFM:2');
      expect(at(const Duration(minutes: 1, seconds: 50), mode: TransportMode.rer).vehicle.toStopId, 'IDFM:3');
    });

    test('leaves where its trip starts at the time given, and skips stops off its branch', () {
      final waiting = vehicle(from: null, toNext: Duration.zero).copyWith(calls: [
        call('IDFM:2', 'Gare de Lyon', Duration.zero),
        ...calls.skip(1),
      ]);
      expect(at(const Duration(seconds: 5), of: waiting).vehicle.toStopId, 'IDFM:3');

      final offBranch = vehicleAt(moving, fetchedAt, fetchedAt.add(const Duration(minutes: 2)), TransportMode.metro,
          serves: (stopId) => stopId != 'IDFM:3');
      expect(offBranch.vehicle.toStopId, 'IDFM:4');
      expect(offBranch.vehicle.fromStopId, 'IDFM:2');
    });

    test('stays as fetched without its calls', () {
      expect(at(const Duration(minutes: 3), of: vehicle()).vehicle, vehicle());
      expect(at(const Duration(minutes: 3), of: vehicle()).progress, 1);
    });
  });

  group('BranchPath', () {
    const branch = LineBranch(headsign: 'Nation', tripCount: 10, stops: [
      StopRef(id: 'IDFM:1', name: 'Châtelet', lat: 48.8584, lon: 2.3470),
      StopRef(id: 'IDFM:2', name: 'Gare de Lyon', lat: 48.8443, lon: 2.3730),
      StopRef(id: 'IDFM:3', name: 'Nation', lat: 48.8484, lon: 2.3959),
    ]);
    final path = BranchPath(branch);

    test('places a vehicle between its stops', () {
      final halfway = path.place(vehicle(), 0.5)!.point;

      expect(halfway.latitude, closeTo((48.8584 + 48.8443) / 2, 0.0005));
      expect(path.place(vehicle(), 1)!.point.latitude, closeTo(48.8443, 0.0001));
    });

    test('places a vehicle waiting at the first stop on it', () {
      expect(path.place(vehicle(from: null, to: 'IDFM:1'), 1)!.point.latitude, closeTo(48.8584, 0.0001));
    });

    test('takes the previous stop when the one left is not on the branch', () {
      expect(path.place(vehicle(from: 'IDFM:9', to: 'IDFM:3'), 0)!.point.latitude, closeTo(48.8443, 0.0001));
    });

    test('tells which way a vehicle goes', () {
      // Châtelet → Gare de Lyon goes south-east
      final place = path.place(vehicle(), 0.1)!;

      expect(place.heading, closeTo(bearingBetween(const LatLng(48.8584, 2.3470), const LatLng(48.8443, 2.3730)), 2));
    });

    test('points a vehicle waiting at a stop the way the branch goes', () {
      final waiting = path.place(vehicle(from: null, to: 'IDFM:1'), 1)!;

      expect(waiting.heading, greaterThan(90));
      expect(waiting.heading, lessThan(180));
    });

    test('ignores vehicles of another branch', () {
      expect(path.place(vehicle(to: 'IDFM:99'), 0.5), isNull);
    });

    test('keeps the stretches through stops a path drawn does not serve', () {
      // All served: nothing to add (the other direction on the same tracks)
      expect(path.partsOff({'IDFM:1', 'IDFM:2', 'IDFM:3'}), isEmpty);

      // Gare de Lyon served the other way only: from Châtelet to Nation, through it
      final [loop] = path.partsOff({'IDFM:1', 'IDFM:3'});
      expect(loop.first.latitude, closeTo(48.8584, 0.0001));
      expect(loop.last.latitude, closeTo(48.8484, 0.0001));
      expect(loop.any((point) => (point.latitude - 48.8443).abs() < 0.0001), isTrue);

      // Its own end: from the last stop served to the path's end
      final [end] = path.partsOff({'IDFM:1', 'IDFM:2'});
      expect(end.first.latitude, closeTo(48.8443, 0.0001));
      expect(end.last.latitude, closeTo(48.8484, 0.0001));
    });
  });

  test('lists a stop area served twice in a row once', () {
    const denfert = StopRef(id: 'D', name: 'Denfert-Rochereau', lat: 48.834, lon: 2.333);
    const branch = LineBranch(headsign: 'Porte de la Chapelle', tripCount: 10, stops: [
      StopRef(id: 'A', name: 'Alésia', lat: 48.828, lon: 2.327),
      denfert,
      denfert,
      StopRef(id: 'P', name: 'Port Royal', lat: 48.840, lon: 2.337),
      denfert,
    ]);

    // Twice in a row once; again later (a loop) kept
    expect(stopsOnce(branch).map((stop) => stop.id), ['A', 'D', 'P', 'D']);
  });

  test('tells how on time a vehicle is', () {
    expect(Punctuality.of(vehicle()), Punctuality.unknown);
    expect(Punctuality.of(vehicle().copyWith(delaySeconds: 30)), Punctuality.onTime);
    expect(Punctuality.of(vehicle().copyWith(delaySeconds: -90)), Punctuality.onTime);
    expect(Punctuality.of(vehicle().copyWith(delaySeconds: 60)), Punctuality.late);
  });

  testWidgets('draws a vehicle as a capsule, larger when selected, late or not alike', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Row(children: [
        VehicleCapsule(line: metro1),
        VehicleCapsule(line: metro1, atStop: true, selected: true),
      ]),
    ));

    expect(tester.getSize(find.byType(VehicleCapsule).first), Size.square(VehicleCapsule.boxSize()));
    expect(tester.getSize(find.byType(VehicleCapsule).last), Size.square(VehicleCapsule.boxSize(selected: true)));
    // One image per line and look, nothing of its punctuality in it
    expect(VehicleCapsule.imageName(metro1, atStop: false, selected: false),
        isNot(VehicleCapsule.imageName(metro1, atStop: true, selected: false)));
  });

  test('says when a vehicle gets to its next stop, and its delay', () {
    expect(vehicleWhen(vehicle(toNext: const Duration(seconds: 70)), fetchedAt, TransportMode.metro, atStop: false), '2 min');
    expect(vehicleWhen(vehicle(), fetchedAt, TransportMode.metro, atStop: true), 'à quai');
    // Due but still on its way: never "à quai" between two stops
    expect(vehicleWhen(vehicle(toNext: const Duration(seconds: -20)), fetchedAt, TransportMode.metro, atStop: false), '1 min');
    expect(vehicleDelay(vehicle()), isNull);
    expect(vehicleDelay(vehicle().copyWith(delaySeconds: 30)), isNull);
    expect(vehicleDelay(vehicle().copyWith(delaySeconds: 180)), '3 min de retard');
  });

  test('measures the callout over the selected vehicle to hold its text', () {
    final short = VehicleCallout.sizeOf(stop: 'Nation', when: '1 min');
    final long = VehicleCallout.sizeOf(stop: 'Nation', when: '1 min', delay: '3 min de retard');

    expect(long.width, greaterThan(short.width));
    expect(short.height, greaterThan(VehicleCallout.gap));
  });

  test('labels a vehicle with its next stop', () {
    expect(vehicleLabel(vehicle(toNext: const Duration(minutes: 2)), fetchedAt, TransportMode.metro),
        '→ Nation · Gare de Lyon dans 2 min');
    // At the stop: "à quai" on a platform, "à l'arrêt" for a bus
    expect(vehicleLabel(vehicle(toNext: Duration.zero), fetchedAt, TransportMode.rer), '→ Nation · Gare de Lyon à quai');
    expect(vehicleLabel(vehicle(toNext: Duration.zero), fetchedAt, TransportMode.bus), "→ Nation · Gare de Lyon à l'arrêt");
  });
}
