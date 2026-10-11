import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/lines/line_vehicles.dart';
import 'package:website_app/l10n/l10n.dart';

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

    test('ignores vehicles of another branch', () {
      expect(path.position(vehicle(to: 'IDFM:99'), 0.5), isNull);
    });
  });

  test('labels a vehicle with its next stop', () {
    expect(vehicleLabel(vehicle(toNext: const Duration(minutes: 2)), fetchedAt), '→ Nation · Gare de Lyon dans 2 min');
    expect(vehicleLabel(vehicle(toNext: Duration.zero), fetchedAt), startsWith('→ Nation · Gare de Lyon'));
  });
}
