import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/time_format.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/go/go_vehicle_match.dart';

import '../../support/go_replay.dart';

/// Real journeys played again: every session of the GO traces exported into `traces/` (at the root of the app, out of
/// git: the user's trips are no one else's, `.git/info/exclude`), checked against what the user says happened.
/// Without that folder (the CI) nothing runs. Run before committing a change to GO:
///
///     flutter test test/features/go/go_traces_test.dart
///
/// Each export holds the last sessions of the device; the same session in several exports is played once (the
/// longest copy). What happened comes from the trace itself (`taken` events: the train answered once arrived, in the
/// development and beta builds) and from `traces/expected.json`, written by hand for the older traces:
///
///     {
///       "<session id>": {
///         "note": "Bécon → Saint-Lazare, chose the late 15:15 then took the 15:11",
///         "taken": {"1": "134618"},
///         "taps": [{"t": "2026-11-26T15:07:30", "step": 1, "train": "135954"}]
///       }
///     }
///
/// `taken`: per ride (step of the journey) the departure taken, by its train number, else its time (`15:11`, local
/// time of the device, scheduled or real); `taps`: the departures chosen in a card before the traces kept them
/// (`choose` events), the same way.
///
/// Checked for every session: played to its end; the departure aimed at never swaps back and forth before boarding
/// (A, B, then A again within 3 minutes, the user choosing nothing); the end reached when the trace reached it; and on
/// board each ride, the departure GO follows is the one taken.
void main() {
  final folder = Directory('traces');
  final sessions = _sessions(folder);
  if (sessions.isEmpty) {
    test('GO traces: none in traces/ (they stay on the developer\'s machine)', () {}, skip: 'no traces/ folder');
    return;
  }
  final expected = _expected(File('${folder.path}/expected.json'));

  for (final session in sessions) {
    final id = session['id'] as String;
    final said = expected[id] ?? const <String, Object?>{};
    final note = said['note'];
    test('GO trace $id${note is String ? ': $note' : ''}', () async {
      final events = [for (final event in session['events'] as List) (event as Map).cast<String, Object?>()];
      final seen = _ridesSeen(events);
      final taps = <DateTime, Future<void> Function(GoController)>{};
      for (final tap in (said['taps'] as List?) ?? const []) {
        final map = (tap as Map).cast<String, Object?>();
        final step = map['step'] as int;
        final ride = _find(seen[step] ?? const [], map['train'] as String);
        expect(ride, isNotNull, reason: 'tap ${map['t']}: no departure ${map['train']} seen for the ride $step');
        taps[DateTime.parse(map['t'] as String)] = (controller) => controller.choose(step, ride!, byUser: true);
      }

      final replayed = await replayGoTrace(session, taps: taps);
      expect(replayed, isNotEmpty);
      final tapped = {for (final at in taps.keys) at, for (final event in events) if (event['kind'] == 'choose' && event['byUser'] == true) DateTime.parse(event['t'] as String)};

      // The departure taken for each ride: answered in the app, else written by hand
      final taken = <int, Departure>{};
      for (final event in events.where((event) => event['kind'] == 'taken')) {
        taken[event['step'] as int] = Departure.fromJson((event['departure'] as Map).cast<String, dynamic>());
      }
      for (final MapEntry(:key, :value) in ((said['taken'] as Map?) ?? const {}).entries) {
        final step = int.parse(key as String);
        final ride = _find(seen[step] ?? const [], value as String);
        expect(ride, isNotNull, reason: 'taken: no departure $value seen for the ride $step');
        taken[step] = ride!.departure;
      }

      final summary = <String>[];
      final steps = replayed.last.state.tracker.steps;
      for (final (step, ride) in steps.indexed) {
        if (!ride.isRide) {
          continue;
        }
        // Before boarding: no swapping back and forth on its own
        final aimed = <({DateTime at, String id})>[];
        for (final (:at, :state) in replayed) {
          final progress = state.progress;
          final before = progress.step < step || progress.step == step && progress.phase == GoPhase.waiting;
          final vehicle = state.vehicleStep == step ? state.vehicle : null;
          if (!before || vehicle == null) {
            continue;
          }
          final key = _identity(vehicle);
          if (aimed.isEmpty || aimed.last.id != key) {
            aimed.add((at: at, id: key));
          }
        }
        for (var i = 2; i < aimed.length; i++) {
          final (a, b, c) = (aimed[i - 2], aimed[i - 1], aimed[i]);
          final chosen = tapped.any((at) => !at.isBefore(a.at) && !at.isAfter(c.at.add(const Duration(seconds: 5))));
          expect(a.id == c.id && c.at.difference(a.at) < const Duration(minutes: 3) && !chosen, isFalse,
              reason: 'ride $step: aimed at ${a.id}, ${b.id} then ${c.id} again by ${_clock(c.at)}');
        }

        // On board: the departure followed, the one taken
        final onBoard = replayed.where((replayed) => replayed.state.progress.step == step && replayed.state.progress.phase == GoPhase.onBoard);
        if (onBoard.isEmpty) {
          summary.add('ride $step: never on board');
          expect(taken[step], isNull, reason: 'ride $step: taken, never on board');
          continue;
        }
        final last = onBoard.last;
        final section = last.state.tracker.steps[step].section;
        final followed = _closest(seen[step] ?? const [], section.departure, section.arrival);
        summary.add('ride $step: on board ${_clock(onBoard.first.at)}–${_clock(last.at)}, follows '
            '${followed == null ? '?' : _identity(followed.departure)} (${_clock(section.departure)} → ${_clock(section.arrival)})'
            '${taken[step] == null ? '' : ', taken ${_identity(taken[step]!)}'}');
        if (taken[step] case final truth?) {
          expect(followed != null && sameVehicleDeparture(followed.departure, truth), isTrue,
              reason: 'ride $step: follows ${followed == null ? 'none' : _identity(followed.departure)}, took ${_identity(truth)}');
        }
      }

      if (events.any((event) => event['kind'] == 'progress' && event['phase'] == 'arrived')) {
        expect(replayed.any((replayed) => replayed.state.progress.phase == GoPhase.arrived), isTrue, reason: 'never arrived');
      }
      // ignore: avoid_print
      print('$id\n  ${summary.join('\n  ')}');
    });
  }
}

/// The sessions of every export in [folder], each once (its longest copy), in time order
List<Map<String, Object?>> _sessions(Directory folder) {
  if (!folder.existsSync()) {
    return const [];
  }
  final byId = <String, Map<String, Object?>>{};
  final files = folder.listSync().whereType<File>().where((file) => file.path.endsWith('.json') && !file.path.endsWith('expected.json'));
  for (final file in files) {
    final json = jsonDecode(file.readAsStringSync());
    for (final session in json is List ? json : const []) {
      final map = (session as Map).cast<String, Object?>();
      final id = map['id'];
      final events = map['events'];
      if (id is! String || events is! List || !events.any((event) => event is Map && event['kind'] == 'start')) {
        continue;
      }
      final known = byId[id];
      if (known == null || (known['events'] as List).length < events.length) {
        byId[id] = map;
      }
    }
  }
  return byId.values.toList()..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
}

Map<String, Map<String, Object?>> _expected(File file) {
  if (!file.existsSync()) {
    return const {};
  }
  final json = jsonDecode(file.readAsStringSync()) as Map;
  return {for (final MapEntry(:key, :value) in json.entries) key as String: (value as Map).cast<String, Object?>()};
}

/// The departures received for each ride, each once with its last known times (gone from the lists once left)
Map<int, List<Ride>> _ridesSeen(List<Map<String, Object?>> events) {
  final seen = <int, List<Ride>>{};
  for (final event in events.where((event) => event['kind'] == 'rides')) {
    final list = seen.putIfAbsent(event['step'] as int, () => []);
    for (final json in event['rides'] as List) {
      final ride = Ride.fromJson((json as Map).cast<String, dynamic>());
      final known = list.indexWhere((other) => sameDeparture(other, ride));
      known >= 0 ? list[known] = ride : list.add(ride);
    }
  }
  return seen;
}

/// A departure by its train number, else by its local time (`15:11`), scheduled or real
Ride? _find(List<Ride> rides, String said) {
  final byNumber = rides.where((ride) => ride.departure.trainNumber == said).firstOrNull;
  if (byNumber != null) {
    return byNumber;
  }
  return rides
      .where((ride) => formatClock(ride.departure.time) == said || ride.departure.aimedTime != null && formatClock(ride.departure.aimedTime!) == said)
      .firstOrNull;
}

/// Of [rides], the one closest to leaving at [departure] and arriving at [arrival]: the one the journey follows
Ride? _closest(List<Ride> rides, DateTime departure, DateTime arrival) {
  Ride? best;
  Duration? bestGap;
  for (final ride in rides) {
    final arrives = ride.arrivalAt ?? ride.stops.lastOrNull?.time;
    final gap = ride.departure.time.difference(departure).abs() + (arrives == null ? Duration.zero : arrives.difference(arrival).abs());
    if (bestGap == null || gap < bestGap) {
      best = ride;
      bestGap = gap;
    }
  }
  return best;
}

String _identity(Departure departure) => [
      ?departure.trainNumber,
      ?departure.mission,
      formatClock(departure.aimedTime ?? departure.time),
    ].join(' ');

String _clock(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
