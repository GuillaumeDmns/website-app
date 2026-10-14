import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/service_hours/service_hours.dart';
import 'package:website_app/l10n/l10n.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  // As the backend sends it (website-back's LineServiceHours / ServiceDirection / Frequency records)
  final hours = LineServiceHours.fromJson({
    'line': {'id': 'C01371', 'name': '1', 'longName': 'Métro 1', 'mode': 'METRO', 'color': 'FFCD00', 'textColor': '000000'},
    'date': '2026-10-14',
    'directions': [
      {
        'name': 'La Défense',
        'direction': 0,
        'at': {'id': 'IDFM:70003', 'name': 'Château de Vincennes', 'lat': 48.84, 'lon': 2.44},
        'first': '2026-10-14T03:30:00Z',
        'last': '2026-10-14T23:15:00Z',
        'frequencies': [
          {'period': 'EARLY_MORNING', 'start': '2026-10-14T03:30:00Z', 'end': '2026-10-14T05:00:00Z', 'departures': 12, 'minMinutes': 6, 'maxMinutes': 8},
          {'period': 'MORNING_PEAK', 'start': '2026-10-14T05:00:00Z', 'end': '2026-10-14T08:00:00Z', 'departures': 70, 'minMinutes': 2, 'maxMinutes': 3},
          {'period': 'EVENING', 'start': '2026-10-14T18:00:00Z', 'end': '2026-10-14T22:00:00Z', 'departures': 40, 'minMinutes': 6, 'maxMinutes': 6},
          {'period': 'NIGHT', 'start': '2026-10-14T22:00:00Z', 'end': '2026-10-14T23:15:00Z', 'departures': 1},
          {'period': 'SOMETIME', 'start': '2026-10-14T23:15:00Z', 'end': '2026-10-14T23:15:00Z', 'departures': 1, 'minMinutes': 65, 'maxMinutes': 90},
        ],
      },
    ],
  });
  final direction = hours.directions.single;

  test('reads the service hours of a line', () {
    expect(direction.direction, 0);
    expect(direction.at?.name, 'Château de Vincennes');
    expect(direction.frequencies.map((frequency) => frequency.period), [
      ServicePeriod.earlyMorning,
      ServicePeriod.morningPeak,
      ServicePeriod.evening,
      ServicePeriod.night,
      // Unknown periods read as daytime
      ServicePeriod.daytime,
    ]);
    expect(direction.frequencies[3].minMinutes, isNull);
  });

  test('tells how often a direction leaves', () {
    expect(frequencyLabel(direction.frequencies[0]), 'toutes les 6–8 min');
    expect(frequencyLabel(direction.frequencies[2]), 'toutes les 6 min');
    expect(frequencyLabel(direction.frequencies[3]), '1 départ');
    expect(frequencyLabel(direction.frequencies[4]), 'toutes les 1 h 05–1 h 30');
    expect(periodLabel(ServicePeriod.morningPeak), 'Pointe du matin');
  });

  test('tells what matters now: the frequency, the last departure soon, the service over or not started', () {
    expect(serviceStatus(direction, DateTime.utc(2026, 10, 14, 6)), (text: 'En ce moment toutes les 2–3 min', warning: false));
    expect(direction.frequencyAt(DateTime.utc(2026, 10, 14, 12)), isNull);
    expect(serviceStatus(direction, DateTime.utc(2026, 10, 14, 22, 30)), (text: 'Dernier départ dans 45 min', warning: true));
    expect(serviceStatus(direction, DateTime.utc(2026, 10, 14, 23, 20)), (text: "Plus de départ aujourd'hui", warning: true));
    expect(serviceStatus(direction, DateTime.utc(2026, 10, 14, 2)).text, startsWith('Premier départ à '));
  });
}
