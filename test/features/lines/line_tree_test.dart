import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/lines/line_screen.dart';
import 'package:website_app/features/lines/line_tree.dart';
import 'package:website_app/features/lines/line_vehicles.dart';
import 'package:website_app/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

StopRef stop(String id) => StopRef(id: id, name: id, lat: 48.8, lon: 2.3);

LineBranch branch(String headsign, int trips, List<String> stops) =>
    LineBranch(headsign: headsign, tripCount: trips, stops: [for (final id in stops) stop(id)]);

void main() {
  setUp(() => useLocale(const Locale('fr')));

  // Like the RER B going north: branches at both ends (Saint-Rémy or Robinson, CDG or Mitry)
  final north = [
    branch('CDG', 1000, ['StRemy', 'Massy', 'BourgLaReine', 'Chatelet', 'Aulnay', 'Sevran', 'CDG']),
    branch('Mitry', 350, ['Robinson', 'Sceaux', 'BourgLaReine', 'Chatelet', 'Aulnay', 'Vert', 'Mitry']),
    branch('CDG', 300, ['Robinson', 'Sceaux', 'BourgLaReine', 'Chatelet', 'Aulnay', 'Sevran', 'CDG']),
    branch('Mitry', 290, ['StRemy', 'Massy', 'BourgLaReine', 'Chatelet', 'Aulnay', 'Vert', 'Mitry']),
  ];

  group('lineTree', () {
    test('lists the busiest branch as the trunk, the others as branches where they leave or join it', () {
      final trunk = lineTree(north);

      expect(trunk.stops.map((stop) => stop.id), ['StRemy', 'Massy', 'BourgLaReine', 'Chatelet', 'Aulnay', 'Sevran', 'CDG']);
      expect(trunk.spurs, hasLength(2));
      final robinson = trunk.spurs.firstWhere((spur) => spur.merges);
      expect(robinson.attach.id, 'BourgLaReine');
      expect(robinson.stops.map((stop) => stop.id), ['Robinson', 'Sceaux']);
      expect(robinson.end.id, 'Robinson');
      final mitry = trunk.spurs.firstWhere((spur) => !spur.merges);
      expect(mitry.attach.id, 'Aulnay');
      expect(mitry.stops.map((stop) => stop.id), ['Vert', 'Mitry']);
      expect(mitry.end.id, 'Mitry');
      expect(treeDepth(trunk), 1);
    });

    test('hangs a branch off another branch when it leaves it', () {
      final trunk = lineTree([
        branch('Paris', 300, ['Mantes', 'Plaisir', 'StCyr', 'Paris']),
        branch('Paris', 200, ['Rambouillet', 'Trappes', 'StCyr', 'Paris']),
        branch('Paris', 100, ['Dreux', 'Houdan', 'Trappes', 'StCyr', 'Paris']),
      ]);

      final rambouillet = trunk.spurs.single;
      expect(rambouillet.stops.map((stop) => stop.id), ['Rambouillet', 'Trappes']);
      final dreux = rambouillet.spurs.single;
      expect((dreux.attach.id, dreux.merges), ('Trappes', true));
      expect(dreux.stops.map((stop) => stop.id), ['Dreux', 'Houdan']);
      expect(rambouillet.stopCount, 4);
      expect(treeDepth(trunk), 2);
    });

    test('keeps a line without branches as its trunk alone', () {
      final trunk = lineTree([branch('Nation', 100, ['A', 'B', 'C'])]);

      expect(trunk.stops, hasLength(3));
      expect(trunk.spurs, isEmpty);
    });
  });

  group('both ways', () {
    // A bus going A → E by B, coming back E → A by Y and X instead of C and B
    final going = branch('E', 100, ['A', 'B', 'C', 'D', 'E']);
    final back = branch('A', 100, ['E', 'D', 'Y', 'X', 'A']);
    final trunk = lineTree([going], otherWay: [back]);

    test('lists the stops only the other direction serves, where it leaves and rejoins the listed ones', () {
      final other = trunk.spurs.single;
      expect(other.otherWay, isTrue);
      // Read against its direction: from A, X then Y, back at D
      expect((other.attach.id, other.merges, other.rejoin?.id), ('A', false, 'D'));
      expect(other.stops.map((stop) => stop.id), ['X', 'Y']);
      expect(other.sequence, ['A', 'X', 'Y', 'D']);
    });

    test('places the other direction\'s vehicles on its own stops, running up the list', () {
      Vehicle coming(String from, String to) => Vehicle(
            id: '$from-$to',
            direction: 1,
            branch: 0,
            fromStopId: from,
            toStopId: to,
            progress: 0.5,
            expectedAt: DateTime.utc(2026, 11, 21, 12),
          );
      final placed = treeVehicles(trunk, [
        (vehicle: coming('D', 'Y'), progress: 0.5),
        (vehicle: coming('X', 'A'), progress: 0.5),
      ]);

      final other = trunk.spurs.single;
      expect(placed.map((placement) => (placement.node, placement.gap, placement.reverse)), [
        (other, 0, true),
        (other, 2, true),
      ]);
    });

    test('adds nothing for a direction serving the same stops back', () {
      expect(lineTree([going], otherWay: [branch('A', 100, ['E', 'D', 'C', 'B', 'A'])]).spurs, isEmpty);
    });
  });

  group('treeVehicles', () {
    final trunk = lineTree(north);
    Vehicle vehicle(String id, {String? from, required String to, int direction = 0}) => Vehicle(
          id: id,
          direction: direction,
          branch: 0,
          fromStopId: from,
          toStopId: to,
          progress: 0.5,
          expectedAt: DateTime.utc(2026, 11, 21, 12),
        );

    test('places a vehicle between two stops of the trunk, or of a branch', () {
      final placed = treeVehicles(trunk, [
        (vehicle: vehicle('trunk', from: 'Massy', to: 'BourgLaReine'), progress: 0.5),
        (vehicle: vehicle('mitry', from: 'Vert', to: 'Mitry'), progress: 0.5),
        // Leaving the trunk for its branch: in the branch, before its first stop
        (vehicle: vehicle('leaving', from: 'Aulnay', to: 'Vert'), progress: 0.5),
      ]);

      final byId = {for (final placement in placed) placement.vehicle.id: placement};
      expect((byId['trunk']!.node, byId['trunk']!.gap, byId['trunk']!.reverse), (trunk, 1, false));
      final mitry = trunk.spurs.firstWhere((spur) => !spur.merges);
      expect((byId['mitry']!.node, byId['mitry']!.gap), (mitry, 1));
      expect((byId['leaving']!.node, byId['leaving']!.gap), (mitry, 0));
    });

    test('places a vehicle standing at the stop a branch joins on the trunk', () {
      final placed = treeVehicles(trunk, [(vehicle: vehicle('standing', from: 'Sceaux', to: 'BourgLaReine'), progress: 1)]);

      expect((placed.single.node, placed.single.stop), (trunk, 2));
    });

    test('turns a vehicle standing at a stop the way it goes', () {
      final placed = treeVehicles(trunk, [
        (vehicle: vehicle('down', from: 'Massy', to: 'BourgLaReine'), progress: 1),
        (vehicle: vehicle('up', from: 'Chatelet', to: 'BourgLaReine', direction: 1), progress: 1),
      ]);

      expect({for (final placement in placed) placement.vehicle.id: placement.reverse}, {'down': false, 'up': true});
    });

    test('turns a vehicle standing at its first stop by its next one', () {
      final next = [VehicleCall(stopId: 'Massy', expectedAt: DateTime.utc(2026, 11, 21, 12, 5))];
      final placed = treeVehicles(trunk, [
        (vehicle: vehicle('first', to: 'BourgLaReine', direction: 1).copyWith(calls: next), progress: 1),
      ]);

      expect((placed.single.stop, placed.single.reverse), (2, true));
    });

    test('runs the other direction up the list', () {
      final placed = treeVehicles(trunk, [(vehicle: vehicle('south', from: 'Chatelet', to: 'BourgLaReine', direction: 1), progress: 0.25)]);

      expect((placed.single.gap, placed.single.reverse), (2, true));
    });
  });

  group('a train not stopping everywhere', () {
    // A, B, C close together, then D 8 km further: uneven, like a suburb's stations then the run into Paris
    StopRef at(String id, double km) => StopRef(id: id, name: id, lat: 48.8, lon: 2.0 + km * 0.013662);
    final stopping = LineBranch(headsign: 'D', tripCount: 100, stops: [at('A', 0), at('B', 1), at('C', 2), at('D', 10)]);
    final direct = LineBranch(headsign: 'D', tripCount: 50, stops: [at('A', 0), at('D', 10)]);
    final trunk = lineTree([stopping, direct]);
    final train = Vehicle(
      id: 'direct',
      direction: 0,
      branch: 1,
      fromStopId: 'A',
      toStopId: 'D',
      progress: 0.5,
      expectedAt: DateTime.utc(2026, 11, 21, 12),
    );

    test('is listed among the stops it runs past where it is on its path, as on the map', () {
      // Halfway in time through A → D is 5 km on: past C already (by stop count it would be between B and C)
      final placed = treeVehicles(trunk, [(vehicle: train, progress: 0.5)], pathOf: (_) => BranchPath(direct)).single;

      expect(placed.direct, isTrue);
      expect(placed.gap, 2);
      expect(placed.position, closeTo(2.375, 0.05));
    });

    test('goes by its time through them without its path', () {
      final placed = treeVehicles(trunk, [(vehicle: train, progress: 0.5)]).single;

      expect((placed.direct, placed.gap), (true, 1));
    });

    test('is not direct between two stops next to each other', () {
      final placed = treeVehicles(trunk, [(vehicle: train.copyWith(fromStopId: 'C', branch: 0), progress: 0.5)]).single;

      expect(placed.direct, isFalse);
    });
  });

  test('names a direction after its termini', () {
    expect(directionLabel(LineDirection(directionId: 0, branches: north)), 'Vers CDG / Mitry');
    expect(
      directionLabel(LineDirection(directionId: 1, branches: [
        branch('Mantes', 300, ['P', 'M']),
        branch('Rambouillet', 290, ['P', 'R']),
        branch('Dreux', 160, ['P', 'D']),
      ])),
      'Vers Mantes +2',
    );
    expect(destinationsOf(LineDirection(directionId: 0, branches: north)), ['CDG', 'Mitry']);
  });
}
