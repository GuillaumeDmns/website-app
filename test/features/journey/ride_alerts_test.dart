import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/journey/widgets/ride_alerts.dart';

const _metro1 = 'C01371';

Disruption _disruption(String title,
        {DisruptionSeverity severity = DisruptionSeverity.disrupted,
        DisruptionCategory category = DisruptionCategory.traffic,
        bool active = true,
        List<String> lineIds = const []}) =>
    Disruption(id: title, severity: severity, category: category, title: title, message: '$title.', active: active, lineIds: lineIds);

void main() {
  final interrupted = _disruption('Métro 1 : trafic interrompu', severity: DisruptionSeverity.blocking, lineIds: [_metro1]);
  final information = _disruption('Métro 1 : travaux cet été', severity: DisruptionSeverity.info, lineIds: [_metro1]);
  final upcoming = _disruption('Métro 1 : grève jeudi', active: false, lineIds: [_metro1]);
  // Impacts on stop points: listed with the line and with the stop
  final chateletClosed = _disruption('Métro 1 : station Châtelet fermée', severity: DisruptionSeverity.blocking);
  final concordeClosed = _disruption('Métro 1 : station Concorde fermée', severity: DisruptionSeverity.blocking);
  final busStop = _disruption('Bus 38 : arrêt Châtelet non desservi', severity: DisruptionSeverity.blocking);
  final rerA = _disruption('RER A : trafic perturbé', lineIds: ['C01742']);
  final elevator = _disruption('Ascenseur hors service', severity: DisruptionSeverity.info, category: DisruptionCategory.elevator);

  test("the line's own disruptions, information and upcoming ones left out", () {
    final alerts = rideAlerts(lineId: _metro1, line: [interrupted, information, upcoming], stops: const []);

    expect(alerts.line, [interrupted]);
    expect(alerts.severity, DisruptionSeverity.blocking);
    expect(rideAlerts(lineId: _metro1, line: [information, upcoming], stops: const []).isEmpty, isTrue);
  });

  test("at its two stops, the line's disruptions there and their elevators: not another line's, nor a stop only passed", () {
    final alerts = rideAlerts(
      lineId: _metro1,
      // The line's page lists its closed stations too
      line: [interrupted, chateletClosed, concordeClosed],
      stops: [
        // Châtelet's: its buses', its main lines' (the métro 1 again, the RER A), its elevators
        (name: 'Châtelet', disruptions: [busStop, chateletClosed, interrupted, rerA, elevator]),
        (name: 'Gare de Lyon', disruptions: [interrupted]),
      ],
    );

    expect(alerts.line, [interrupted]);
    expect(alerts.stops.map((stop) => stop.name), ['Châtelet', 'Gare de Lyon']);
    expect(alerts.stops.first.disruptions, [chateletClosed]);
    expect(alerts.stops.first.elevators, [elevator]);
    expect(alerts.stops.last.isEmpty, isTrue);
    expect(alerts.elevatorCount, 1);
  });

  test('the same text kept under other ids by the two lists is the same disruption, one about both stops said at the first', () {
    final bothStops = _disruption('Métro 1 : Châtelet et Gare de Lyon non desservies', severity: DisruptionSeverity.blocking);
    final alerts = rideAlerts(
      lineId: _metro1,
      line: [bothStops],
      stops: [
        (name: 'Châtelet', disruptions: [bothStops.copyWith(id: 'impact-chatelet')]),
        (name: 'Gare de Lyon', disruptions: [bothStops.copyWith(id: 'impact-gare-de-lyon')]),
      ],
    );

    expect(alerts.stops.first.disruptions.single.title, bothStops.title);
    expect(alerts.stops.last.isEmpty, isTrue);
  });

  test('elevators out of order alone: no severity, still something to show', () {
    final alerts = rideAlerts(lineId: _metro1, line: const [], stops: [
      (name: 'Châtelet', disruptions: [elevator, elevator.copyWith(id: 'second', title: 'Ascenseur sortie 2')]),
    ]);

    expect(alerts.isEmpty, isFalse);
    expect(alerts.severity, isNull);
    expect(alerts.elevatorCount, 2);
    expect(rideAlerts(lineId: _metro1, line: const [], stops: [(name: 'Châtelet', disruptions: [busStop])]).isEmpty, isTrue);
  });
}
