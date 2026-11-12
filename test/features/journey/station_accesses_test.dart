import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/journey/station_accesses.dart';

import '../../support/samples.dart';

void main() {
  final start = DateTime.utc(2026, 10, 10, 8, 0);

  // Châtelet: one way in on the way from Rue de Rivoli, one past the station
  const chateletWest = StationEntrance(id: 'chatelet-west', code: '1', name: 'r. de Rivoli', lat: 48.8590, lon: 2.3455);
  const chateletEast = StationEntrance(id: 'chatelet-east', code: '9', name: 'pl. du Châtelet', lat: 48.8575, lon: 2.3490);
  // Nation: one way out behind the station, one on the walk east
  const nationBehind = StationEntrance(id: 'nation-behind', code: '2', name: 'av. du Trône', lat: 48.8484, lon: 2.3950);
  const nationOnTheWay = StationEntrance(id: 'nation-way', code: '6', name: 'bd Voltaire', lat: 48.8486, lon: 2.3968);
  const entrances = {
    'IDFM:70001': [chateletWest, chateletEast],
    'IDFM:70003': [nationBehind, nationOnTheWay],
  };

  JourneySection walkTo(List<StationEntrance> accesses) => walk(start, 300).copyWith(
        shape: const [[2.3400, 48.8600], [2.3470, 48.8584]],
        accesses: accesses,
      );

  JourneySection walkFromNation(List<StationEntrance> accesses) => walk(start.add(const Duration(minutes: 20)), 300, from: point(nation)).copyWith(
        to: address,
        shape: const [[2.3959, 48.8484], [2.4013, 48.8484]],
        accesses: accesses,
      );

  test("the metro and train stations a journey walks into or out of, not its bus stops nor its transfers", () {
    final trip = journey([
      walkTo(const []),
      transit(start.add(const Duration(minutes: 5)), 600),
      walkFromNation(const []),
    ]);
    expect(journeyStationIds(trip), {'IDFM:70001', 'IDFM:70003'});

    // From the metro to a bus at Nation: never through its ways in and out
    final toBus = journey([
      walkTo(const []),
      transit(start.add(const Duration(minutes: 5)), 600),
      transit(start.add(const Duration(minutes: 16)), 600, line: bus38, from: nation, to: gareDeLyon),
    ]);
    expect(journeyStationIds(toBus), {'IDFM:70001'});
  });

  test("the ways a journey takes: Navitia's, else the best guess; in at the start, out at the end", () {
    // Navitia's path goes in by the east entrance and out behind the station (another station's access in passing)
    const elsewhere = StationEntrance(id: 'elsewhere', name: 'Ailleurs', lat: 48.85, lon: 2.35);
    final navitia = journey([
      walkTo(const [elsewhere, chateletEast]),
      wait(start.add(const Duration(minutes: 5)), 60),
      transit(start.add(const Duration(minutes: 6)), 600),
      walkFromNation(const [nationBehind]),
    ]);
    final stations = {for (final station in journeyStationAccesses(navitia, entrances)) station.stopAreaId: station};

    expect(stations['IDFM:70001']!.taken, {'chatelet-east': false});
    expect(stations['IDFM:70001']!.exit, isFalse);
    expect(stations['IDFM:70001']!.entrances, [chateletWest, chateletEast]);
    expect(stations['IDFM:70003']!.taken, {'nation-behind': true});
    expect(stations['IDFM:70003']!.exit, isTrue);

    // Without Navitia's accesses: the one reached first on the way in, the one leaving the least to walk on the way out
    final guessed = journey([walkTo(const []), transit(start.add(const Duration(minutes: 5)), 600), walkFromNation(const [])]);
    final guesses = {for (final station in journeyStationAccesses(guessed, entrances)) station.stopAreaId: station.taken};
    expect(guesses, {'IDFM:70001': {'chatelet-west': false}, 'IDFM:70003': {'nation-way': true}});
  });

  test('the stations of a transfer within them are left out, as a station whose page is not there yet', () {
    final trip = journey([
      walkTo(const [chateletEast]),
      transit(start.add(const Duration(minutes: 5)), 600),
      JourneySection(kind: SectionKind.transfer, departure: start.add(const Duration(minutes: 15)), arrival: start.add(const Duration(minutes: 18)), duration: 180),
      transit(start.add(const Duration(minutes: 18)), 300, line: rerA, from: nation, to: gareDeLyon),
    ]);
    final stations = {for (final station in journeyStationAccesses(trip, entrances)) station.stopAreaId: station};

    // Nation: changing from the metro to the RER within the station, its ways in and out of no use
    expect(stations.keys, ['IDFM:70001']);
    expect(journeyStationIds(trip), {'IDFM:70001'});
  });
}
