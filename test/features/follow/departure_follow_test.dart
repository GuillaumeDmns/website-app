import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/location/position_feed.dart';
import 'package:website_app/core/platform/live_journey.dart';
import 'package:website_app/features/follow/departure_follow.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/fake_backend.dart';
import '../../support/fake_live_journey.dart';
import '../../support/samples.dart';
import '../../support/test_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => useLocale(const Locale('fr')));

  DateTime inMinutes(int minutes) => DateTime.now().toUtc().add(Duration(minutes: minutes));

  group('the followed departure among the stop\'s', () {
    final start = DateTime.utc(2026, 11, 16, 8, 0);
    DateTime at(int minutes) => start.add(Duration(minutes: minutes));

    test('a train by its number, whatever its delay', () {
      final followed = departure(at(5), trainNumber: '154101');
      final late = departure(at(12), aimed: at(5), trainNumber: '154101');
      expect(findFollowed([departure(at(6), trainNumber: '154103'), late], followed), late);
    });

    test('else by its planned time: a delay moves the expected one only', () {
      final followed = departure(at(5));
      final late = departure(at(9), aimed: at(5));
      expect(findFollowed([departure(at(8)), late], followed), late);
    });

    test('a metro without planned time: the closest expected time; none once it left', () {
      final noAimed = Departure(time: at(0), realtime: true);
      final followed = noAimed.copyWith(time: at(5));
      final same = noAimed.copyWith(time: at(6));
      expect(findFollowed([same, noAimed.copyWith(time: at(10))], followed), same);
      expect(findFollowed([noAimed.copyWith(time: at(10))], followed), isNull);
    });
  });

  FollowedDeparture followedTrain(Departure departure) =>
      FollowedDeparture(stopAreaId: chatelet.id, stopName: chatelet.name, line: rerA, destination: 'Fontenay-sous-Bois', departure: departure);

  test('the notification says the line and destination, then where and what the real time says', () {
    final time = DateTime.utc(2026, 11, 16, 8, 5);
    final onTime = departureLive(followedTrain(departure(time, trainNumber: '1').copyWith(platform: 'A')));
    expect(onTime.title, 'RER A · Fontenay-sous-Bois');
    expect(onTime.status, startsWith('${currentL10n.followLeavesAt(_clock(time))} · Châtelet · voie A'));
    expect(onTime.departureAt, time);
    expect(onTime.mode, 'train');
    expect(onTime.tone, LiveJourneyTone.fine);

    final late = departureLive(followedTrain(departure(time.add(const Duration(minutes: 4)), aimed: time)));
    expect(late.status, contains(currentL10n.goMinutesLate(4)));
    expect(late.tone, LiveJourneyTone.caution);

    final cancelled = departureLive(followedTrain(departure(time, status: 'cancelled')));
    expect(cancelled.cancelled, isTrue);
    expect(cancelled.status, startsWith(currentL10n.departureCancelled));
    expect(cancelled.tone, LiveJourneyTone.danger);
  });

  group('following', () {
    late FakeBackend backend;
    late FakeLiveJourney live;
    late ProviderContainer container;
    late List<Departure> trains;

    setUp(() {
      backend = FakeBackend();
      live = FakeLiveJourney();
      trains = [departure(inMinutes(5), trainNumber: '154101')];
      backend.on(
        'GET',
        '/api/v2/stops/${chatelet.id}/departures',
        (_) => FakeResponse(StopDepartures(
          stop: chatelet,
          realtimeAvailable: true,
          lines: [LineDepartures(line: rerA, destination: 'Fontenay-sous-Bois', departures: trains)],
        ).toJson()),
      );
      container = testContainer(backend, overrides: [
        liveJourneyProvider.overrideWithValue(live),
        positionFeedProvider.overrideWithValue(PositionFeed(open: (_) => StreamController<Position>().stream)),
        userLocationProvider.overrideWith((ref) => Stream.value(const LatLng(48.8584, 2.3470))),
      ]);
      container.listen(departureFollowProvider, (_, _) {});
      container.listen(goControllerProvider, (_, _) {});
      addTearDown(container.dispose);
    });

    test('shows the departure at once, then what the stop says of it', () async {
      trains = [departure(inMinutes(9), aimed: inMinutes(5), trainNumber: '154101').copyWith(platform: 'B')];
      container.read(departureFollowProvider.notifier).follow(followedTrain(departure(inMinutes(5), trainNumber: '154101')));
      expect(live.departures, hasLength(1));

      await pumpEventQueue();
      await pumpEventQueue();
      // Late and on platform B now
      expect(container.read(departureFollowProvider)!.departure.platform, 'B');
      expect(live.departures.last.status, contains('voie B'));
      expect(live.departures.last.tone, LiveJourneyTone.caution);
      expect(backend.requestsTo('/api/v2/stops/${chatelet.id}/departures'), hasLength(1));
    });

    test('"Arrêter" in the notification ends it', () async {
      container.read(departureFollowProvider.notifier).follow(followedTrain(trains.single));
      live.tapStop();
      expect(container.read(departureFollowProvider), isNull);
      expect(live.stops, greaterThan(0));
      await pumpEventQueue();
    });

    test('a departure that left more than a minute ago is not followed', () async {
      container.read(departureFollowProvider.notifier).follow(followedTrain(departure(inMinutes(-2))));
      expect(container.read(departureFollowProvider), isNull);
      expect(live.departures, isEmpty);
      await pumpEventQueue();
    });

    test('GO started: the notification is the journey\'s', () async {
      container.read(departureFollowProvider.notifier).follow(followedTrain(trains.single));
      final now = DateTime.now().toUtc();
      container
          .read(goControllerProvider.notifier)
          .start(journey([walk(now, 240), transit(now.add(const Duration(minutes: 6)), 480, via: [gareDeLyon])]), const JourneyRequest());
      await pumpEventQueue();
      expect(container.read(departureFollowProvider), isNull);
      expect(live.updates, isNotEmpty);
      container.read(goControllerProvider.notifier).stop();
    });
  });
}

String _clock(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
