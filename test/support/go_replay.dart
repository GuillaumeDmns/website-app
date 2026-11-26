import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/location/location_providers.dart';
import 'package:website_app/core/location/position_feed.dart';
import 'package:website_app/core/platform/live_journey.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_state.dart';
import 'package:website_app/features/go/go_trace.dart';
import 'package:website_app/features/journey/journey_providers.dart';
import 'package:website_app/features/journey/journey_request.dart';

import 'fake_backend.dart';
import 'fake_live_journey.dart';
import 'standard_backend.dart';
import 'test_container.dart';

/// The beat of GO's clock between a trace's events ([GoController.tick])
const _beat = Duration(seconds: 5);

/// A state of GO while a trace is played again, and when
typedef GoReplayed = ({DateTime at, GoState state});

/// Plays a session of GO's trace again ([GoTrace], exported from a development build): the journey, then the fixes,
/// the departures and the location turned off and on at the times they came, through GO's own controller on a
/// simulated clock, beating every 5 s between them like the controller's. The departures asked are answered with the last ones the trace received for that line. Gives GO's
/// state after each of them; the trace's own `progress` and `follow` events say what the app made of them then.
/// The departures the user chose in a card (`choose` events) are chosen again at their times; [taps]: more of what the
/// user did then, untraced (older traces), done at those times on the controller.
Future<List<GoReplayed>> replayGoTrace(Map<String, Object?> session,
    {Map<DateTime, Future<void> Function(GoController controller)> taps = const {}}) async {
  final events = [for (final event in session['events'] as List) (event as Map).cast<String, Object?>()];
  final start = events.firstWhere((event) => event['kind'] == 'start');
  final journey = JourneyOption.fromJson((start['journey'] as Map).cast<String, dynamic>());
  var time = DateTime.parse(start['t'] as String);

  // The departures last received for each line
  final rides = <String, List<Object?>>{};
  String? lineOf(Object? step) {
    final index = step is int ? step : -1;
    final transit = journey.sections.where((section) => section.kind != SectionKind.wait && section.from != null && section.to != null).toList();
    return index >= 0 && index < transit.length ? transit[index].line?.id : null;
  }

  final backend = standardBackend();
  backend.on('GET', '/api/v2/lines/*/rides', (request) {
    final segments = request.uri.pathSegments;
    final line = segments[segments.indexOf('lines') + 1];
    return FakeResponse(rides[line] ?? const []);
  });
  final fixes = StreamController<Position>.broadcast();
  final service = StreamController<bool>.broadcast();
  addTearDown(fixes.close);
  addTearDown(service.close);
  final first = journey.sections.firstOrNull?.from;
  final container = testContainer(backend, overrides: [
    positionFeedProvider.overrideWithValue(PositionFeed(open: (_) => fixes.stream, serviceEnabled: () => service.stream)),
    liveJourneyProvider.overrideWithValue(FakeLiveJourney()),
    userLocationProvider.overrideWith((ref) => Stream.value(first == null ? null : LatLng(first.lat, first.lon))),
    goClockProvider.overrideWithValue(() => time),
    // Not traced again
    goTraceProvider.overrideWithValue(null),
  ]);
  container.listen(goControllerProvider, (_, _) {});
  final controller = container.read(goControllerProvider.notifier);
  controller.start(journey, const JourneyRequest());
  await pumpEventQueue();

  final states = <GoReplayed>[];
  void record() {
    final state = container.read(goControllerProvider);
    if (state != null) {
      states.add((at: time, state: state));
    }
  }

  // The controller's 5 s clock beats between the events, from the start as in the app: what the schedule does without
  // a fix
  var beat = time.add(_beat);
  // The departures the user chose in a card, as traced, with the taps given
  final waiting = [
    ...taps.entries,
    for (final event in events)
      if (event['kind'] == 'choose' && event['byUser'] == true)
        MapEntry<DateTime, Future<void> Function(GoController)>(
          DateTime.parse(event['t'] as String),
          (controller) => controller.choose(event['step'] as int, Ride.fromJson((event['ride'] as Map).cast<String, dynamic>()),
              byUser: true),
        ),
  ]..sort((a, b) => a.key.compareTo(b.key));
  Future<void> tapsUntil(DateTime next) async {
    while (waiting.isNotEmpty && !waiting.first.key.isAfter(next)) {
      final tap = waiting.removeAt(0);
      time = tap.key;
      await tap.value(controller);
      await pumpEventQueue();
      record();
    }
  }

  for (final event in events) {
    final next = DateTime.parse(event['t'] as String);
    for (; beat.isBefore(next); beat = beat.add(_beat)) {
      await tapsUntil(beat);
      time = beat;
      controller.tick();
      await pumpEventQueue();
      record();
    }
    await tapsUntil(next);
    time = next;
    switch (event['kind']) {
      case 'fix':
        fixes.add(Position(
          latitude: (event['lat'] as num).toDouble(),
          longitude: (event['lon'] as num).toDouble(),
          timestamp: DateTime.parse(event['timestamp'] as String),
          accuracy: (event['accuracy'] as num).toDouble(),
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: (event['speed'] as num).toDouble(),
          speedAccuracy: (event['speedAccuracy'] as num).toDouble(),
        ));
      case 'rides':
        final line = lineOf(event['step']);
        if (line != null) {
          rides[line] = event['rides'] as List<Object?>;
          container.invalidate(rideOptionsProvider);
        }
      case 'service':
        service.add(event['enabled'] == true);
      default:
        continue;
    }
    await pumpEventQueue();
    record();
  }
  controller.stop();
  return states;
}
