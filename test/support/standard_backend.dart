import 'package:website_app/core/api/models.dart';

import 'fake_backend.dart';
import 'samples.dart';

/// A [FakeBackend] answering the app's usual requests around Châtelet, times relative to now (like the backend's
/// integration tests: Châtelet, Gare de Lyon, Nation; métro 1, RER A, bus 38)
FakeBackend standardBackend() {
  final backend = FakeBackend();
  backend.get('/api/health', {'status': 'UP', 'version': '0.6.0'});
  DateTime inMinutes(int minutes) => DateTime.now().toUtc().add(Duration(minutes: minutes));

  StopDepartures chateletDepartures() => StopDepartures(
        stop: chatelet.copyWith(distance: 40),
        realtimeAvailable: true,
        lines: [
          LineDepartures(line: metro1, destination: 'Nation', departures: [
            departure(inMinutes(3), aimed: inMinutes(2)),
            departure(inMinutes(9)),
          ]),
          LineDepartures(line: rerA, destination: 'Fontenay-sous-Bois', departures: [
            departure(inMinutes(5), mission: 'UPAC', trainNumber: '154101').copyWith(platform: 'A'),
          ]),
          LineDepartures(line: bus38, destination: 'Gare de Lyon', departures: [
            departure(inMinutes(12), realtime: false),
          ]),
        ],
      );

  backend.post('/api/auth/guest', {'jwt': 'guest-token', 'expiresIn': 2592000});
  backend.post('/api/auth/google', {'jwt': 'google-access-token', 'refreshToken': 'google-refresh-token', 'expiresIn': 3600});
  backend.post('/api/token/refresh', {'jwt': 'access-token', 'refreshToken': 'next-refresh-token', 'expiresIn': 3600});

  backend.on('GET', '/api/v2/nearby/departures', (_) => FakeResponse([chateletDepartures().toJson()]));
  backend.on('GET', '/api/v2/nearby', (_) => FakeResponse([chatelet.copyWith(distance: 40).toJson(), gareDeLyon.copyWith(distance: 2400).toJson()]));
  backend.on('GET', '/api/v2/stops/IDFM:70001/departures', (_) => FakeResponse(chateletDepartures().toJson()));
  backend.get('/api/v2/stops/IDFM:70001', const StopAreaDetail(
    id: 'IDFM:70001',
    name: 'Châtelet',
    lat: 48.8584,
    lon: 2.3470,
    lines: [metro1, rerA, bus38],
    quays: [
      Quay(id: 'IDFM:1001', name: 'Châtelet', lat: 48.8585, lon: 2.3471, lineIds: ['C01371']),
      Quay(id: 'IDFM:1002', name: 'Châtelet', lat: 48.8585, lon: 2.3471, platformCode: 'A', lineIds: ['C01742']),
    ],
    connections: [Connection(id: 'IDFM:70007', name: 'Les Halles', minTransferSeconds: 240)],
  ).toJson());
  backend.get('/api/v2/stops/IDFM:70001/disruptions', [elevatorOutage.toJson()]);
  backend.get('/api/v2/lines/C01371', LineDetail(line: metro1, directions: [
    LineDirection(directionId: 0, branches: [
      LineBranch(headsign: 'Nation', tripCount: 120, stops: [
        for (final stop in [chatelet, gareDeLyon, nation]) StopRef(id: stop.id, name: stop.name, lat: stop.lat, lon: stop.lon),
      ]),
    ]),
    LineDirection(directionId: 1, branches: [
      LineBranch(headsign: 'Châtelet', tripCount: 120, stops: [
        for (final stop in [nation, gareDeLyon, chatelet]) StopRef(id: stop.id, name: stop.name, lat: stop.lat, lon: stop.lon),
      ]),
    ]),
  ]).toJson());
  backend.get('/api/v2/lines/C01371/vehicles', []);
  backend.get('/api/v2/lines/C01371/disruptions', [metroStopped.toJson()]);
  backend.get('/api/v2/traffic', [
    LineTraffic(line: metro1, severity: DisruptionSeverity.blocking, titles: [metroStopped.title!]).toJson(),
    const LineTraffic(line: rerA).toJson(),
    const LineTraffic(line: bus38, severity: DisruptionSeverity.disrupted, titles: ['Bus 38 : manifestation']).toJson(),
  ]);
  backend.on('GET', '/api/v2/search', (request) => FakeResponse(SearchResult(
        lines: '${request.queryParameters['q']}'.toLowerCase() == '1' ? [metro1] : [],
        places: [
          PlaceResult(type: PlaceType.stopArea, id: chatelet.id, name: 'Châtelet (Paris)', lat: chatelet.lat, lon: chatelet.lon, lines: chatelet.lines),
          const PlaceResult(type: PlaceType.address, id: '2.3418;48.8598', name: '10 Rue de Rivoli (Paris)', lat: 48.8598, lon: 2.3418),
        ],
      ).toJson()));
  backend.on('GET', '/api/v2/journeys', (_) {
    final start = inMinutes(2);
    final metro = transit(start.add(const Duration(minutes: 5)), 480, to: gareDeLyon);
    return FakeResponse(JourneyPlan(journeys: [
      journey([walk(start, 300), metro]).copyWith(type: 'best', fare: 215),
      journey([walk(start, 240), transit(start.add(const Duration(minutes: 4)), 600, line: rerA, to: gareDeLyon)]).copyWith(type: 'rapid'),
    ]).toJson());
  });
  backend.on('GET', '/api/v2/lines/*/rides', (_) => FakeResponse([
        for (final minutes in [7, 12, 17]) ride(inMinutes(minutes)).toJson(),
      ]));
  // The last ride tonight in 40 min, the first tomorrow morning
  backend.on('GET', '/api/v2/lines/*/rides/span', (_) => FakeResponse(RideSpan(
        first: ScheduledRide(departure: inMinutes(-600), arrival: inMinutes(-592)),
        last: ScheduledRide(departure: inMinutes(40), arrival: inMinutes(48)),
        next: ScheduledRide(departure: inMinutes(400), arrival: inMinutes(408)),
      ).toJson()));
  backend.get('/api/v2/bikes/nearby', [
    const BikeStation(id: '1', name: 'Châtelet - Rivoli', lat: 48.8590, lon: 2.3480, capacity: 30, mechanical: 5, electric: 3, docks: 10, distance: 99)
        .toJson(),
  ]);
  backend.get('/api/v2/bikes/stations', []);
  backend.get('/api/v2/me/favorites', []);
  backend.get('/api/v2/me', const Account(email: 'ada@example.com', firstName: 'Ada', role: 'ROLE_USER', google: true).toJson());
  return backend;
}

const metroStopped = Disruption(
  id: 'metro-1-stopped',
  severity: DisruptionSeverity.blocking,
  category: DisruptionCategory.traffic,
  title: 'Métro 1 : trafic interrompu',
  message: 'Trafic interrompu entre Châtelet et Nation.',
  active: true,
  lineIds: ['C01371'],
  sections: [DisruptionSection(lineId: 'C01371', fromId: 'IDFM:70001', fromName: 'Châtelet', toId: 'IDFM:70003', toName: 'Nation')],
);

const elevatorOutage = Disruption(
  id: 'chatelet-elevator',
  severity: DisruptionSeverity.info,
  category: DisruptionCategory.elevator,
  title: 'Ascenseur hors service : Ligne M1 direction Nation',
  message: 'Niveau 0 : sortie 2, rue de Rivoli',
  active: true,
);
