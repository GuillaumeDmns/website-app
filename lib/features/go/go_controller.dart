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
import '../../l10n/l10n.dart';
import '../auth/auth_controller.dart';
import '../journey/journey_providers.dart';
import '../journey/journey_request.dart';
import '../journey/journey_retime.dart';
import 'go_guidance.dart';
import 'go_live.dart';
import 'go_ride_guess.dart';
import 'go_smoother.dart';
import 'go_state.dart';
import 'go_tracker.dart';

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

/// GO session: feeds the [GoTracker] with high-accuracy positions (the app's [PositionFeed], asked as often as the
/// moment needs, [goLocationNeed]), a 5 s clock and the real-time departures of the next ride (`rideOptionsProvider`,
/// every 30 s, shared with the cards showing them), gives the alerts, and keeps the session on the device so that it
/// survives a restart. On board, the journey follows the vehicle guessed among the departures seen at the stop
/// ([RideGuess]).
class GoController extends Notifier<GoState?> {
  PositionFeed? _feed;
  StreamSubscription<Position>? _positions;
  Timer? _tick;
  Timer? _departuresTimer;
  Position? _lastFix;

  /// What the map shows of the fixes, redrawn ([GoSmoother.redrawInterval]) while it moves and the app is on screen
  final _smoother = GoSmoother();
  Timer? _smoothTimer;
  bool _shown = true;

  /// The user's pace on the moves (m/s), averaged over the fixes
  double? _walkSpeed;

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

  /// On board, which of them the user is on, and the journey being moved to it
  RideGuess? _guess;
  DateTime? _guessedFixAt;
  bool _following = false;

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
      _smoothen();
      _askPositions();
    });
    ref.onDispose(_stopFeeds);
    _restore();
    return null;
  }

  /// Starts following [journey]; [request] gives the destination and options to recalculate
  void start(JourneyOption journey, JourneyRequest? request) {
    ref.read(liveJourneyProvider).prepare();
    _begin(journey, _requestFor(journey, request), muted: state?.muted ?? false, keepAwake: state?.keepAwake ?? false);
  }

  void stop() {
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
    );
    _save();
    _watchDepartures();
    _update();
  }

  /// [current]'s journey with [ride] taken for the ride [step], the departures of the following rides fetched as the
  /// retiming asks for them
  Future<JourneyOption> _retimedWith(GoState current, int step, Ride ride) async {
    final sectionIndex = current.tracker.steps[step].sectionIndex;
    final api = ref.read(mobilityApiProvider);
    final now = DateTime.now();
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

  /// On board, the vehicle taken is guessed among the departures seen at the stop ([RideGuess]: the one that left when
  /// the user did, then checked at each station on the way): the journey follows it, without a word to the user
  void _guessRide(GoState state) {
    final progress = state.progress;
    if (progress.phase != GoPhase.onBoard) {
      _guess = null;
      return;
    }
    var guess = _guess;
    if (guess == null || guess.step != progress.step) {
      final ride = state.tracker.steps[progress.step];
      final seen = _seenFor == state.tracker ? _seen[progress.step] : null;
      guess = _guess = RideGuess.start(progress.step, ride, seen ?? const [], departed: ride.section.departure.add(progress.shift));
    }
    final fix = _lastFix;
    if (fix != null && fix.timestamp != _guessedFixAt) {
      _guessedFixAt = fix.timestamp;
      guess.observe(fix.timestamp, LatLng(fix.latitude, fix.longitude), speed: sureSpeed(fix), accuracy: fix.accuracy);
    }
    final better = guess.better;
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
    final departed = latest.tracker.steps[step].section.departure.add(latest.progress.shift);
    final tracker = GoTracker(journey);
    state = latest.copyWith(tracker: tracker, progress: tracker.onAnotherVehicle(latest.progress, departed));
    _guess?.follow(ride);
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
  }) {
    _closeTimer?.cancel();
    _closeTimer = null;
    _walkSpeed = null;
    _turnFelt = null;
    final tracker = GoTracker(journey);
    state = GoState(
      tracker: tracker,
      request: request,
      progress: progress ?? tracker.initial(),
      startedAt: startedAt ?? DateTime.now(),
      plannedArrival: plannedArrival ?? journey.arrival,
      muted: muted,
      keepAwake: keepAwake,
    );
    ref.read(liveJourneyProvider).keepScreenOn(keepAwake);
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
    _positions = feed.fixes.listen(_onFix, onError: (Object e) => debugPrint('GO positions unavailable: $e'));
    _askPositions();
    unawaited(_seed());
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _update());
    _departuresTimer = Timer.periodic(const Duration(seconds: 30), (_) => _watchDepartures());
    _watchDepartures();
    _update();
  }

  void _onFix(Position position) {
    _lastFix = position;
    final now = DateTime.now();
    ref.read(goFixStatsProvider.notifier).record(now, position.accuracy);
    final current = state;
    final step = current?.tracker.stepOf(current.progress);
    final speed = sureSpeed(position);
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
    if (known != null && DateTime.now().difference(known.timestamp) < const Duration(minutes: 1)) {
      _onFix(known);
      return;
    }
    final position = ref.read(userLocationProvider).value;
    if (position != null) {
      _onFix(Position(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
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
    final position = _smoother.at(DateTime.now());
    if (position != null) {
      ref.read(preciseUserPositionProvider.notifier).set(position);
    }
    if (_smoothTimer != null || !_shown || !_smoother.moving(DateTime.now())) {
      return;
    }
    _smoothTimer = Timer(_smoother.redrawInterval, () {
      _smoothTimer = null;
      _smoothen();
    });
  }

  void _stopFeeds() {
    _lastFix = null;
    // Not during a build: providers can't be modified while widgets build
    Future.microtask(() {
      try {
        ref.read(preciseUserPositionProvider.notifier).set(null);
        ref.read(goFixStatsProvider.notifier).clear();
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
    _guess = null;
    _recalculateTimer?.cancel();
    _recalculateTimer = null;
  }

  void _update() {
    final current = state;
    if (current == null) {
      return;
    }
    final fix = _lastFix;
    final position = fix == null ? null : LatLng(fix.latitude, fix.longitude);
    final input = GoInput(
      now: DateTime.now(),
      position: position,
      accuracy: fix?.accuracy,
      speed: fix == null ? null : sureSpeed(fix),
      fixAt: fix?.timestamp,
      vehicle: current.vehicle,
      vehicleStep: current.vehicleStep,
      realtimeDepartures: current.realtimeDepartures,
    );
    final (progress, alerts) = current.tracker.update(current.progress, input);

    final changed = progress.step != current.progress.step ||
        progress.phase != current.progress.phase ||
        progress.stopIndex != current.progress.stopIndex ||
        progress.issue != current.progress.issue ||
        progress.fired.length != current.progress.fired.length;

    if (progress.step != current.progress.step) {
      // A new move: its own pace (on foot after a bike, say)
      _walkSpeed = null;
    }
    var next = current.copyWith(progress: progress, position: position, walkSpeed: _walkSpeed);
    // The vehicle kept on its own is said until the user is on board (or elsewhere)
    if (current.retained case final retained?
        when progress.step != retained.step || progress.phase != GoPhase.waiting) {
      next = next.copyWith(retained: () => null);
    }
    // Off the way: recalculated on its own after a countdown; back on it, nothing to do
    if (progress.issue == GoIssue.offRoute && current.progress.issue != GoIssue.offRoute && !current.recalculating) {
      _recalculateTimer?.cancel();
      _recalculateTimer = Timer(_recalculateAfter, recalculate);
      next = next.copyWith(recalculateAt: () => DateTime.now().add(_recalculateAfter));
    } else if (progress.issue != GoIssue.offRoute && current.recalculateAt != null) {
      _recalculateTimer?.cancel();
      _recalculateTimer = null;
      next = next.copyWith(recalculateAt: () => null);
    }
    if (alerts.isNotEmpty) {
      final alert = alerts.last;
      next = next.copyWith(alert: alert, alertAt: DateTime.now());
      if (!current.muted) {
        final live = ref.read(liveJourneyProvider);
        if (!live.systemAlerts) {
          feelGoAlert(alert);
        }
        // Web: a notification when the tab is hidden
        live.alert(alert.title, alert.body ?? '', urgent: alert.urgent, kind: alert.kind);
      }
    }
    state = next;
    _askPositions();
    _publishLive(next);
    _feelTurn(next);
    _guessRide(next);

    if (changed) {
      _save();
      // On board, the departures watched are the next ride's; back at the stop (a correction), this one's again
      if (progress.step != current.progress.step || progress.phase != current.progress.phase) {
        _watchDepartures();
      }
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
    final now = DateTime.now();
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
    final update = goLiveUpdate(state, DateTime.now());
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
    final now = DateTime.now();
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
    // The planned vehicle: same scheduled time (a few minutes of tolerance)
    final ride = of.tracker.steps[of.step];
    final vehicle = plannedRide(rides, of.tracker.plannedDeparture(ride, latest.progress))?.departure;
    state = latest.copyWith(
      vehicle: () => vehicle,
      vehicleStep: () => of.step,
      realtimeDepartures: rides.any((ride) => ride.departure.realtime),
    );
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
    });
  }

  /// Session kept on the device, unless it is over (30 min after the arrival)
  Future<void> _restore() async {
    final store = ref.read(localStoreProvider);
    final json = await store.readJson(_storageKey);
    if (json is! Map<String, dynamic> || state != null) {
      return;
    }
    try {
      // Through JSON again: nested objects were stored with their toJson
      final journey = JourneyOption.fromJson(json['journey'] as Map<String, dynamic>);
      final progress = GoProgress.fromJson(json['progress'] as Map<String, dynamic>);
      final end = (progress.arrivedAt ?? journey.arrival.add(progress.shift)).add(const Duration(minutes: 30));
      if (DateTime.now().isAfter(end)) {
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
      );
    } catch (e) {
      debugPrint('GO session unreadable: $e');
      await store.remove(_storageKey);
    }
  }
}

final goControllerProvider = NotifierProvider<GoController, GoState?>(GoController.new);
