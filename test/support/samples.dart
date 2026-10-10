import 'package:website_app/core/api/models.dart';

/// Models as the backend sends them, for the tests. Times are UTC like the API's.

const metro1 = LineSummary(id: 'C01371', name: '1', longName: 'Métro 1', mode: TransportMode.metro, color: 'FFCD00', textColor: '000000');
const rerA = LineSummary(id: 'C01742', name: 'A', longName: 'RER A', mode: TransportMode.rer, color: 'EB2132', textColor: 'FFFFFF');
const bus38 = LineSummary(id: 'C02000', name: '38', longName: 'Bus 38', mode: TransportMode.bus, color: '82C8E6', textColor: '000000');

const chatelet = StopAreaSummary(id: 'IDFM:70001', name: 'Châtelet', lat: 48.8584, lon: 2.3470, lines: [metro1, rerA, bus38]);
const gareDeLyon = StopAreaSummary(id: 'IDFM:70002', name: 'Gare de Lyon', lat: 48.8443, lon: 2.3730, lines: [metro1, rerA]);
const nation = StopAreaSummary(id: 'IDFM:70003', name: 'Nation', lat: 48.8484, lon: 2.3959, lines: [metro1, rerA]);

JourneyPoint point(StopAreaSummary stop) => JourneyPoint(name: stop.name, lat: stop.lat, lon: stop.lon, stopAreaId: stop.id);

const address = JourneyPoint(name: '10 Rue de Rivoli', lat: 48.8600, lon: 2.3400);

Departure departure(DateTime time, {DateTime? aimed, bool realtime = true, String? status, String? trainNumber, String? mission}) =>
    Departure(time: time, aimedTime: aimed ?? time, realtime: realtime, status: status, trainNumber: trainNumber, mission: mission);

Ride ride(DateTime time, {DateTime? aimed, Duration ride = const Duration(minutes: 8), String? trainNumber, String? status}) => Ride(
      departure: departure(time, aimed: aimed, trainNumber: trainNumber, status: status),
      destination: 'Nation',
      arrivalAt: time.add(ride),
      arrivalSource: ArrivalSource.realtime,
    );

JourneySection walk(DateTime departure, int seconds, {JourneyPoint from = address, JourneyPoint? to}) => JourneySection(
      kind: SectionKind.walk,
      departure: departure,
      arrival: departure.add(Duration(seconds: seconds)),
      duration: seconds,
      from: from,
      to: to ?? point(chatelet),
      length: (seconds * 1.2).round(),
    );

JourneySection wait(DateTime departure, int seconds) => JourneySection(
      kind: SectionKind.wait,
      departure: departure,
      arrival: departure.add(Duration(seconds: seconds)),
      duration: seconds,
    );

JourneySection transit(DateTime departure, int seconds,
        {LineSummary line = metro1, StopAreaSummary from = chatelet, StopAreaSummary to = nation, List<StopAreaSummary>? via}) {
  final served = [from, ...?via, to];
  return JourneySection(
    kind: SectionKind.transit,
    departure: departure,
    arrival: departure.add(Duration(seconds: seconds)),
    duration: seconds,
    from: point(from),
    to: point(to),
    line: line,
    headsign: to.name,
    stops: [
      for (final (index, stop) in served.indexed)
        JourneyStop(
          name: stop.name,
          lat: stop.lat,
          lon: stop.lon,
          time: departure.add(Duration(seconds: seconds * index ~/ (served.length - 1))),
        ),
    ],
    shape: [for (final stop in served) [stop.lon, stop.lat]],
  );
}

JourneyOption journey(List<JourneySection> sections) => JourneyOption(
      type: 'best',
      departure: sections.first.departure,
      arrival: sections.last.arrival,
      duration: sections.last.arrival.difference(sections.first.departure).inSeconds,
      sections: sections,
    );
