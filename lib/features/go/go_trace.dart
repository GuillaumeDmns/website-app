import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api/models.dart';
import '../../core/config.dart';
import '../../core/storage/local_store.dart';
import 'go_tracker.dart';

/// What GO received during a session and what it made of it, in the development builds: the journey, every position
/// fix as the device gave it, the departures received for each ride, the location turned off and on, the progress as
/// it changed, the vehicles followed, the departures chosen, and what the user said (the train taken, asked once
/// arrived; "GO se trompe" at a moment). Exported from GO's page ("Exporter la trace"), a session is played again in
/// the tests (`test/support/go_replay.dart`): a journey GO got wrong becomes a test. Kept on the device only, the last
/// [sessions] sessions, written when the app leaves the screen, when the session ends and every [_flushEvery] events
/// (each write rewrites the whole preferences file on Android).
class GoTrace {
  GoTrace(this._store);

  static const storageKey = 'go_traces';
  static const sessions = 3;

  /// A session longer than this keeps its last events (about two hours of fixes a second)
  static const _maxEvents = 8000;
  static const _flushEvery = 600;

  final LocalStore _store;
  List<Map<String, Object?>>? _events;
  String? _id;
  int _unwritten = 0;
  ({int step, String phase, int stopIndex, int shift})? _lastProgress;

  /// A new session following [journey], from [at]
  void start(JourneyOption journey, DateTime at) {
    unawaited(flush());
    _id = at.toIso8601String();
    _events = [];
    _lastProgress = null;
    _add(at, 'start', {'journey': _json(journey)});
  }

  void fix(Position position, DateTime at) => _add(at, 'fix', {
        'lat': position.latitude,
        'lon': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
        'speedAccuracy': position.speedAccuracy,
        'timestamp': position.timestamp.toIso8601String(),
      });

  /// The departures received for the ride [step]
  void rides(int step, List<Ride> rides, DateTime at) => _add(at, 'rides', {'step': step, 'rides': _json(rides)});

  void service(bool enabled, DateTime at) => _add(at, 'service', {'enabled': enabled});

  /// The progress, when its step, phase, stop or delay changed
  void progress(GoProgress progress, DateTime at) {
    final summary = (step: progress.step, phase: progress.phase.name, stopIndex: progress.stopIndex, shift: progress.shift.inSeconds);
    if (summary == _lastProgress) {
      return;
    }
    _lastProgress = summary;
    _add(at, 'progress', {'step': summary.step, 'phase': summary.phase, 'stopIndex': summary.stopIndex, 'shift': summary.shift});
  }

  /// The journey now follows [ride] for the ride [step]
  void follow(int step, Ride ride, DateTime at) => _add(at, 'follow', {'step': step, 'ride': _json(ride)});

  /// [ride] taken for the ride [step] ([GoController.choose]): [byUser] chosen in a card (played again by
  /// `replayGoTrace`), else by GO (the departure aimed at, its times moved, a vehicle missed)
  void choose(int step, Ride ride, DateTime at, {required bool byUser}) =>
      _add(at, 'choose', {'step': step, 'byUser': byUser, 'ride': _json(ride)});

  /// The session in progress, to say later what happened in it ([taken])
  String? get sessionId => _id;

  /// What the user says they took for the ride [step], asked once arrived: the truth the tests check GO against.
  /// [session]: the one in progress or, closed since, one kept.
  Future<void> taken(String session, int step, Departure departure, DateTime at) =>
      _note(session, at, 'taken', {'step': step, 'departure': _json(departure)});

  /// GO went wrong about then, as the user says ("GO se trompe"), with what they wrote
  Future<void> flag(String? note, DateTime at) async {
    final session = _id;
    if (session != null) {
      await _note(session, at, 'flag', {if (note != null && note.trim().isNotEmpty) 'note': note.trim()});
    }
  }

  /// An event said by the user: written at once, into a session kept if it ended meanwhile
  Future<void> _note(String session, DateTime at, String kind, Map<String, Object?> data) async {
    if (session == _id) {
      _add(at, kind, data);
      await flush();
      return;
    }
    final kept = await read(_store);
    final found = kept.where((other) => other['id'] == session).firstOrNull;
    final events = found?['events'];
    if (events is! List) {
      return;
    }
    events.add({'t': at.toIso8601String(), 'kind': kind, ...data});
    await _store.writeJson(storageKey, kept);
  }

  void stop(DateTime at) {
    _add(at, 'stop', const {});
    unawaited(flush());
    _events = null;
    _id = null;
  }

  void _add(DateTime at, String kind, Map<String, Object?> data) {
    final events = _events;
    if (events == null) {
      return;
    }
    events.add({'t': at.toIso8601String(), 'kind': kind, ...data});
    if (events.length > _maxEvents) {
      // The journey stays first
      events.removeAt(1);
    }
    if (++_unwritten >= _flushEvery) {
      unawaited(flush());
    }
  }

  /// Writes the session in progress with the ones before it
  Future<void> flush() async {
    final events = _events;
    final id = _id;
    if (events == null || id == null || _unwritten == 0) {
      return;
    }
    _unwritten = 0;
    final kept = await read(_store);
    kept.removeWhere((session) => session['id'] == id);
    kept.add({'id': id, 'events': List.of(events)});
    while (kept.length > sessions) {
      kept.removeAt(0);
    }
    await _store.writeJson(storageKey, kept);
  }

  /// The sessions kept, the latest last
  static Future<List<Map<String, Object?>>> read(LocalStore store) async {
    final json = await store.readJson(storageKey);
    return json is List ? [for (final session in json) if (session is Map) session.cast<String, Object?>()] : [];
  }

  /// The sessions kept, as the text exported
  static Future<String> export(LocalStore store) async => const JsonEncoder.withIndent(' ').convert(await read(store));

  /// Through JSON: nested objects as plain maps
  static Object? _json(Object value) => jsonDecode(jsonEncode(value));
}

/// GO's trace in the development and beta builds (the beta follows real journeys on the production backend), none in
/// the published app
final goTraceProvider = Provider<GoTrace?>((ref) => AppConfig.isDev || AppConfig.isBeta ? GoTrace(ref.read(localStoreProvider)) : null);
