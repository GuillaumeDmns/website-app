import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart' as samples;

void main() {
  setUp(() => useLocale(const Locale('fr')));

  group('JourneyPlace', () {
    test('parses the URL parameters', () {
      expect(JourneyPlace.parse('here', null)!.isCurrentLocation, isTrue);
      expect(JourneyPlace.parse('IDFM:70001', 'Châtelet')!.stopAreaId, 'IDFM:70001');
      final point = JourneyPlace.parse('48.86,2.34', null)!;
      expect((point.lat, point.lon), (48.86, 2.34));
      expect(point.name, currentL10n.pointOnMap);

      expect(JourneyPlace.parse(null, null), isNull);
      expect(JourneyPlace.parse('', null), isNull);
      expect(JourneyPlace.parse('Châtelet', null), isNull);
      expect(JourneyPlace.parse('48.86', null), isNull);
    });

    test('gives its URL parameter', () {
      expect(const JourneyPlace.currentLocation().param, 'here');
      expect(const JourneyPlace.stopArea(name: 'Châtelet', id: 'IDFM:70001').param, 'IDFM:70001');
      expect(const JourneyPlace.point(name: 'Rivoli', lat: 48.86, lon: 2.34).param, '48.860000,2.340000');
      expect(const JourneyPlace.currentLocation().name, 'Ma position');
    });

    test('is equal to the same place under another name', () {
      expect(const JourneyPlace.stopArea(name: 'Châtelet', id: 'IDFM:70001'),
          const JourneyPlace.stopArea(name: 'Chatelet (Paris)', id: 'IDFM:70001'));
    });
  });

  group('JourneyRequest', () {
    final request = JourneyRequest(
      from: const JourneyPlace.currentLocation(),
      to: const JourneyPlace.stopArea(name: 'Nation', id: 'IDFM:70003'),
      datetime: DateTime.utc(2026, 10, 10, 8, 30),
      arriveBy: true,
      modes: const {TransportMode.metro, TransportMode.rer},
      wheelchair: true,
      walkingSpeed: WalkingSpeed.slow,
      bikeShare: true,
    );

    test('goes through the URL and back', () {
      final query = request.toQuery();

      expect(query, {
        'from': 'here',
        'to': 'IDFM:70003',
        'toName': 'Nation',
        'at': '2026-10-10T08:30:00.000Z',
        'arriveBy': '1',
        'modes': 'METRO,RER',
        'wheelchair': '1',
        'walk': 'SLOW',
        'velib': '1',
      });
      expect(JourneyRequest.fromQuery(query), request);
      expect(request.optionCount, 4);
    });

    test('keeps the defaults out of the URL', () {
      const plain = JourneyRequest(from: JourneyPlace.currentLocation(), to: JourneyPlace.stopArea(name: 'Nation', id: 'IDFM:70003'));

      expect(plain.toQuery().keys, ['from', 'to', 'toName']);
      expect(plain.optionCount, 0);
      expect(plain.isComplete, isTrue);
      expect(const JourneyRequest(from: JourneyPlace.currentLocation()).isComplete, isFalse);
    });

    test('ignores unknown values', () {
      final parsed = JourneyRequest.fromQuery({'from': 'here', 'modes': 'METRO,PLANE', 'walk': 'RUN', 'at': 'yesterday'});

      expect(parsed.modes, {TransportMode.metro});
      expect(parsed.walkingSpeed, WalkingSpeed.normal);
      expect(parsed.datetime, isNull);
    });

    test('swaps start and end', () {
      final swapped = request.swapped();

      expect(swapped.from!.stopAreaId, 'IDFM:70003');
      expect(swapped.to!.isCurrentLocation, isTrue);
      expect(swapped.modes, request.modes);
    });

    test('replaces my location by the journey start when shared', () {
      final journey = samples.journey([samples.walk(DateTime.utc(2026, 10, 10, 8), 300)]);

      final shared = request.forSharing(journey);

      expect(shared.from!.isCurrentLocation, isFalse);
      expect(shared.from!.name, samples.address.name);
      expect(shared.to, request.to);
    });

    test('changes the time with copyWith', () {
      expect(request.copyWith(datetime: () => null).datetime, isNull);
      expect(request.copyWith(arriveBy: false).datetime, request.datetime);
    });
  });
}
