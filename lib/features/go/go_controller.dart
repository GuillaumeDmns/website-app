import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../../core/platform/live_journey.dart';
import '../../core/storage/local_store.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import '../auth/auth_controller.dart';
import '../journey/journey_request.dart';
import '../journey/journey_retime.dart';
import 'go_instruction.dart';
import 'go_tracker.dart';

const _storageKey = 'go_session';

/// A journey followed in GO mode
@immutable
class GoState {
  const GoState({
    required this.tracker,
    required this.request,
    required this.progress,
    required this.startedAt,
    required this.plannedArrival,
    this.muted = false,
    this.keepAwake = false,
    this.position,
    this.vehicle,
    this.vehicleStep,
    this.alert,
    this.alertAt,
    this.recalculating = false,
    this.error,
  });

  final GoTracker tracker;

  /// Destination and options, to recalculate
  final JourneyRequest request;
  final GoProgress progress;
  final DateTime startedAt;

  /// Arrival planned when GO was started (kept through recalculations and departures chosen), for the arrival summary
  final DateTime plannedArrival;

  /// No sound nor vibration for the alerts
  final bool muted;

  /// The screen stays on
  final bool keepAwake;

  /// Last position fix
  final LatLng? position;

  /// Real-time departure of the planned vehicle of the ride [vehicleStep] (the next one)
  final Departure? vehicle;
  final int? vehicleStep;

  /// Last alert given, and when
  final GoAlert? alert;
  final DateTime? alertAt;
  final bool recalculating;

  /// Last recalculation failure
  final String? error;

  JourneyOption get journey => tracker.journey;

  /// Vehicle of the current ride (null when the next ride is not the current step)
  Departure? get currentVehicle => vehicleStep == progress.step ? vehicle : null;

  GoState copyWith({
    GoProgress? progress,
    bool? muted,
    bool? keepAwake,
    LatLng? position,
    Departure? Function()? vehicle,
    int? Function()? vehicleStep,
    GoAlert? alert,
    DateTime? alertAt,
    bool? recalculating,
    String? Function()? error,
  }) =>
      GoState(
        tracker: tracker,
        request: request,
        progress: progress ?? this.progress,
        startedAt: startedAt,
        plannedArrival: plannedArrival,
        muted: muted ?? this.muted,
        keepAwake: keepAwake ?? this.keepAwake,
        position: position ?? this.position,
        vehicle: vehicle != null ? vehicle() : this.vehicle,
        vehicleStep: vehicleStep != null ? vehicleStep() : this.vehicleStep,
        alert: alert ?? this.alert,
        alertAt: alertAt ?? this.alertAt,
        recalculating: recalculating ?? this.recalculating,
        error: error != null ? error() : this.error,
      );
}

/// GO session: feeds the [GoTracker] with high-accuracy positions, a 5 s clock and the real-time departures of the
/// next ride (every 30 s), gives the alerts, and keeps the session on the device so that it survives a restart.
class GoController extends Notifier<GoState?> {
  StreamSubscription<Position>? _positions;
  Timer? _tick;
  Timer? _departuresTimer;
  Position? _lastFix;

  /// Last content sent to the system notification, to only send changes
  String? _lastLive;
  int _lastLiveProgress = -1;
  bool _loadingDepartures = false;

  @override
  GoState? build() {
    ref.listen(authControllerProvider, (previous, status) {
      if (status == AuthStatus.signedOut) {
        _stopFeeds();
        state = null;
      }
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
    _stopFeeds();
    state = null;
    _lastLive = null;
    ref.read(liveJourneyProvider).stop();
    ref.read(localStoreProvider).remove(_storageKey);
  }

  void next() => _setProgress((tracker, progress) => tracker.next(progress));

  void jumpTo(int step) => _setProgress((tracker, progress) => tracker.jumpTo(progress, step));

  void dismissIssue() => _setProgress((tracker, progress) => tracker.dismissIssue(progress));

  /// Takes [ride] for the ride [step] (in progress or to come) instead of the planned departure (missed, cancelled,
  /// or another one preferred): the journey moves to it from there, the following connections included.
  Future<void> choose(int step, Ride ride) async {
    final current = state;
    if (current == null || step < current.progress.step || step >= current.tracker.steps.length) {
      return;
    }
    final sectionIndex = current.tracker.steps[step].sectionIndex;
    final api = ref.read(mobilityApiProvider);
    final now = DateTime.now();

    // Departures of the following rides, fetched as the retiming asks for them
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

    final latest = state;
    if (latest == null || latest.tracker != current.tracker) {
      return;
    }
    var journey = retimed.journey;
    final progress = latest.progress;
    if (step > progress.step && progress.shift != Duration.zero) {
      // The current ride's lateness still applies to what follows it: the chosen times are kept as they are
      journey = shiftJourney(journey, from: sectionIndex, by: -progress.shift);
    }
    final tracker = GoTracker(journey);
    state = GoState(
      tracker: tracker,
      request: latest.request,
      progress: tracker.chosen(progress, step),
      startedAt: latest.startedAt,
      plannedArrival: latest.plannedArrival,
      muted: latest.muted,
      keepAwake: latest.keepAwake,
      position: latest.position,
    );
    _save();
    _loadDepartures();
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

    state = current.copyWith(recalculating: true, error: () => null);
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
    _update();
  }

  void _startFeeds() {
    _stopFeeds();
    _positions = Geolocator.getPositionStream(locationSettings: _locationSettings()).listen(
      (position) {
        _lastFix = position;
        _update();
      },
      onError: (Object e) => debugPrint('GO positions unavailable: $e'),
    );
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _update());
    _departuresTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadDepartures());
    _loadDepartures();
    _update();
  }

  /// Regular fixes even when not moving: a user waiting at a stop must not look like one without GPS (underground)
  static LocationSettings _locationSettings() {
    if (kIsWeb) {
      return WebSettings(accuracy: LocationAccuracy.best, distanceFilter: 0, maximumAge: Duration.zero);
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 2),
        ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          activityType: ActivityType.otherNavigation,
          pauseLocationUpdatesAutomatically: false,
        ),
      _ => const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0),
    };
  }

  void _stopFeeds() {
    _lastFix = null;
    Future.microtask(() {
      try {
        ref.read(preciseUserPositionProvider.notifier).set(null);
      } catch (_) {
        // Disposed
      }
    });
    _positions?.cancel();
    _positions = null;
    _tick?.cancel();
    _tick = null;
    _departuresTimer?.cancel();
    _departuresTimer = null;
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
      speed: fix == null || fix.speed < 0 ? null : fix.speed,
      fixAt: fix?.timestamp,
      vehicle: current.vehicle,
      vehicleStep: current.vehicleStep,
    );
    final (progress, alerts) = current.tracker.update(current.progress, input);

    final changed = progress.step != current.progress.step ||
        progress.phase != current.progress.phase ||
        progress.stopIndex != current.progress.stopIndex ||
        progress.issue != current.progress.issue ||
        progress.fired.length != current.progress.fired.length;

    var next = current.copyWith(progress: progress, position: position);
    if (alerts.isNotEmpty) {
      final alert = alerts.last;
      next = next.copyWith(alert: alert, alertAt: DateTime.now());
      if (!current.muted) {
        final live = ref.read(liveJourneyProvider);
        if (!live.systemAlerts) {
          _signal(alert);
        }
        // Web: a notification when the tab is hidden
        live.alert(alert.title, alert.body ?? '', urgent: alert.urgent);
      }
    }
    state = next;
    _publishLive(next);
    if (position != null) {
      ref.read(preciseUserPositionProvider.notifier).set(position);
    }

    if (changed) {
      _save();
      if (progress.step != current.progress.step) {
        _loadDepartures();
      }
    }
    if (progress.phase == GoPhase.arrived) {
      _stopFeeds();
      _lastLive = null;
      ref.read(liveJourneyProvider).stop();
    }
  }

  /// Progress in the system notification (Android), when its text changes or every 15 s of progress
  void _publishLive(GoState state) {
    if (state.progress.phase == GoPhase.arrived) {
      return;
    }
    final now = DateTime.now();
    final instruction = goInstruction(state, now);
    final tracker = state.tracker;
    final progress = state.progress;
    final step = tracker.stepOf(progress);

    var done = 0;
    for (var i = 0; i < progress.step && i < tracker.steps.length; i++) {
      done += tracker.steps[i].section.duration;
    }
    if (step != null) {
      final fraction = switch (progress.phase) {
        GoPhase.moving => step.line.length == 0 ? 0.0 : progress.along / step.line.length,
        GoPhase.onBoard => step.section.stops.length < 2 ? 0.5 : progress.stopIndex / (step.section.stops.length - 1),
        _ => 0.0,
      };
      done += (step.section.duration * fraction.clamp(0.0, 1.0)).round();
    }

    final chip = switch (progress.phase) {
      GoPhase.onBoard =>
        tracker.stopsLeft(progress) <= 1 ? currentL10n.goChipGetOff : currentL10n.stopsCount(tracker.stopsLeft(progress)),
      GoPhase.waiting when step != null =>
        currentL10n.minutesShort(
            (tracker.expectedDeparture(step, progress, state.currentVehicle).difference(now).inSeconds / 60).ceil().clamp(0, 999)),
      _ => currentL10n.minutesShort((tracker.metersLeft(progress) / 1.2 / 60).ceil()),
    };
    final info = currentL10n.goArrival(formatClock(tracker.eta(progress, state.currentVehicle)));
    final key = '${instruction.title}|${instruction.subtitle}|$chip|$info|${progress.step}';
    if (key == _lastLive && (done - _lastLiveProgress).abs() < 15) {
      return;
    }
    _lastLive = key;
    _lastLiveProgress = done;

    final section = step?.section;
    final mode = section == null
        ? 'walk'
        : section.kind == SectionKind.transit
            ? switch (section.line?.mode) {
                TransportMode.metro => 'metro',
                TransportMode.rer || TransportMode.transilien || TransportMode.ter => 'train',
                TransportMode.tram => 'tram',
                _ => 'bus',
              }
            : section.kind == SectionKind.transfer
                ? 'transfer'
                : 'walk';

    ref.read(liveJourneyProvider).update(LiveJourneyUpdate(
          title: instruction.title,
          status: instruction.subtitle ?? '',
          progress: done,
          mode: mode,
          chip: chip,
          info: info,
          segments: [
            for (final goStep in tracker.steps)
              LiveJourneySegment(
                seconds: goStep.section.duration,
                color: goStep.isRide && goStep.section.line?.color != null ? '#${goStep.section.line!.color}' : '#9E9E9E',
              ),
          ],
        ));
  }

  static void _signal(GoAlert alert) {
    SystemSound.play(SystemSoundType.alert);
    if (alert.urgent) {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 300), HapticFeedback.heavyImpact);
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  /// Real-time departures of the next ride's line at its boarding stop
  Future<void> _loadDepartures() async {
    final current = state;
    if (current == null || _loadingDepartures) {
      return;
    }
    final progress = current.progress;
    // On board, the vehicle of the ride is known: look at the following ride
    final start = progress.phase == GoPhase.onBoard ? progress.step + 1 : progress.step;
    final steps = current.tracker.steps;
    final index = [for (var i = start; i < steps.length; i++) i].where((i) => steps[i].isRide).firstOrNull;
    final ride = index == null ? null : steps[index];
    final from = ride?.section.from?.stopAreaId;
    final to = ride?.section.to?.stopAreaId;
    final lineId = ride?.section.line?.id;
    if (ride == null || from == null || to == null || lineId == null || lineId.isEmpty) {
      state = current.copyWith(vehicle: () => null, vehicleStep: () => null);
      return;
    }

    _loadingDepartures = true;
    try {
      final now = DateTime.now();
      final earliest = index == progress.step ? now : earliestBoarding(current.journey, ride.sectionIndex, now).add(progress.shift);
      final key = rideKey(ride.section, earliest, now)!;
      final rides = await ref.read(mobilityApiProvider).lineRides(lineId, from: from, to: to, after: key.after, limit: 8);
      final latest = state;
      if (latest == null || latest.tracker != current.tracker) {
        return;
      }
      // The planned vehicle: same scheduled time (a few minutes of tolerance)
      final vehicle = plannedRide(rides, current.tracker.plannedDeparture(ride, latest.progress))?.departure;
      state = latest.copyWith(vehicle: () => vehicle, vehicleStep: () => index);
    } catch (e) {
      debugPrint('GO departures unavailable: $e');
    } finally {
      _loadingDepartures = false;
    }
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
