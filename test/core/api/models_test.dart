import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';

/// The models read the backend's JSON as it is sent (see website-back's controller/object/v2 records)
void main() {
  test('reads departures of a stop area, real time and scheduled', () {
    final departures = StopDepartures.fromJson({
      'stop': {'id': 'IDFM:70001', 'name': 'Châtelet', 'lat': 48.8584, 'lon': 2.347, 'distance': null, 'lines': []},
      'realtimeAvailable': true,
      'lines': [
        {
          'line': {'id': 'C01742', 'name': 'A', 'longName': 'RER A', 'mode': 'RER', 'color': 'EB2132', 'textColor': 'FFFFFF'},
          'destination': 'Fontenay-sous-Bois',
          'departures': [
            {
              'time': '2026-10-10T08:05:00Z',
              'aimedTime': '2026-10-10T08:03:00Z',
              'realtime': true,
              'status': 'delayed',
              'platform': 'A',
              'atStop': false,
              'mission': 'UPAC',
              'trainNumber': '154101',
            },
            {'time': '2026-10-10T08:20:00Z', 'aimedTime': '2026-10-10T08:20:00Z', 'realtime': false, 'status': null},
          ],
        },
      ],
    });

    final first = departures.lines.single.departures.first;
    expect(departures.lines.single.line.mode, TransportMode.rer);
    expect(first.time, DateTime.utc(2026, 10, 10, 8, 5));
    expect(first.delayed, isTrue);
    expect(first.cancelled, isFalse);
    expect(first.mission, 'UPAC');
    expect(departures.lines.single.departures.last.realtime, isFalse);
  });

  test('reads an unknown mode as a bus', () {
    expect(LineSummary.fromJson({'id': 'C1', 'mode': 'CABLE_CAR'}).mode, TransportMode.bus);
  });

  test('reads a journey with a line the GTFS does not know', () {
    // The backend builds such a line from Navitia's display, without id
    final plan = JourneyPlan.fromJson({
      'journeys': [
        {
          'type': 'best',
          'tags': ['walking'],
          'departure': '2026-10-10T08:00:00Z',
          'arrival': '2026-10-10T08:30:00Z',
          'duration': 1800,
          'transfers': 0,
          'walkingDuration': null,
          'fare': 215,
          'sections': [
            {
              'kind': 'TRANSIT',
              'departure': '2026-10-10T08:00:00Z',
              'arrival': '2026-10-10T08:30:00Z',
              'duration': 1800,
              'from': {'name': 'Châtelet', 'lat': 48.8584, 'lon': 2.347, 'stopAreaId': 'IDFM:70001'},
              'to': {'name': 'Ailleurs', 'lat': 48.9, 'lon': 2.4, 'stopAreaId': null},
              'line': {'id': null, 'name': '999', 'longName': 'Bus 999', 'mode': 'BUS', 'color': 'AAAAAA', 'textColor': null},
              'headsign': 'Ailleurs',
              'boardingPositions': [],
              'stops': [],
              'steps': [],
              'realtime': false,
              'delay': null,
              'length': null,
              'shape': [
                [2.347, 48.8584],
                [2.4, 48.9],
              ],
            },
            {'kind': 'TELEPORT', 'departure': '2026-10-10T08:30:00Z', 'arrival': '2026-10-10T08:30:00Z', 'duration': 0},
          ],
        },
      ],
      'earlier': {'datetime': '2026-10-10T07:59:00Z', 'arriveBy': true},
      'later': null,
    });

    final journey = plan.journeys.single;
    expect(journey.rides.single.line!.name, '999');
    expect(journey.rides.single.line!.id, isEmpty);
    expect(journey.sections.last.kind, SectionKind.other);
    expect(journey.fare, 215);
    expect(plan.earlier!.arriveBy, isTrue);
    expect(plan.later, isNull);
  });

  test('reads search results without lines for addresses', () {
    final result = SearchResult.fromJson({
      'lines': [],
      'places': [
        {'type': 'ADDRESS', 'id': '2.3418;48.8598', 'name': '10 Rue de Rivoli', 'lat': 48.8598, 'lon': 2.3418, 'lines': null},
        {'type': 'ADMINISTRATIVE_REGION', 'id': 'admin:1', 'name': 'Paris', 'lat': 48.85, 'lon': 2.35},
      ],
    });

    expect(result.places.first.lines, isEmpty);
    expect(result.places.last.type, PlaceType.poi);
  });

  test('reads rides with their arrival source', () {
    final rides = [
      for (final source in ['realtime', 'scheduled', 'typical', 'guessed', null])
        Ride.fromJson({
          'departure': {'time': '2026-10-10T08:00:00Z', 'realtime': true},
          'destination': 'Nation',
          'arrivalAt': source == null ? null : '2026-10-10T08:10:00Z',
          'arrivalSource': source,
        }),
    ];

    expect(rides.map((ride) => ride.arrivalSource),
        [ArrivalSource.realtime, ArrivalSource.scheduled, ArrivalSource.typical, null, null]);
    expect(rides.first.stops, isEmpty);
  });

  test('reads where a ride stops', () {
    // A direct train from Bécon-les-Bruyères to Saint-Lazare
    final ride = Ride.fromJson({
      'departure': {'time': '2026-10-10T08:11:10Z', 'aimedTime': '2026-10-10T08:11:10Z', 'realtime': true, 'trainNumber': '134512'},
      'destination': 'Gare Saint-Lazare',
      'arrivalAt': '2026-10-10T08:18:00Z',
      'arrivalSource': 'scheduled',
      'stops': [
        {'name': 'Bécon les Bruyères', 'lat': 48.9055, 'lon': 2.2688, 'time': '2026-10-10T08:11:10Z'},
        {'name': 'Gare Saint-Lazare', 'lat': 48.8775, 'lon': 2.3244, 'time': '2026-10-10T08:18:00Z'},
      ],
    });

    expect(ride.stops.map((stop) => stop.name), ['Bécon les Bruyères', 'Gare Saint-Lazare']);
    expect(ride.stops.last.time, DateTime.utc(2026, 10, 10, 8, 18));
  });

  test('reads vehicles, timetables, Vélib stations, the account and favorites', () {
    final vehicle = Vehicle.fromJson({
      'id': 'RERA-1',
      'name': 'UPAC',
      'destination': 'Fontenay-sous-Bois',
      'direction': 0,
      'branch': 0,
      'fromStopId': 'IDFM:70001',
      'toStopId': 'IDFM:70002',
      'toStopName': 'Gare de Lyon',
      'progress': 0.4,
      'expectedAt': '2026-10-10T08:01:00Z',
      'delaySeconds': 60,
      'calls': [
        {'stopId': 'IDFM:70002', 'stopName': 'Gare de Lyon', 'expectedAt': '2026-10-10T08:01:00Z', 'delaySeconds': 60, 'platform': 'A'},
      ],
    });
    expect(vehicle.calls.single.platform, 'A');
    expect(vehicle.stale, isFalse);
    expect(Vehicle.fromJson({...vehicle.toJson(), 'calls': [], 'stale': true}).stale, isTrue);

    final timetable = Timetable.fromJson({
      'stop': {'id': 'IDFM:70001', 'name': 'Châtelet', 'lat': 48.8584, 'lon': 2.347},
      'line': {'id': 'C01742', 'name': 'A', 'mode': 'RER'},
      'date': '2026-10-12',
      'directions': [
        {
          'name': 'Fontenay-sous-Bois / Joinville-le-Pont',
          'departures': [
            {'time': '2026-10-12T03:00:00Z', 'destination': 'Fontenay-sous-Bois', 'mission': null},
          ],
        },
      ],
    });
    expect(timetable.date, DateTime(2026, 10, 12));

    final station = BikeStation.fromJson({
      'id': '1',
      'code': '1001',
      'name': 'Châtelet - Rivoli',
      'lat': 48.859,
      'lon': 2.348,
      'capacity': 30,
      'mechanical': 5,
      'electric': 3,
      'docks': 10,
      'renting': true,
      'returning': true,
      'distance': 99,
      'reportedAt': '2026-10-10T08:00:00Z',
    });
    expect(station.bikes, 8);

    final account = Account.fromJson({'email': null, 'firstName': 'Ada', 'role': 'ROLE_USER', 'google': true, 'createdAt': '2026-10-10T08:00:00+02:00'});
    expect(account.google, isTrue);

    final favorite = Favorite.fromJson({
      'id': 3,
      'kind': 'STOP',
      'label': 'Châtelet',
      'lat': 48.8584,
      'lon': 2.347,
      'stopAreaId': 'IDFM:70001',
      'stop': {'id': 'IDFM:70001', 'name': 'Châtelet', 'lat': 48.8584, 'lon': 2.347, 'lines': []},
    });
    expect(favorite.kind, FavoriteKind.stop);
    expect(Favorite.fromJson(jsonDecode(jsonEncode(favorite.toJson())) as Map<String, dynamic>), favorite);
    expect(favorite.toJson()['stop'], isA<Map<String, dynamic>>());
  });

  test('reads disruptions and the traffic', () {
    final traffic = LineTraffic.fromJson({
      'line': {'id': 'C01371', 'name': '1', 'mode': 'METRO'},
      'severity': 'BLOCKING',
      'titles': ['Métro 1 : trafic interrompu'],
    });
    expect(traffic.severity, DisruptionSeverity.blocking);

    final disruption = Disruption.fromJson({
      'id': 'd1',
      'severity': 'UNKNOWN',
      'category': 'ELEVATOR',
      'title': 'Ascenseur',
      'message': null,
      'cause': null,
      'start': null,
      'end': null,
      'active': true,
      'updatedAt': null,
      'lineIds': [],
    });
    expect(disruption.severity, DisruptionSeverity.info);
    expect(disruption.category, DisruptionCategory.elevator);
    expect(disruption.sections, isEmpty);

    final works = Disruption.fromJson({
      'id': 'd2',
      'severity': 'DISRUPTED',
      'category': 'WORKS',
      'active': false,
      'lineIds': ['C01727'],
      'sections': [
        {'lineId': 'C01727', 'fromId': 'IDFM:63244', 'fromName': 'Massy - Palaiseau', 'toId': 'IDFM:69677', 'toName': 'Thiais - Orly'},
      ],
    });
    expect(works.sections.single.fromName, 'Massy - Palaiseau');
    expect(works.sections.single.toId, 'IDFM:69677');
  });
}
