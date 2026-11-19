import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/location/position_feed.dart';
import '../../core/map/map_overlay.dart';
import '../../core/platform/app_shown.dart';
import '../../core/platform/live_journey.dart';
import '../../core/storage/local_store.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/refresh.dart';
import '../../l10n/l10n.dart';
import '../auth/auth_controller.dart';
import '../follow/departure_follow.dart';
import '../journey/journey_providers.dart';
import '../journey/journey_request.dart';
import '../journey/journey_retime.dart';
import 'go_cards.dart';
import 'go_guidance.dart';
import 'go_live.dart';
import 'go_smoother.dart';
import 'go_state.dart';
import 'go_trace.dart';
import 'go_tracker.dart';
import 'go_vehicle_match.dart';

const _storageKey = 'go_session';

/// How often GO needs a position fix at the moment of [state]: every second on foot or by bike while the app is on
/// screen (the map follows the user), every two seconds in the background (the turns are still felt ahead); less while
/// waiting at the stop or riding, where the tracker only needs to see the vehicle leave and the stops go by. Null once
/// arrived: the app's regular positions.
LocationNeed? goLocationNeed(GoState? state, {required bool shown}) => switch (state?.progress.phase) {
      null || GoPhase.arrived => null,
      GoPhase.moving => LocationNeed(Duration(seconds: shown ? 1 : 2)),
      GoPhase.waiting => const LocationNeed(Duration(seconds: 5)),
      GoPhase.onBoard => const LocationNeed(Duration(seconds: 3)),
    };

/// The speed [fix] is sure of (m/s): its speed less its accuracy, null when unknown. A phone lying indoors reports
/// 2.5 ± 2.1 m/s: still for GO (no smoothed walk, no boarding seen, no pace)
double? sureSpeed(Position fix) => fix.speed < 0 ? null : math.max(0, fix.speed - math.max(0, fix.speedAccuracy));

/// When the position of [fix] was first given, [previous] being the fix before it, whose position was first given at
/// [since]: the same position given again with a new time (the system's last one, underground) is no fresher, and no
/// sign that the user is still there. With [rough] (waiting, on board), neither is a rough position within the
/// accuracies of the one before (a cell tower, the GPS stuck at a station while the metro takes the user five stations
/// away): only a rough one that moved says something.
DateTime positionSince(Position fix, Position? previous, DateTime? since, {bool rough = false}) {
  if (previous == null || since == null) {
    return fix.timestamp;
  }
  if (previous.latitude == fix.latitude && previous.longitude == fix.longitude) {
    return since;
  }
  final stuck = rough && fix.accuracy > _preciseAccuracy && previous.accuracy > _preciseAccuracy &&
      metersBetween(LatLng(fix.latitude, fix.longitude), LatLng(previous.latitude, previous.longitude)) <=
          math.max(fix.accuracy, previous.accuracy);
  return stuck ? since : fix.timestamp;
}

/// A fix this precise is the GPS's (see [GoTracker])
const _preciseAccuracy = 30.0;

/// Whether [alert] is felt (sound, vibration): not when muted, nor a getting-off alert of a ride whose alerts the user
/// turned off ("Alerter quand descendre")
bool goAlertFelt(GoState state, GoAlert alert) {
  if (state.muted) {
    return false;
  }
  final alighting = alert.kind == 'prepare' || alert.kind == 'alight';
  return !alighting || !state.alightAlertsOff.contains(int.tryParse(alert.id.split('-').last));
}

/// GO session: feeds the [GoTracker] with high-accuracy positions (the app's [PositionFeed], asked as often as the
/// moment needs, [goLocationNeed]), a 5 s clock and the real-time departures of the next ride (`rideOptionsProvider`,
/// every 30 s, shared with the cards showing them), gives the alerts, and keeps the session on the device so that it
/// survives a restart. On board, the journey follows the vehicle guessed among the departures seen at the stop
/// ([VehicleMatch]), from waiting for it on.
class GoController extends Notifier<GoState?> {
  DateTime _now() => ref.read(goClockProvider)();

  /// What the session received and made of it (development builds)
  GoTrace? get _trace => ref.read(goTraceProvider);

  PositionFeed? _feed;
  StreamSubscription<Position>? _positions;
  Timer? _tick;
  static const _tickEvery = Duration(seconds: 5);
  Timer? _departuresTimer;
  Position? _lastFix;

  /// When the position of [_lastFix] was first given ([positionSince])
  DateTime? _fixSince;

  /// What the map shows of the fixes, redrawn ([GoSmoother.redrawInterval]) while it moves and the app is on screen
  final _smoother = GoSmoother();
  Timer? _smoothTimer;
  bool _shown = true;

  /// The user's pace on the moves (m/s), averaged over the fixes
  double? _walkSpeed;

  /// A move ridden in a vehicle, from the fixes' speeds
  final _vehicleSpeed = GoVehicleSpeed();

  /// The turn last felt (its offset on the walk of that step), to give each one once
  String? _turnFelt;

  /// After the arrival, the session closes itself
  Timer? _closeTimer;
  static const _closeAfter = Duration(minutes: 2);

  /// Last content sent to the system notification, to only send changes
  String? _lastLive;
  int _lastLiveProgress = -1;

  /// Departures of the next ride listened to, and for which ride (step and tracker) of which key; the last ones
  /// received, to replace a missed vehicle at once
  ProviderSubscription<AsyncValue<List<Ride>>>? _departures;
  ({RideKey key, GoTracker tracker, int step})? _departuresOf;
  List<Ride>? _rides;

  /// A missed or cancelled vehicle being replaced by the next one
  bool _retaining = false;

  /// Departures received for each ride of the journey followed by [_seenFor] (by step), the departed ones kept: those
  /// the user may have boarded
  final _seen = <int, List<Ride>>{};
  GoTracker? _seenFor;

  /// From waiting for a ride to its alighting stop, which of them the user is on, and the journey being moved to it
  VehicleMatch? _match;
  DateTime? _matchedFixAt;
  bool _following = false;

  /// Since when the GPS sees the user still at the platform (or in the vehicle standing there)
  DateTime? _stillSince;

  /// The device's location turned on and off
  StreamSubscription<bool>? _service;

  /// The location back (turned on again, a session taken up after a restart): from when fixes are new, the rough one
  /// waiting for a second one to agree with it, and the next fix to place anywhere on the journey ([GoInput.relocate])
  DateTime? _reacquireFrom;
  Position? _reacquireRough;
  Position? _beforeOff;
  bool _relocateNext = false;

  /// When the last precise fix came: after minutes without one (a long tunnel), the next may be anywhere
  DateTime? _lastPreciseAt;
  static const _longWithoutPrecise = Duration(minutes: 3);

  /// After boarding, the ride's departures followed a few minutes more (see [_watchBoarded]), and which ones
  ProviderSubscription<AsyncValue<List<Ride>>>? _boarded;
  ({RideKey key, GoTracker tracker, int step})? _boardKey;
  static const _boardedWatch = Duration(minutes: 5);

  /// Off the way: the recalculation on its own, after a countdown the user can beat or cancel
  Timer? _recalculateTimer;
  static const _recalculateAfter = Duration(seconds: 10);

  @override
  GoState? build() {
    ref.listen(authControllerProvider, (previous, status) {
      // Signed out: the followed journey was the account's
      if (previous == AuthStatus.signedIn && status == AuthStatus.guest) {
        _stopFeeds();
        state = null;
      }
    });
    // Off screen (screen off, app in the background): nothing to draw, fewer fixes
    _shown = ref.read(appShownProvider);
    ref.listen(appShownProvider, (_, shown) {
      _shown = shown;
      if (!shown) {
        unawaited(_trace?.flush());
      }
      _smoothen();
      _askPositions();
    });
    ref.onDispose(_stopFeeds);
    // "Terminer" in the notification ("Arrêter" for a departure followed without a journey)
    ref.read(liveJourneyProvider).onStop(() {
      ref.read(departureFollowProvider.notifier).stop();
      stop();
    });
    _restore();
    return null;
  }

  /// Starts following [journey]; [request] gives the destination and options to recalculate
  void start(JourneyOption journey, JourneyRequest? request) {
    ref.read(liveJourneyProvider).prepare();
    _begin(journey, _requestFor(journey, request), muted: state?.muted ?? false, keepAwake: state?.keepAwake ?? false);
  }

  void stop() {
    if (state != null) {
      _trace?.stop(_now());
    }
    _closeTimer?.cancel();
    _closeTimer = null;
    _stopFeeds();
    state = null;
    _lastLive = null;
    ref.read(liveJourneyProvider).stop();
    ref.read(localStoreProvider).remove(_storageKey);
  }

  void next() => _setProgress((tracker, progress) => tracker.next(progress));

  void jumpTo(int step) => _setProgress((tracker, progress) => tracker.jumpTo(progress, step));

  /// "Je suis ici" on [card]: GO goes on from there, on board for a ride's card, [along] meters along a move (out of
  /// the station got off at, for a walk's card after it)
  void hereAt(GoCard card, {double along = 0}) => _setProgress((tracker, progress) => switch (card.kind) {
        GoCardKind.ride => tracker.next(tracker.jumpTo(progress, card.step)),
        GoCardKind.walk => tracker.jumpTo(progress, card.step, along: along),
        _ => tracker.jumpTo(progress, card.step),
      });

  /// "Alerter quand descendre" for the ride [step]: off, its getting-off alerts are not felt
  void setAlightAlert(int step, bool on) {
    final current = state;
    if (current == null) {
      return;
    }
    final off = {...current.alightAlertsOff};
    on ? off.remove(step) : off.add(step);
    state = current.copyWith(alightAlertsOff: off);
    _save();
  }

  void dismissIssue() {
    _cancelRecalculation();
    _setProgress((tracker, progress) => tracker.dismissIssue(progress));
  }

  void _cancelRecalculation() {
    _recalculateTimer?.cancel();
    _recalculateTimer = null;
    if (state?.recalculateAt != null) {
      state = state!.copyWith(recalculateAt: () => null);
    }
  }

  /// Takes [ride] for the ride [step] (in progress or to come) instead of the planned departure (missed, cancelled,
  /// or another one preferred): the journey moves to it from there, the following connections included. [retained]:
  /// taken on its own for a missed or cancelled vehicle, said as such with how much later the arrival is.
  Future<void> choose(int step, Ride ride, {bool retained = false, bool cancelled = false}) async {
    final current = state;
    if (current == null || step < current.progress.step || step >= current.tracker.steps.length) {
      return;
    }
    final previousEta = current.tracker.eta(current.progress, current.currentVehicle);
    final sectionIndex = current.tracker.steps[step].sectionIndex;
    var journey = await _retimedWith(current, step, ride);

    final latest = state;
    if (latest == null || latest.tracker != current.tracker) {
      return;
    }
    final progress = latest.progress;
    if (step > progress.step && progress.shift != Duration.zero) {
      // The current ride's lateness still applies to what follows it: the chosen times are kept as they are
      journey = shiftJourney(journey, from: sectionIndex, by: -progress.shift);
    }
    final tracker = GoTracker(journey);
    final chosen = tracker.chosen(progress, step);
    state = GoState(
      tracker: tracker,
      request: latest.request,
      progress: chosen,
      startedAt: latest.startedAt,
      plannedArrival: latest.plannedArrival,
      muted: latest.muted,
      keepAwake: latest.keepAwake,
      position: latest.position,
      retained: retained ? (step: step, later: tracker.eta(chosen, null).difference(previousEta), cancelled: cancelled) : null,
      alightAlertsOff: latest.alightAlertsOff,
      locationOff: latest.locationOff,
    );
    _save();
    // The departures followed go on with the screen off
    ref.read(followedOffScreenProvider.notifier).set(true);
    _watchDepartures();
    _update();
  }

  /// [current]'s journey with [ride] taken for the ride [step], the departures of the following rides fetched as the
  /// retiming asks for them
  Future<JourneyOption> _retimedWith(GoState current, int step, Ride ride) async {
    final sectionIndex = current.tracker.steps[step].sectionIndex;
    final api = ref.read(mobilityApiProvider);
    final now = _now();
    final known = <RideKey, List<Ride>>{};
    var retimed = retimeJourney(current.journey, lookup: (key) => known[key], now: now, choices: {sectionIndex: ride}, from: sectionIndex);
    for (var round = 0; round < 6; round++) {
      final missing = retimed.rides.values.map((plan) => plan.key).where((key) => !known.containsKey(key)).toList();
      if (missing.isEmpty) {
        break;
      }
      for (final key in missing) {
        try {
          known[key] = await api.lineRides(key.lineId, from: key.from, to: key.to, after: key.after, limit: 8);
        } catch (e) {
          known[key] = const [];
        }
      }
      retimed = retimeJourney(current.journey, lookup: (key) => known[key], now: now, choices: {sectionIndex: ride}, from: sectionIndex);
    }
    return retimed.journey;
  }

  /// The vehicle the user is on, among the departures seen at the stop ([VehicleMatch]), from waiting for it to the
  /// alighting stop: the journey follows it, without a word to the user
  void _matchVehicle(GoState state) {
    final progress = state.progress;
    final ride = state.tracker.stepOf(progress);
    if (ride == null || !ride.isRide || (progress.phase != GoPhase.waiting && progress.phase != GoPhase.onBoard)) {
      _match = null;
      _stillSince = null;
      return;
    }
    final now = _now();
    var match = _match;
    if (match == null || match.step != progress.step) {
      match = _match = VehicleMatch(progress.step, ride);
      _stillSince = null;
      final seen = _seenFor == state.tracker ? _seen[progress.step] : null;
      if (seen != null) {
        match.seen(seen, now);
      }
    }
    final fix = _lastFix;
    final since = _fixSince;
    final fresh = fix != null && since != null && now.difference(since) <= const Duration(seconds: 30);
    if (progress.phase == GoPhase.waiting) {
      // Still at the platform, or seated in the vehicle standing there, by the GPS: not on any departure gone since
      final speed = fix == null ? null : sureSpeed(fix);
      final still = fresh && fix.accuracy <= _preciseAccuracy && (speed == null || speed < 1) &&
          ride.alongInPlatformZone(LatLng(fix.latitude, fix.longitude), fix.accuracy) != null;
      if (!still) {
        _stillSince = null;
      } else if (now.difference(_stillSince ??= now) >= const Duration(seconds: 30)) {
        match.stillAtPlatform(now);
      }
      return;
    }
    _stillSince = null;
    if (!match.hasDeparted) {
      match.departed(progress.departedAt ?? ride.section.departure.add(progress.shift));
    }
    // A new position only: the same one given again tells nothing of a station (stopped there or not)
    if (fix != null && fix.timestamp != _matchedFixAt && fix.timestamp == since) {
      _matchedFixAt = fix.timestamp;
      match.observe(fix.timestamp, LatLng(fix.latitude, fix.longitude), speed: sureSpeed(fix), accuracy: fix.accuracy);
    }
    final better = match.better;
    if (better != null && !_following) {
      _following = true;
      unawaited(_followRide(progress.step, better).whenComplete(() => _following = false));
    }
  }

  /// On board the ride [step], the vehicle is guessed to be [ride], not the one followed (a direct train, not the
  /// stopping one): the journey follows it from there on, its stops, its arrival and the connections after it, the
  /// user still where they are on board
  Future<void> _followRide(int step, Ride ride) async {
    final current = state;
    if (current == null || current.progress.step != step || current.progress.phase != GoPhase.onBoard) {
      return;
    }
    final journey = await _retimedWith(current, step, ride);
    final latest = state;
    if (latest == null || latest.tracker != current.tracker || latest.progress.step != step || latest.progress.phase != GoPhase.onBoard) {
      return;
    }
    final departed = latest.progress.departedAt ?? latest.tracker.steps[step].section.departure.add(latest.progress.shift);
    final tracker = GoTracker(journey);
    state = latest.copyWith(tracker: tracker, progress: tracker.onAnotherVehicle(latest.progress, departed));
    _match
      ?..ride = tracker.steps[step]
      ..follow(ride);
    _trace?.follow(step, ride, _now());
    // The departures seen are the same ones, for the same ride of the journey moved to that vehicle
    if (_seenFor == latest.tracker) {
      _seenFor = tracker;
    }
    if (_boardKey?.tracker == latest.tracker) {
      _boardKey = (key: _boardKey!.key, tracker: tracker, step: _boardKey!.step);
    }
    _save();
    _watchDepartures();
    _update();
  }

  void toggleKeepAwake() {
    final current = state;
    if (current != null) {
      state = current.copyWith(keepAwake: !current.keepAwake);
      ref.read(liveJourneyProvider).keepScreenOn(!current.keepAwake);
      _save();
    }
  }

  void toggleMute() {
    final current = state;
    if (current != null) {
      state = current.copyWith(muted: !current.muted);
      _save();
    }
  }

  /// New journey from the current position to the same destination with the same options; the first option is
  /// followed.
  Future<void> recalculate() async {
    _recalculateTimer?.cancel();
    _recalculateTimer = null;
    final current = state;
    if (current == null || current.recalculating) {
      return;
    }
    final position = current.position ?? ref.read(userLocationProvider).value;
    final to = current.request.to;
    if (position == null || to == null) {
      state = current.copyWith(error: () => currentL10n.goLocationUnavailable);
      return;
    }

    state = current.copyWith(recalculating: true, error: () => null, recalculateAt: () => null);
    try {
      final request = current.request;
      final plan = await ref.read(mobilityApiProvider).journeys(
            from: '${position.latitude},${position.longitude}',
            to: to.stopAreaId ?? '${to.lat},${to.lon}',
            modes: request.modes,
            wheelchair: request.wheelchair,
            walkingSpeed: request.walkingSpeed.apiName,
            bikeShare: request.bikeShare,
          );
      final journey = plan.journeys.firstOrNull;
      if (journey == null) {
        state = state?.copyWith(recalculating: false, error: () => currentL10n.goNoJourneyFound);
        return;
      }
      _begin(
        journey,
        request.copyWith(from: JourneyPlace.point(name: currentL10n.myLocation, lat: position.latitude, lon: position.longitude)),
        muted: current.muted,
        keepAwake: current.keepAwake,
        plannedArrival: current.plannedArrival,
      );
    } catch (e) {
      state = state?.copyWith(recalculating: false, error: () => currentL10n.goRecalculateFailed('$e'));
    }
  }

  // Internals

  void _begin(
    JourneyOption journey,
    JourneyRequest request, {
    required bool muted,
    bool keepAwake = false,
    DateTime? plannedArrival,
    GoProgress? progress,
    DateTime? startedAt,
    Set<int> alightAlertsOff = const {},
  }) {
    _closeTimer?.cancel();
    _closeTimer = null;
    // One live notification: the journey's, not a departure followed from a stop
    ref.read(departureFollowProvider.notifier).handOver();
    _walkSpeed = null;
    _vehicleSpeed.reset();
    _turnFelt = null;
    final tracker = GoTracker(journey);
    state = GoState(
      tracker: tracker,
      request: request,
      // The GPS gets its usual time for a first fix before the clock leads (GoTracker.followsSchedule): a session taken
      // up again after a restart (the last fix isn't kept with it), or started from a journey looked at for a while,
      // never skips a step by the schedule while that fix comes
      progress: (progress ?? tracker.initial()).copyWith(lastFixAt: _now()),
      startedAt: startedAt ?? _now(),
      plannedArrival: plannedArrival ?? journey.arrival,
      muted: muted,
      keepAwake: keepAwake,
      alightAlertsOff: alightAlertsOff,
    );
    ref.read(liveJourneyProvider).keepScreenOn(keepAwake);
    _trace?.start(journey, _now());
    _save();
    _startFeeds();
  }

  /// Destination and options: from the search when known, else the end of the journey
  static JourneyRequest _requestFor(JourneyOption journey, JourneyRequest? request) {
    final end = journey.sections.lastOrNull?.to;
    final to = request?.to != null && !request!.to!.isCurrentLocation
        ? request.to!
        : end == null
            ? null
            : end.stopAreaId != null
                ? JourneyPlace.stopArea(name: end.name, id: end.stopAreaId!, lat: end.lat, lon: end.lon)
                : JourneyPlace.point(name: end.name, lat: end.lat, lon: end.lon);
    return (request ?? const JourneyRequest()).copyWith(to: to, datetime: () => null, arriveBy: false);
  }

  void _setProgress(GoProgress Function(GoTracker tracker, GoProgress progress) change) {
    final current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(progress: change(current.tracker, current.progress));
    _save();
    // A correction: the ride whose departures matter may have changed
    _watchDepartures();
    _update();
  }

  void _startFeeds() {
    _stopFeeds();
    final feed = ref.read(positionFeedProvider);
    _feed = feed;
    _positions = feed.fixes.listen(_onFix, onError: (Object e) {
      debugPrint('GO positions unavailable: $e');
      if (e is LocationServiceDisabledException) {
        _onService(false);
      }
    });
    _service = feed.serviceEnabled.listen(_onService, onError: (Object e) => debugPrint('GO location status unavailable: $e'));
    _askPositions();
    unawaited(_seed());
    _tick = Timer.periodic(_tickEvery, (_) => _update());
    _departuresTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _watchDepartures();
      _watchBoarded();
    });
    _watchDepartures();
    _update();
  }

  /// The device's location turned off: the schedule leads, the card says so with a way to turn it on; back on, the
  /// device's stream is opened again and the next good fix may be anywhere on the journey
  void _onService(bool enabled) {
    final current = state;
    if (current == null || current.locationOff == !enabled) {
      return;
    }
    if (enabled) {
      _reacquire();
      _feed?.reopen();
    } else {
      _beforeOff = _lastFix ?? _beforeOff;
      // Its last fix says nothing of where the user goes now
      _lastFix = null;
      _fixSince = null;
    }
    _trace?.service(enabled, _now());
    state = current.copyWith(locationOff: !enabled);
    _update();
  }

  /// The location back: fixes from now on only, a precise one or two rough ones agreeing, then placed anywhere on the
  /// journey
  void _reacquire() {
    _reacquireFrom = _now();
    _reacquireRough = null;
  }

  /// [position] is good enough to place the user again after the location came back (see [_reacquire])
  bool _reacquired(Position position) {
    final from = _reacquireFrom;
    if (from == null) {
      return true;
    }
    final last = _beforeOff;
    final givenAgain = last != null && last.latitude == position.latitude && last.longitude == position.longitude;
    if (position.timestamp.isBefore(from.subtract(const Duration(seconds: 2))) || givenAgain) {
      return false;
    }
    if (position.accuracy > _preciseAccuracy) {
      final first = _reacquireRough;
      final agree = first != null && (first.latitude != position.latitude || first.longitude != position.longitude) &&
          metersBetween(LatLng(first.latitude, first.longitude), LatLng(position.latitude, position.longitude)) <=
              math.max(first.accuracy, position.accuracy);
      if (!agree) {
        _reacquireRough = position;
        return false;
      }
    }
    _reacquireFrom = null;
    _reacquireRough = null;
    _beforeOff = null;
    _relocateNext = true;
    return true;
  }

  void _onFix(Position position) {
    _trace?.fix(position, _now());
    if (state?.locationOff == true) {
      // Fixes again: the location is back (its status may come later, or never on this platform)
      _onService(true);
    }
    if (!_reacquired(position)) {
      return;
    }
    if (position.accuracy <= _preciseAccuracy) {
      final last = _lastPreciseAt;
      if (last != null && position.timestamp.difference(last) > _longWithoutPrecise) {
        _relocateNext = true;
      }
      _lastPreciseAt = position.timestamp;
    }
    final phase = state?.progress.phase;
    _fixSince = positionSince(position, _lastFix, _fixSince, rough: phase == GoPhase.waiting || phase == GoPhase.onBoard);
    _lastFix = position;
    final now = _now();
    ref.read(goFixStatsProvider.notifier).record(now, position.accuracy);
    final current = state;
    final step = current?.tracker.stepOf(current.progress);
    final speed = sureSpeed(position);
    if (step != null && !step.isRide) {
      _vehicleSpeed.add(step.section.kind, speed);
    }
    // The pace on foot or by bike, from decent fixes while moving
    if (step != null && !step.isRide && speed != null && speed >= 0.5 && speed <= 9 && position.accuracy <= 30) {
      final pace = _walkSpeed;
      _walkSpeed = pace == null ? speed : pace + (speed - pace) * 0.2;
    }
    _smoother.fix(
      LatLng(position.latitude, position.longitude),
      now,
      speed: speed,
      accuracy: position.accuracy,
      // Going on along the way on foot or by bike only
      path: step == null || step.isRide ? null : step.line,
    );
    _update();
    _smoothen();
  }

  /// GO's first high-accuracy fix may take seconds (the GPS starting): the last known position meanwhile, so that the
  /// map follows the user at once instead of framing the whole journey
  Future<void> _seed() async {
    Position? known;
    try {
      known = kIsWeb ? null : await Geolocator.getLastKnownPosition();
    } catch (_) {
      // Not on this platform
    }
    if (_lastFix != null || _positions == null) {
      return;
    }
    if (known != null && _now().difference(known.timestamp) < const Duration(minutes: 1)) {
      _onFix(known);
      return;
    }
    final position = ref.read(userLocationProvider).value;
    if (position != null) {
      _onFix(Position(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: _now(),
        // The app's regular positions: within 25 m
        accuracy: 25,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: -1,
        speedAccuracy: 0,
      ));
    }
  }

  /// The positions GO needs now from the app's feed
  void _askPositions() => _feed?.need = goLocationNeed(state, shown: _shown);

  /// Shows the smoothed position, redrawn while it moves and the app is on screen (nothing drawn screen off)
  void _smoothen() {
    final position = _smoother.at(_now());
    if (position != null) {
      ref.read(preciseUserPositionProvider.notifier).set(position, accuracy: _lastFix?.accuracy);
    }
    if (_smoothTimer != null || !_shown || !_smoother.moving(_now())) {
      return;
    }
    _smoothTimer = Timer(_smoother.redrawInterval, () {
      _smoothTimer = null;
      _smoothen();
    });
  }

  void _stopFeeds() {
    _lastFix = null;
    _fixSince = null;
    // Not during a build: providers can't be modified while widgets build
    Future.microtask(() {
      try {
        ref.read(preciseUserPositionProvider.notifier).set(null);
        ref.read(goFixStatsProvider.notifier).clear();
        // Started again meanwhile (a recalculation): still followed
        ref.read(followedOffScreenProvider.notifier).set(_tick != null);
      } catch (_) {
        // Disposed
      }
    });
    _positions?.cancel();
    _positions = null;
    // The app's regular positions again
    _feed?.need = null;
    _feed = null;
    _smoothTimer?.cancel();
    _smoothTimer = null;
    _smoother.reset();
    _tick?.cancel();
    _tick = null;
    _departuresTimer?.cancel();
    _departuresTimer = null;
    _departures?.close();
    _departures = null;
    _departuresOf = null;
    _rides = null;
    _seen.clear();
    _seenFor = null;
    _match = null;
    _stillSince = null;
    _boarded?.close();
    _boarded = null;
    _boardKey = null;
    _service?.cancel();
    _service = null;
    _reacquireFrom = null;
    _reacquireRough = null;
    _relocateNext = false;
    _lastPreciseAt = null;
    _recalculateTimer?.cancel();
    _recalculateTimer = null;
  }

  /// The 5 s clock's beat, for a trace played again on a simulated clock (`test/support/go_replay.dart`)
  @visibleForTesting
  void tick() => _update();

  void _update() {
    final current = state;
    if (current == null) {
      return;
    }
    final fix = _lastFix;
    final position = fix == null ? null : LatLng(fix.latitude, fix.longitude);
    final input = GoInput(
      now: _now(),
      position: position,
      accuracy: fix?.accuracy,
      speed: fix == null ? null : sureSpeed(fix),
      fixAt: fix == null ? null : _fixSince,
      vehicle: current.vehicle,
      vehicleStep: current.vehicleStep,
      realtimeDepartures: current.realtimeDepartures,
      relocate: _relocateNext && fix != null,
    );
    if (fix != null) {
      _relocateNext = false;
    }
    final (progress, alerts) = current.tracker.update(current.progress, input);

    final changed = progress.step != current.progress.step ||
        progress.phase != current.progress.phase ||
        progress.stopIndex != current.progress.stopIndex ||
        progress.issue != current.progress.issue ||
        progress.fired.length != current.progress.fired.length;

    if (progress.step != current.progress.step) {
      // A new move: its own pace (on foot after a bike, say)
      _walkSpeed = null;
      _vehicleSpeed.reset();
    }
    var next = current.copyWith(progress: progress, position: position, walkSpeed: _walkSpeed, inVehicle: _vehicleSpeed.inVehicle);
    // The vehicle kept on its own is said until the user is on board (or elsewhere)
    if (current.retained case final retained?
        when progress.step != retained.step || progress.phase != GoPhase.waiting) {
      next = next.copyWith(retained: () => null);
    }
    // Off the way: recalculated on its own after a countdown; back on it, nothing to do
    if (progress.issue == GoIssue.offRoute && current.progress.issue != GoIssue.offRoute && !current.recalculating) {
      _recalculateTimer?.cancel();
      _recalculateTimer = Timer(_recalculateAfter, recalculate);
      next = next.copyWith(recalculateAt: () => _now().add(_recalculateAfter));
    } else if (progress.issue != GoIssue.offRoute && current.recalculateAt != null) {
      _recalculateTimer?.cancel();
      _recalculateTimer = null;
      next = next.copyWith(recalculateAt: () => null);
    }
    // Felt in the app; the ongoing notification says what to do now, and only what must be done at once rings in a
    // notification of its own while the app isn't on screen
    if (alerts.isNotEmpty) {
      final alert = alerts.last;
      next = next.copyWith(alert: alert, alertAt: _now());
      if (goAlertFelt(current, alert)) {
        feelGoAlert(alert);
        if (!_shown && goAlertRings(alert)) {
          ref.read(liveJourneyProvider).alert(alert.title, alert.body);
        }
      }
    }
    state = next;
    _trace?.progress(progress, input.now);
    _askPositions();
    _publishLive(next);
    _feelTurn(next);
    _matchVehicle(next);

    if (changed) {
      _save();
      // On board, the departures watched are the next ride's; back at the stop (a correction), this one's again
      if (progress.step != current.progress.step || progress.phase != current.progress.phase) {
        _watchDepartures();
      }
      _watchBoarded();
    }
    _replaceMissed(next);
    if (progress.phase == GoPhase.arrived) {
      _stopFeeds();
      _lastLive = null;
      ref.read(liveJourneyProvider).stop();
      // The summary stays a while, then the session ends on its own
      _closeTimer ??= Timer(_closeAfter, () {
        _closeTimer = null;
        if (state?.progress.phase == GoPhase.arrived) {
          stop();
        }
      });
    }
  }

  /// A missed or cancelled vehicle: the next departure of the line is taken on its own (another one can be chosen,
  /// or the journey recalculated), so that the user never has to act to know what to do next
  void _replaceMissed(GoState state) {
    final issue = state.progress.issue;
    final rides = _rides;
    final step = state.tracker.stepOf(state.progress);
    if (_retaining || (issue != GoIssue.missed && issue != GoIssue.cancelled) || step == null || !step.isRide ||
        rides == null || _departuresOf?.step != state.progress.step || _departuresOf?.tracker != state.tracker) {
      return;
    }
    final now = _now();
    final planned = state.tracker.expectedDeparture(step, state.progress, state.currentVehicle);
    final ride = replacementRide(rides, issue!, planned, now);
    if (ride == null) {
      return;
    }
    _retaining = true;
    choose(state.progress.step, ride, retained: true, cancelled: issue == GoIssue.cancelled).whenComplete(() => _retaining = false);
  }

  /// Progress in the system notification (Android), when its text changes or every 15 s of progress
  void _publishLive(GoState state) {
    if (state.progress.phase == GoPhase.arrived) {
      return;
    }
    final update = goLiveUpdate(state, _now());
    final key = '${update.title}|${update.status}|${update.chip}|${update.info}|${state.progress.step}';
    if (key == _lastLive && (update.progress - _lastLiveProgress).abs() < 15) {
      return;
    }
    _lastLive = key;
    _lastLiveProgress = update.progress;
    ref.read(liveJourneyProvider).update(update);
  }

  /// A turn of the walk close ahead (15 m): felt once, like a navigation app, unless muted
  void _feelTurn(GoState state) {
    final step = state.tracker.stepOf(state.progress);
    if (state.muted || step == null || state.progress.phase != GoPhase.moving) {
      return;
    }
    final maneuver = nextManeuver(step, state.progress.along);
    if (maneuver == null || maneuver.meters > 15) {
      return;
    }
    final key = '${state.progress.step}-${maneuver.walk.offset}';
    if (key != _turnFelt) {
      _turnFelt = key;
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 180), HapticFeedback.mediumImpact);
    }
  }

  /// Real-time departures of the next ride's line at its boarding stop: listened to from where the traveller gets
  /// there (checked every 30 s and at each step, as that time moves), the provider re-fetching them every 30 s
  void _watchDepartures() {
    final current = state;
    if (current == null) {
      return;
    }
    final progress = current.progress;
    // On board, the vehicle of the ride is known: look at the following ride
    final start = progress.phase == GoPhase.onBoard ? progress.step + 1 : progress.step;
    final steps = current.tracker.steps;
    final index = [for (var i = start; i < steps.length; i++) i].where((i) => steps[i].isRide).firstOrNull;
    final ride = index == null ? null : steps[index];
    final now = _now();
    final earliest = ride == null || index == progress.step
        ? now
        : earliestBoarding(current.journey, ride.sectionIndex, now).add(progress.shift);
    final key = ride == null ? null : rideKey(ride.section, earliest, now);
    if (ride == null || index == null || key == null) {
      _departures?.close();
      _departures = null;
      _departuresOf = null;
      state = current.copyWith(vehicle: () => null, vehicleStep: () => null, realtimeDepartures: false);
      return;
    }
    final of = (key: key, tracker: current.tracker, step: index);
    if (index == progress.step && progress.phase == GoPhase.waiting) {
      _boardKey = of;
    }
    if (of == _departuresOf) {
      return;
    }
    _departures?.close();
    _departuresOf = of;
    _rides = null;
    _departures = ref.listen(
      rideOptionsProvider(key),
      (_, departures) => _onDepartures(of, departures),
      fireImmediately: true,
    );
  }

  void _onDepartures(({RideKey key, GoTracker tracker, int step}) of, AsyncValue<List<Ride>> departures) {
    final rides = departures.value;
    final latest = state;
    if (departures.hasError) {
      debugPrint('GO departures unavailable: ${departures.error}');
    }
    if (rides == null || latest == null || latest.tracker != of.tracker) {
      return;
    }
    _rides = rides;
    _remember(of, rides, latest);
    // The planned vehicle: same scheduled time (a few minutes of tolerance); among departures of the same minute, the
    // one arriving when the ride does, as the departures card picks it (its mission is the card's header)
    final ride = of.tracker.steps[of.step];
    final vehicle = plannedRide(
      rides,
      of.tracker.plannedDeparture(ride, latest.progress),
      arrival: ride.section.arrival.add(latest.progress.shift),
    )?.departure;
    state = latest.copyWith(
      vehicle: () => vehicle,
      vehicleStep: () => of.step,
      realtimeDepartures: rides.any((ride) => ride.departure.realtime),
    );
  }

  /// The departures [rides] received for the ride of [of], the departed ones kept: those the user may be on
  void _remember(({RideKey key, GoTracker tracker, int step}) of, List<Ride> rides, GoState latest) {
    _trace?.rides(of.step, rides, _now());
    if (_seenFor != of.tracker) {
      _seen.clear();
      _seenFor = of.tracker;
    }
    final seen = _seen.putIfAbsent(of.step, () => []);
    for (final ride in rides) {
      final known = seen.indexWhere((other) => sameDeparture(other, ride));
      if (known >= 0) {
        seen[known] = ride;
      } else {
        seen.add(ride);
      }
    }
    final match = _match;
    if (match != null && match.step == of.step) {
      final progress = latest.progress;
      final ride = of.tracker.steps[of.step];
      // Down the line already: a vehicle still at the stop is not the user's
      final gone = progress.step == of.step && progress.phase == GoPhase.onBoard && progress.along > ride.platformZone.to;
      match.seen(rides, _now(), userGone: gone);
    }
  }

  /// After boarding, the departures of the ride taken a few minutes more (no request of their own: the ones waited for):
  /// the real time of the vehicles that left about then (a late one still at the platform) says which one the user is on
  void _watchBoarded() {
    final current = state;
    final progress = current?.progress;
    final departed = progress?.departedAt;
    final of = _boardKey;
    final keep = current != null && progress!.phase == GoPhase.onBoard && of != null && of.step == progress.step &&
        of.tracker == current.tracker && departed != null && _now().difference(departed) < _boardedWatch;
    if (!keep) {
      _boarded?.close();
      _boarded = null;
      if (progress?.phase != GoPhase.waiting) {
        _boardKey = null;
      }
      return;
    }
    _boarded ??= ref.listen(rideOptionsProvider(of.key), (_, departures) {
      final rides = departures.value;
      final latest = state;
      if (rides != null && latest != null) {
        _remember(of, rides, latest);
      }
    });
  }

  Future<void> _save() async {
    final current = state;
    if (current == null) {
      return;
    }
    await ref.read(localStoreProvider).writeJson(_storageKey, {
      'journey': current.journey.toJson(),
      'request': current.request.toQuery(),
      'progress': current.progress.toJson(),
      'startedAt': current.startedAt.toIso8601String(),
      'plannedArrival': current.plannedArrival.toIso8601String(),
      'muted': current.muted,
      'keepAwake': current.keepAwake,
      'alightOff': current.alightAlertsOff.toList(),
    });
  }

  /// Session kept on the device, unless it is over (30 min after the arrival, or finished from the notification while
  /// the app wasn't running)
  Future<void> _restore() async {
    final store = ref.read(localStoreProvider);
    if (await ref.read(liveJourneyProvider).stopRequested()) {
      await store.remove(_storageKey);
      return;
    }
    final json = await store.readJson(_storageKey);
    if (json is! Map<String, dynamic> || state != null) {
      return;
    }
    try {
      // Through JSON again: nested objects were stored with their toJson
      final journey = JourneyOption.fromJson(json['journey'] as Map<String, dynamic>);
      final progress = GoProgress.fromJson(json['progress'] as Map<String, dynamic>);
      final end = (progress.arrivedAt ?? journey.arrival.add(progress.shift)).add(const Duration(minutes: 30));
      if (_now().isAfter(end)) {
        await store.remove(_storageKey);
        return;
      }
      _begin(
        journey,
        JourneyRequest.fromQuery((json['request'] as Map).cast<String, String>()),
        muted: json['muted'] == true,
        keepAwake: json['keepAwake'] == true,
        plannedArrival: DateTime.tryParse(json['plannedArrival'] as String? ?? ''),
        progress: progress,
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
        alightAlertsOff: {...?(json['alightOff'] as List?)?.cast<int>()},
      );
      // Wherever the user got while the app was gone
      _relocateNext = true;
    } catch (e) {
      debugPrint('GO session unreadable: $e');
      await store.remove(_storageKey);
    }
  }
}

final goControllerProvider = NotifierProvider<GoController, GoState?>(GoController.new);

/// GO's clock: the device's, a simulated one in the tests and when a trace is played again
final goClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
