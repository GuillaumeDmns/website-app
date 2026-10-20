import 'package:flutter/material.dart';
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

  group('BranchPath', () {
    const branch = LineBranch(headsign: 'Nation', tripCount: 10, stops: [
      StopRef(id: 'IDFM:1', name: 'Châtelet', lat: 48.8584, lon: 2.3470),
      StopRef(id: 'IDFM:2', name: 'Gare de Lyon', lat: 48.8443, lon: 2.3730),
      StopRef(id: 'IDFM:3', name: 'Nation', lat: 48.8484, lon: 2.3959),
    ]);
    final path = BranchPath(branch);

    test('places a vehicle between its stops', () {
      final halfway = path.position(vehicle(), 0.5)!;

      expect(halfway.latitude, closeTo((48.8584 + 48.8443) / 2, 0.0005));
      expect(path.position(vehicle(), 1)!.latitude, closeTo(48.8443, 0.0001));
    });

    test('places a vehicle waiting at the first stop on it', () {
      expect(path.position(vehicle(from: null, to: 'IDFM:1'), 1)!.latitude, closeTo(48.8584, 0.0001));
    });

    test('takes the previous stop when the one left is not on the branch', () {
      expect(path.position(vehicle(from: 'IDFM:9', to: 'IDFM:3'), 0)!.latitude, closeTo(48.8443, 0.0001));
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
      expect(path.position(vehicle(to: 'IDFM:99'), 0.5), isNull);
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

  group('stopListPositions', () {
    // A branch from W merging at M with another one from N
    const branch = LineBranch(headsign: 'Paris', tripCount: 10, stops: [
      StopRef(id: 'W1', name: 'W1', lat: 48.80, lon: 2.20),
      StopRef(id: 'W2', name: 'W2', lat: 48.81, lon: 2.21),
      StopRef(id: 'M', name: 'M', lat: 48.82, lon: 2.22),
      StopRef(id: 'P', name: 'Paris', lat: 48.83, lon: 2.23),
    ]);

    test('places a vehicle between the stop it left and the next one', () {
      final positions = stopListPositions(branch, [(vehicle: vehicle(from: 'W2', to: 'M'), progress: 0.75)]);

      expect(positions.keys, [2]);
      expect(positions[2]!.single.offset, closeTo(-0.25, 0.001));
    });

    test('spreads a direct train over the stops it skips', () {
      // Left W1 for M, skipping W2: halfway is at W2
      final positions = stopListPositions(branch, [(vehicle: vehicle(from: 'W1', to: 'M'), progress: 0.5)]);

      expect(positions.keys, [1]);
      expect(positions[1]!.single.offset, closeTo(0, 0.001));
    });

    test('leaves out a vehicle coming from another branch until it runs on this one', () {
      final coming = vehicle(from: 'N2', to: 'M');
      final merged = vehicle(from: 'M', to: 'P');

      expect(stopListPositions(branch, [(vehicle: coming, progress: 0.5)]), isEmpty);
      expect(stopListPositions(branch, [(vehicle: merged, progress: 0.5)]).values.single.single.vehicle, merged);
    });

    test('places a vehicle waiting at its first stop on it', () {
      final positions = stopListPositions(branch, [(vehicle: vehicle(from: null, to: 'M'), progress: 1)]);

      expect(positions.keys, [2]);
    });
  });

  test('tells how on time a vehicle is', () {
    expect(Punctuality.of(vehicle()), Punctuality.unknown);
    expect(Punctuality.of(vehicle().copyWith(delaySeconds: 30)), Punctuality.onTime);
    expect(Punctuality.of(vehicle().copyWith(delaySeconds: -90)), Punctuality.onTime);
    expect(Punctuality.of(vehicle().copyWith(delaySeconds: 60)), Punctuality.late);
  });

  testWidgets('fades a stale vehicle and points it the way it goes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Row(children: [
        VehicleMarker(line: metro1, heading: 90, punctuality: Punctuality.late),
        VehicleMarker(line: metro1, stale: true),
      ]),
    ));

    expect(tester.getSize(find.byType(VehicleMarker).first), Size.square(VehicleMarker.boxSize(22)));
    expect(find.descendant(of: find.byType(VehicleMarker).first, matching: find.byType(Transform)), findsWidgets);
    expect(find.descendant(of: find.byType(VehicleMarker).last, matching: find.byType(Opacity)), findsOneWidget);
    expect(find.descendant(of: find.byType(VehicleMarker).first, matching: find.byType(Opacity)), findsNothing);
  });

  test('labels a vehicle with its next stop', () {
    expect(vehicleLabel(vehicle(toNext: const Duration(minutes: 2)), fetchedAt), '→ Nation · Gare de Lyon dans 2 min');
    expect(vehicleLabel(vehicle(toNext: Duration.zero), fetchedAt), startsWith('→ Nation · Gare de Lyon'));
  });
}
