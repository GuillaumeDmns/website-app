import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/models.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';

/// Step followed in GO mode: a ride (wait at the stop, then on board) or a move (walk, transfer, bike…).
class GoStep {
  GoStep._(this.section, this.sectionIndex, this.line, this.stopAlongs);

  factory GoStep(JourneySection section, int sectionIndex) {
    final line = MeasuredPolyline(sectionPath(section));

    // Position of each served stop along the path, in order
    final stopAlongs = <double>[];
    var minAlong = 0.0;
    for (final stop in section.stops) {
      final along = line.project(LatLng(stop.lat, stop.lon), minAlong: minAlong)?.along ?? minAlong;
      stopAlongs.add(along);
      minAlong = along;
    }
    return GoStep._(section, sectionIndex, line, stopAlongs);
  }

  final JourneySection section;

  /// Index in the journey's sections
  final int sectionIndex;
  final MeasuredPolyline line;

  /// Ride: meters from the start of [line] to each stop of `section.stops`
  final List<double> stopAlongs;

  bool get isRide => section.kind == SectionKind.transit;

  LatLng? get end => section.to == null ? null : LatLng(section.to!.lat, section.to!.lon);

  LatLng? get start => section.from == null ? null : LatLng(section.from!.lat, section.from!.lon);

  /// Where to head from [position] on a move: the path [_aheadMeters] after where the user is along it (so a user
  /// beside the path still heads along it, and one away from it heads back to it), else the last stretch of the path.
  /// [along] is the progress known so far. Degrees clockwise from north.
  double headingFrom(LatLng position, double along) {
    if (line.points.length < 2) {
      final end = this.end;
      return end == null ? 0 : bearingBetween(position, end);
    }
    // GPS a little beside the path: where it is along it now, never back from the progress known
    final projection = line.project(position, minAlong: math.max(0, along - 50));
    final here = projection != null && projection.distance < 60 ? math.max(along, projection.along) : along;
    final ahead = line.pointAt(math.min(line.length, here + _aheadMeters));
    if (metersBetween(position, ahead) >= 5) {
      return bearingBetween(position, ahead);
    }
    return bearingBetween(line.pointAt(math.max(0, line.length - 15)), line.points.last);
  }

  static const _aheadMeters = 30.0;

  /// Ride: meters along it where its vehicle may stand at the boarding stop with the user in it: from a little before the
  /// stop's point to a vehicle's length after it, since the stop's point may be at the head of the platform (a terminus'
  /// always is) and the user anywhere in a 450 m double train. Someone standing still there is waiting, on the platform
  /// or already seated: never seen leaving.
  ({double from, double to}) get platformZone {
    final at = stopAlongs.isEmpty ? 0.0 : stopAlongs.first;
    return (from: at - 150, to: at + platformLength);
  }

  double get platformLength => switch (section.line?.mode) {
        TransportMode.rer || TransportMode.transilien || TransportMode.ter => 450,
        TransportMode.metro => 150,
        TransportMode.tram => 80,
        _ => 40,
      };

  /// Ride: the fastest its vehicle goes (m/s), to bound how far the clock may take the user from where the GPS last saw
  /// them
  double get topSpeed => switch (section.line?.mode) {
        TransportMode.rer || TransportMode.transilien || TransportMode.ter => 40,
        TransportMode.metro => 22,
        _ => 15,
      };

  /// Ride: where [fix] is on the boarding stop's platform zone (meters along), null when elsewhere
  double? alongInPlatformZone(LatLng fix, double accuracy) {
    final projection = line.project(fix);
    final zone = platformZone;
    if (projection == null || projection.distance > 100 + accuracy || projection.along < zone.from || projection.along > zone.to) {
      return null;
    }
    return projection.along;
  }

  /// Ride: index of the stop whose point is closest to [fix] within [meters], null when none is
  int? stopNear(LatLng fix, double meters) {
    int? closest;
    var best = meters;
    for (final (index, stop) in section.stops.indexed) {
      final distance = metersBetween(fix, LatLng(stop.lat, stop.lon));
      if (distance <= best) {
        best = distance;
        closest = index;
      }
    }
    return closest;
  }

  /// Ride: scheduled time at [along] meters along it
  DateTime scheduledAt(double along) => stopTime(0).add(scheduledTo(along));

  /// Ride: scheduled time from its first stop to [along] meters along it, between the times of the stops around
  Duration scheduledTo(double along) {
    if (stopAlongs.length < 2) {
      final share = line.length <= 0 ? 0.0 : (along / line.length).clamp(0.0, 1.0);
      return section.arrival.difference(section.departure) * share;
    }
    var k = 0;
    while (k < stopAlongs.length - 2 && stopAlongs[k + 1] < along) {
      k++;
    }
    final span = stopAlongs[k + 1] - stopAlongs[k];
    final share = span <= 0 ? 1.0 : ((along - stopAlongs[k]) / span).clamp(0.0, 1.0);
    final from = stopTime(k);
    return from.add(stopTime(k + 1).difference(from) * share).difference(stopTime(0));
  }

  /// Scheduled time at each stop, interpolated where the journey has none
  DateTime stopTime(int index) {
    final stops = section.stops;
    final time = index < stops.length ? stops[index].time : null;
    if (time != null) {
      return time;
    }
    if (stops.length < 2) {
      return index == 0 ? section.departure : section.arrival;
    }
    final total = section.arrival.difference(section.departure);
    return section.departure.add(total * (index / (stops.length - 1)));
  }
}

enum GoPhase {
  /// Walking (or other move) towards the end of the step
  moving,

  /// At the stop, the vehicle is coming
  waiting,

  /// In the vehicle
  onBoard,
  arrived,
}

/// Problem that needs the user: the tracker never changes the journey on its own
enum GoIssue {
  /// Away from the walking path for a while
  offRoute,

  /// The planned vehicle left while the user was still at the stop
  missed,

  /// The planned vehicle is cancelled
  cancelled,
}

/// Progress in a journey. Only moves forward on its own; the user can move it both ways.
@immutable
class GoProgress {
  const GoProgress({
    required this.step,
    required this.phase,
    this.along = 0,
    this.stopIndex = 0,
    this.shift = Duration.zero,
    this.issue,
    this.offRouteSince,
    this.lastFixAt,
    this.fired = const {},
    this.arrivedAt,
    this.preciseAlong,
    this.preciseAt,
    this.joined = false,
    this.stopFloor = 0,
    this.departedAt,
    this.byClock = false,
    this.seenStep,
    this.preciseFixAt,
    this.hintStop = 0,
    this.pendingHintStop,
  });

  /// Index in [GoTracker.steps]
  final int step;
  final GoPhase phase;

  /// Meters done along the current step's path
  final double along;

  /// On board: meters along the ride where the last precise fix (the GPS's) put the user, never back, and when that
  /// position was first given; null without one since boarding (underground)
  final double? preciseAlong;
  final DateTime? preciseAt;

  /// Ride: index of the last stop the vehicle has left (0 = the boarding stop); the alighting stop once there
  final int stopIndex;

  /// How late the user is on the schedule from the current ride on: real departure of the vehicle taken (delay,
  /// later vehicle) minus the planned one
  final Duration shift;
  final GoIssue? issue;
  final DateTime? offRouteSince;

  /// Last usable position fix (accurate enough)
  final DateTime? lastFixAt;

  /// Alerts already given (ids), never repeated
  final Set<String> fired;
  final DateTime? arrivedAt;

  /// Moving: the user was seen on the step's path (a move starts off it out of a train: on its platform, hundreds of
  /// meters from where the walk is drawn from)
  final bool joined;

  /// On board: the last stop the GPS saw the vehicle leave (or the user said they were past): the clock never takes the
  /// user back before it
  final int stopFloor;

  /// When the vehicle the user is on left the boarding stop (seen leaving, or assumed then), null before boarding
  final DateTime? departedAt;

  /// The current step (or phase) was reached by the clock or an assumption, not seen by the GPS nor said by the user:
  /// a precise fix may still put the user back where they really are (still on board the ride before, say)
  final bool byClock;

  /// With [byClock], the last step the GPS (or the user) put the user on before the clock took them further: a precise
  /// fix back there takes them back to it. Null when unknown (taken up after a restart): one step back at most.
  final int? seenStep;

  /// When the last precise fix came (the GPS's, outdoors), wherever it put the user: the GPS working, they are not
  /// underground
  final DateTime? preciseFixAt;

  /// On board underground: the last stop a rough position was taken as a sign of being at ([stopFloor]'s like for
  /// hints), and a stop further back than the clock waiting for a second hint to confirm it
  final int hintStop;
  final int? pendingHintStop;

  GoProgress copyWith({
    int? step,
    GoPhase? phase,
    double? along,
    int? stopIndex,
    Duration? shift,
    GoIssue? Function()? issue,
    DateTime? Function()? offRouteSince,
    DateTime? lastFixAt,
    Set<String>? fired,
    DateTime? arrivedAt,
    double? Function()? preciseAlong,
    DateTime? Function()? preciseAt,
    bool? joined,
    int? stopFloor,
    DateTime? Function()? departedAt,
    bool? byClock,
    int? Function()? seenStep,
    DateTime? preciseFixAt,
    int? hintStop,
    int? Function()? pendingHintStop,
  }) =>
      GoProgress(
        step: step ?? this.step,
        phase: phase ?? this.phase,
        along: along ?? this.along,
        stopIndex: stopIndex ?? this.stopIndex,
        shift: shift ?? this.shift,
        issue: issue != null ? issue() : this.issue,
        offRouteSince: offRouteSince != null ? offRouteSince() : this.offRouteSince,
        lastFixAt: lastFixAt ?? this.lastFixAt,
        fired: fired ?? this.fired,
        arrivedAt: arrivedAt ?? this.arrivedAt,
        preciseAlong: preciseAlong != null ? preciseAlong() : this.preciseAlong,
        preciseAt: preciseAt != null ? preciseAt() : this.preciseAt,
        joined: joined ?? this.joined,
        stopFloor: stopFloor ?? this.stopFloor,
        departedAt: departedAt != null ? departedAt() : this.departedAt,
        byClock: byClock ?? this.byClock,
        seenStep: seenStep != null ? seenStep() : this.seenStep,
        preciseFixAt: preciseFixAt ?? this.preciseFixAt,
        hintStop: hintStop ?? this.hintStop,
        pendingHintStop: pendingHintStop != null ? pendingHintStop() : this.pendingHintStop,
      );

  Map<String, dynamic> toJson() => {
        'step': step,
        'phase': phase.name,
        'along': along,
        'stopIndex': stopIndex,
        'shift': shift.inSeconds,
        'issue': issue?.name,
        'fired': fired.toList(),
        if (arrivedAt != null) 'arrivedAt': arrivedAt!.toIso8601String(),
        'stopFloor': stopFloor,
        if (departedAt != null) 'departedAt': departedAt!.toIso8601String(),
        'byClock': byClock,
      };

  factory GoProgress.fromJson(Map<String, dynamic> json) => GoProgress(
        step: json['step'] as int? ?? 0,
        phase: GoPhase.values.asNameMap()[json['phase']] ?? GoPhase.moving,
        along: (json['along'] as num?)?.toDouble() ?? 0,
        stopIndex: json['stopIndex'] as int? ?? 0,
        shift: Duration(seconds: json['shift'] as int? ?? 0),
        issue: GoIssue.values.asNameMap()[json['issue']],
        fired: {...?(json['fired'] as List?)?.cast<String>()},
        arrivedAt: DateTime.tryParse(json['arrivedAt'] as String? ?? ''),
        stopFloor: json['stopFloor'] as int? ?? 0,
        departedAt: DateTime.tryParse(json['departedAt'] as String? ?? ''),
        // Taken up after a restart: wherever the user is now, the GPS says it
        byClock: json['byClock'] as bool? ?? true,
      );
}

/// What the tracker knows at an update
class GoInput {
  const GoInput({
    required this.now,
    this.position,
    this.accuracy,
    this.speed,
    this.fixAt,
    this.vehicle,
    this.vehicleStep,
    this.realtimeDepartures = false,
    this.relocate = false,
  });

  final DateTime now;
  final LatLng? position;

  /// Meters
  final double? accuracy;

  /// Meters per second
  final double? speed;
  final DateTime? fixAt;

  /// Real-time departure of the planned vehicle at the boarding stop of the ride [vehicleStep], when found
  final Departure? vehicle;
  final int? vehicleStep;

  /// The departures of the ride [vehicleStep] come with real time (see [GoState.realtimeDepartures])
  final bool realtimeDepartures;

  /// The position may be anywhere on the journey, not only where the progress was: the first fix after the location was
  /// turned off, a restart, or minutes without a precise one (see [GoTracker.update])
  final bool relocate;

  Departure? vehicleOf(int step) => vehicleStep == step ? vehicle : null;
}

class GoAlert {
  const GoAlert({required this.id, required this.title, this.body, this.urgent = false});

  /// Unique per journey (e.g. `alight-3`): each alert is given once
  final String id;
  final String title;
  final String? body;

  /// Time to act now (get off, vehicle leaving)
  final bool urgent;

  /// How it is felt (vibration): `prepare` (two short), `alight` (long, repeated), `platform` (one short), `urgent`,
  /// else `info`
  String get kind => switch (id.split('-').first) {
        'prepare' => 'prepare',
        'alight' => 'alight',
        'platform' => 'platform',
        _ => urgent ? 'urgent' : 'info',
      };
}

/// Follows a journey from positions, the clock and real time. Pure: [update] returns the new progress and the
/// alerts to give.
///
/// - Moving: position projected on the path; done near its end, or on schedule without a position (underground); the
///   journey's last move only right by the destination ([_atDestination]).
/// - Waiting: boarding detected when moving fast along the line, or seen far along it whatever the speed (back from a
///   tunnel) (the vehicle taken left when it is seen to, when that is far from the departure expected: a late one, an
///   earlier one), or assumed after the departure without a precise position; still at the stop 90 s after the
///   departure by a precise fix means the vehicle was missed (3 min after one only scheduled, often a few minutes
///   late). Underground, the network's positions, or the last one given again, stay at the station while the vehicle
///   takes the user away: they never say a vehicle was missed.
/// - On board: stop reached from the position on the line, or from the stop times (+ shift) without one or with only
///   rough ones; where the user is between two stops likewise ([betweenStops]).
class GoTracker {
  GoTracker(this.journey) : steps = _steps(journey);

  final JourneyOption journey;
  final List<GoStep> steps;

  static const _maxAccuracy = 100.0;
  static const _fixValidity = Duration(seconds: 30);

  /// A fix this precise is the GPS's, outdoors: only such a fix says the user is still at a stop, or alone where they
  /// are on board. The network's (Wi-Fi, cell towers), the only ones underground, are rougher.
  static const _preciseAccuracy = 30.0;

  /// Without a fix for this long, the schedule leads
  static const _noFixDelay = Duration(seconds: 60);

  static List<GoStep> _steps(JourneyOption journey) => [
        for (final (index, section) in journey.sections.indexed)
          if (section.kind != SectionKind.wait && section.from != null && section.to != null) GoStep(section, index),
      ];

  LatLng? get destination {
    final to = journey.sections.lastOrNull?.to;
    return to == null ? null : LatLng(to.lat, to.lon);
  }

  GoProgress initial() => GoProgress(step: 0, phase: steps.isEmpty ? GoPhase.arrived : _phaseOf(0));

  GoPhase _phaseOf(int step) => steps[step].isRide ? GoPhase.waiting : GoPhase.moving;

  GoStep? stepOf(GoProgress progress) => progress.step < steps.length ? steps[progress.step] : null;

  /// Planned departure of a ride, shifted when the user takes a later vehicle
  DateTime plannedDeparture(GoStep ride, GoProgress progress) => ride.section.departure.add(progress.shift);

  /// Expected departure of the vehicle: real time when known
  DateTime expectedDeparture(GoStep ride, GoProgress progress, Departure? vehicle) =>
      vehicle?.time ?? plannedDeparture(ride, progress);

  /// Estimated arrival at the destination; [vehicle]: real-time departure of the current ride's vehicle. With no ride
  /// left to take, the moves alone say when: [secondsToGo] on the one in progress (at the user's pace) from [now],
  /// then the ones after it as planned.
  DateTime eta(GoProgress progress, Departure? vehicle, {DateTime? now, double? secondsToGo}) {
    if (progress.arrivedAt != null) {
      return progress.arrivedAt!;
    }
    if (now != null && secondsToGo != null && progress.phase == GoPhase.moving && progress.step < steps.length &&
        steps.skip(progress.step).every((step) => !step.isRide)) {
      final after = steps.skip(progress.step + 1).fold(0, (seconds, step) => seconds + step.section.duration);
      return now.add(Duration(seconds: secondsToGo.round() + after));
    }
    // The rides' times as the API gives them: the delay GO measures itself on board is never shown
    var delay = Duration.zero;
    final step = stepOf(progress);
    if (step != null && step.isRide && progress.phase == GoPhase.waiting) {
      // Not left yet: at least the time until the vehicle leaves (missed: the next one, at least now)
      final departure = expectedDeparture(step, progress, vehicle);
      final current = now ?? DateTime.now();
      final leaves = departure.isBefore(current) ? current : departure;
      delay += leaves.difference(plannedDeparture(step, progress));
    }
    return journey.arrival.add(delay);
  }

  /// Stops left before getting off (current ride)
  int stopsLeft(GoProgress progress) {
    final step = stepOf(progress);
    if (step == null || !step.isRide) {
      return 0;
    }
    return math.max(0, step.section.stops.length - 1 - progress.stopIndex);
  }

  /// Meters left on the current step's path
  double metersLeft(GoProgress progress) {
    final step = stepOf(progress);
    return step == null ? 0 : math.max(0, step.line.length - progress.along);
  }

  /// On board, where the user is between the last stop left ([GoProgress.stopIndex]) and the next one: 0 at the stop
  /// left, 1 at the next one. A recent precise fix on the ride's path says it (the GPS, above ground); otherwise
  /// (underground, or only the network's positions, which stay at a station) the clock does, from when the stop was
  /// left to the next one's time: the stop times of the vehicle followed (the journey moves to the real times of a
  /// departure chosen or guessed, `retimeJourney`), else the schedule's, shifted by the delay measured at boarding
  /// ([GoProgress.shift]); never behind where the GPS last saw the user. Null off board or without the served stops.
  double? betweenStops(GoProgress progress, DateTime now) {
    final ride = stepOf(progress);
    final stops = ride?.section.stops ?? const <JourneyStop>[];
    if (ride == null || progress.phase != GoPhase.onBoard || stops.length < 2) {
      return null;
    }
    final last = stops.length - 1;
    final k = math.min(progress.stopIndex, last - 1);
    final span = ride.stopAlongs[k + 1] - ride.stopAlongs[k];
    final preciseAlong = progress.preciseAlong;
    final seen = preciseAlong == null || span <= 0 ? null : ((preciseAlong - ride.stopAlongs[k]) / span).clamp(0.0, 1.0);
    final seenAt = progress.preciseAt;
    if (seen != null && seenAt != null && now.difference(seenAt) <= _preciseValidity) {
      return seen;
    }
    // Left when the vehicle was seen to leave (the boarding stop), else when the clock says so (see _ride)
    final left = ride.stopTime(k).add(progress.shift + (k == 0 ? Duration.zero : _dwell));
    final next = (k + 1 == last ? ride.section.arrival : ride.stopTime(k + 1)).add(progress.shift);
    final total = next.difference(left);
    final clock = total <= Duration.zero
        ? (now.isBefore(left) ? 0.0 : 1.0)
        : (now.difference(left).inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return math.max(clock, seen ?? 0);
  }

  // Manual corrections

  /// Waiting: the user says they boarded; otherwise the step is done
  GoProgress next(GoProgress progress) =>
      progress.phase == GoPhase.waiting ? _board(progress, null, null) : _advance(progress, null);

  /// The user says they are at [step] (a step of the list, or `steps.length` for the arrival); on a move, [along]
  /// meters along it (out of the station they got off at)
  GoProgress jumpTo(GoProgress progress, int step, {double along = 0}) {
    if (step >= steps.length) {
      return _arrive(progress, DateTime.now());
    }
    return GoProgress(
      step: step,
      phase: _phaseOf(step),
      along: steps[step].isRide ? 0 : along,
      shift: progress.shift,
      lastFixAt: progress.lastFixAt,
      fired: progress.fired,
    );
  }

  /// The journey was moved to a departure chosen for the ride [step] (see [GoController.choose]): its times are
  /// now the plan. For the ride in progress, the user waits for the new vehicle and its alerts can be given again.
  GoProgress chosen(GoProgress progress, int step) {
    if (step != progress.step) {
      return progress;
    }
    final fired = {...progress.fired}..removeWhere((id) => id.endsWith('-$step'));
    return progress.copyWith(phase: GoPhase.waiting, shift: Duration.zero, issue: () => null, fired: fired);
  }

  /// On board, the journey now follows another vehicle for the ride in progress, guessed (see [GoController]): the user
  /// is where they were on the way, the stops left are counted on that vehicle's, and its times are shifted from
  /// [departed], when the user was seen to leave, unless its real time says about the same (the more precise)
  GoProgress onAnotherVehicle(GoProgress progress, DateTime departed) {
    final ride = stepOf(progress);
    if (ride == null || progress.phase != GoPhase.onBoard) {
      return progress;
    }
    final index = _stopLeft(ride, progress.along);
    final preciseAlong = progress.preciseAlong;
    final gap = departed.difference(ride.section.departure);
    final shift = gap.abs() <= const Duration(minutes: 1) ? Duration.zero : Duration(seconds: gap.inSeconds.clamp(-1800, 3600));
    return progress.copyWith(
      stopIndex: index,
      stopFloor: preciseAlong == null ? 0 : _stopLeft(ride, preciseAlong),
      shift: shift,
      hintStop: 0,
      pendingHintStop: () => null,
    );
  }

  GoProgress dismissIssue(GoProgress progress) => progress.copyWith(issue: () => null, offRouteSince: () => null);

  // Automatic progress

  (GoProgress, List<GoAlert>) update(GoProgress progress, GoInput input) {
    final alerts = <GoAlert>[];
    final fix = _usableFix(input);
    var current = fix != null ? progress.copyWith(lastFixAt: input.fixAt ?? input.now) : progress;
    if (fix != null && (input.accuracy ?? 0) <= _preciseAccuracy) {
      current = current.copyWith(preciseFixAt: input.fixAt ?? input.now);
    }

    // Where the user really is, when the progress was only guessed: still on board the ride the clock got them off, or
    // anywhere on the journey once the location is back
    if (fix != null && current.phase != GoPhase.arrived) {
      final precise = (input.accuracy ?? 0) <= _preciseAccuracy;
      current = (precise ? _backOnBoard(current, input, fix) : null) ??
          (input.relocate ? _relocate(current, input, fix, alerts) : null) ??
          (precise ? _backToSeen(current, input, fix) : null) ??
          current;
    }

    // Several steps can end at once (e.g. back from the background)
    for (var guard = 0; guard <= steps.length; guard++) {
      final before = current;
      current = switch (current.phase) {
        GoPhase.moving => _move(current, input, fix, alerts),
        GoPhase.waiting => _wait(current, input, fix, alerts),
        GoPhase.onBoard => _ride(current, input, fix, alerts),
        GoPhase.arrived => current,
      };
      if (current.step == before.step && current.phase == before.phase) {
        break;
      }
    }

    // Right by the destination on the last step
    if (current.phase != GoPhase.arrived && fix != null && current.step >= steps.length - 1 &&
        _atDestination(current, fix, input.accuracy, input.now)) {
      current = _arrive(current, input.now);
    }
    if (current.phase == GoPhase.arrived && !current.fired.contains('arrived')) {
      alerts.add(GoAlert(id: 'arrived', title: currentL10n.goArrived, body: journey.sections.lastOrNull?.to?.name));
    }

    _platformAlert(current, input, alerts);

    final fresh = alerts.where((alert) => !current.fired.contains(alert.id)).toList();
    if (fresh.isNotEmpty) {
      current = current.copyWith(fired: {...current.fired, ...fresh.map((alert) => alert.id)});
    }
    return (current, fresh);
  }

  /// A train's platform, once announced or when it changes: for the ride waited for, or the next one (walking there,
  /// or on board the previous ride)
  void _platformAlert(GoProgress progress, GoInput input, List<GoAlert> alerts) {
    final index = input.vehicleStep;
    final platform = input.vehicle?.platform?.trim();
    if (index == null || platform == null || platform.isEmpty || progress.phase == GoPhase.arrived || index < progress.step ||
        index >= steps.length || !steps[index].isRide || (index == progress.step && progress.phase == GoPhase.onBoard)) {
      return;
    }
    final section = steps[index].section;
    final line = section.line;
    if (!(line?.mode.isRail ?? false)) {
      return;
    }
    final lineLabel = line?.label ?? '';
    final changed = progress.fired.any((id) => id.startsWith('platform-$index-') && id != 'platform-$index-$platform');
    alerts.add(GoAlert(
      id: 'platform-$index-$platform',
      title: changed ? currentL10n.alertPlatformChanged(lineLabel, platform) : currentL10n.alertPlatform(lineLabel, platform),
      body: currentL10n.direction(section.headsign ?? ''),
      urgent: changed,
    ));
  }

  LatLng? _usableFix(GoInput input) {
    final position = input.position;
    if (position == null || (input.accuracy ?? 0) > _maxAccuracy) {
      return null;
    }
    final at = input.fixAt ?? input.now;
    return input.now.difference(at) <= _fixValidity ? position : null;
  }

  /// No usable fix for a while (underground, indoors): the schedule leads
  bool followsSchedule(GoProgress progress, DateTime now) => _noFixFor(progress, now);

  bool _noFixFor(GoProgress progress, DateTime now) =>
      progress.lastFixAt == null || now.difference(progress.lastFixAt!) > _noFixDelay;

  GoProgress _move(GoProgress progress, GoInput input, LatLng? fix, List<GoAlert> alerts) {
    final step = steps[progress.step];
    final nextStep = progress.step + 1 < steps.length ? steps[progress.step + 1] : null;
    var current = progress;
    var done = false;

    if (fix != null) {
      final projection = step.line.project(fix, minAlong: math.max(0, current.along - 30));
      if (projection != null) {
        current = current.copyWith(along: math.max(current.along, projection.along));

        // Away from the path for more than a minute, as far as the fix is sure of it (indoors, a fix may be 100 m off);
        // not where the move starts before the path was joined: out of a train, the platform is hundreds of meters
        // from where the walk is drawn from, and a big station takes minutes to leave
        final away = projection.distance - (input.accuracy ?? 0);
        final leaving = !current.joined && step.line.points.isNotEmpty && metersBetween(fix, step.line.points.first) <= _leavingMeters;
        if (projection.distance < 80) {
          current = current.copyWith(joined: true);
        }
        if (away > 150 && !leaving) {
          final since = current.offRouteSince ?? input.now;
          current = current.copyWith(offRouteSince: () => since);
          if (input.now.difference(since) >= const Duration(minutes: 1) && current.issue == null &&
              !current.fired.contains('offroute-${current.step}')) {
            current = current.copyWith(issue: () => GoIssue.offRoute);
            alerts.add(GoAlert(id: 'offroute-${current.step}', title: currentL10n.goOffRoute,
                body: currentL10n.alertOffRouteBody));
          }
        } else if (projection.distance < 80) {
          current = current.copyWith(offRouteSince: () => null, issue: () => current.issue == GoIssue.offRoute ? null : current.issue);
        }
      }
      final end = step.end;
      done = nextStep == null
          // The destination: right by it, not where the progress along the path (run ahead by GPS noise) says
          ? _atDestination(current, fix, input.accuracy, input.now)
          : step.line.length - current.along < 40 || (end != null && metersBetween(fix, end) < 40);

      // Already riding the next vehicle (seen far along its line too, back from a tunnel, unless still on the walk)
      if (!done && nextStep != null && nextStep.isRide) {
        final onWalk = projection != null && projection.distance <= 60;
        done = _riding(nextStep, fix, input.speed ?? 0, far: !onWalk) != null;
      }

      // Hurry: the vehicle leaves before the user gets to the stop at a normal pace
      if (!done && nextStep != null && nextStep.isRide) {
        final departure = expectedDeparture(nextStep, current, input.vehicleOf(current.step + 1));
        final walkSeconds = metersLeft(current) / 1.2;
        final margin = departure.difference(input.now).inSeconds;
        if (margin > 0 && margin < walkSeconds + 60) {
          final line = nextStep.section.line;
          alerts.add(GoAlert(
            id: 'hurry-${current.step}',
            title: currentL10n.alertHurry,
            body: currentL10n.alertHurryBody(
                line?.label ?? '', (margin / 60).ceil(), metersLeft(current).round()),
          ));
        }
      }
    } else if (_noFixFor(current, input.now)) {
      // Underground or indoor: follow the schedule, as far as the user can have gone since the last fix
      done = !input.now.isBefore(step.section.arrival.add(current.shift)) && _couldBeAtEnd(step, current, input.now);
    }

    return done ? _advance(current, input.now, byClock: fix == null) : current;
  }

  /// The fastest a move's user goes (m/s): a brisk walk, a fast ride; null for a car, which the clock alone follows
  static double? _topPace(GoStep step) => switch (step.section.kind) {
        SectionKind.walk || SectionKind.transfer => 2.0,
        SectionKind.bike => 8.0,
        _ => null,
      };

  /// Without a fix, the move [step] may have been done: from where the last one put the user along it, its end is
  /// within reach at [_topPace] since. Indoors, the GPS gives way to positions hundreds of meters off for a minute or
  /// two: the user still at home is not at the station by the clock. Only once the GPS saw the user on the move
  /// ([GoProgress.joined]): before that (a session taken up after a restart, the GPS lost from the start), nothing
  /// says where they are.
  static bool _couldBeAtEnd(GoStep step, GoProgress progress, DateTime now) {
    final pace = _topPace(step);
    final since = progress.lastFixAt;
    if (pace == null || since == null || !progress.joined) {
      return true;
    }
    final left = math.max(0.0, step.line.length - progress.along);
    return !now.isBefore(since.add(Duration(milliseconds: (left / pace * 1000).round())));
  }

  /// A precise fix off the path of [ride]: not on its vehicle, wherever it is on the way
  static bool _offPath(GoStep ride, LatLng fix, double accuracy) {
    final projection = ride.line.project(fix);
    return projection == null || projection.distance > _onPathMeters + accuracy;
  }

  /// A precise fix came this recently: the GPS works, the user is not underground
  static bool _recentlyPrecise(GoProgress progress, DateTime now) {
    final at = progress.preciseFixAt;
    return at != null && !now.isAfter(at.add(_noFixDelay));
  }

  GoProgress _wait(GoProgress progress, GoInput input, LatLng? fix, List<GoAlert> alerts) {
    final ride = steps[progress.step];
    final line = ride.section.line;
    final lineLabel = line?.label ?? '';
    final vehicle = input.vehicleOf(progress.step);
    final departure = expectedDeparture(ride, progress, vehicle);
    final untilDeparture = departure.difference(input.now);
    var current = progress;

    final cancelled = vehicle?.cancelled == true;
    if (cancelled && current.issue == null) {
      current = current.copyWith(issue: () => GoIssue.cancelled);
      alerts.add(GoAlert(id: 'cancel-${current.step}', title: currentL10n.alertCancelled(lineLabel), body: currentL10n.alertTakeNextOrRecalculate, urgent: true));
      return current;
    }

    // Delay of the planned vehicle (a cancelled one won't come: no delay nor "soon")
    if (!cancelled && vehicle != null && vehicle.time.difference(plannedDeparture(ride, current)) >= const Duration(minutes: 3)) {
      alerts.add(GoAlert(
        id: 'delay-${current.step}',
        title: currentL10n.alertLate(lineLabel),
        body: [
          currentL10n.goPlannedDeparture(formatClock(vehicle.time)),
          if (vehicle.platform != null) currentL10n.goPlatform(vehicle.platform!),
        ].join(', '),
      ));
    }

    if (!cancelled && untilDeparture > Duration.zero && untilDeparture <= const Duration(minutes: 2)) {
      alerts.add(GoAlert(
        id: 'soon-${current.step}',
        title: currentL10n.alertSoon(lineLabel, math.max(1, untilDeparture.inSeconds ~/ 60)),
        body: currentL10n.direction(ride.section.headsign ?? ''),
      ));
    }

    // Seen riding: on board, of the vehicle seen leaving then
    final speed = input.speed ?? 0;
    final precise = fix != null && (input.accuracy ?? 0) <= _preciseAccuracy;
    if (fix != null) {
      final riding = _riding(ride, fix, speed);
      if (riding != null) {
        final left = _leftAt(ride, input.now, riding.along, speed, seat: current.preciseAlong);
        return _board(current, input.now, _departureTaken(departure, input.now, riding.along, left), byClock: !precise);
      }
    }

    // Standing on the platform, or seated in the vehicle waiting there (a train is 450 m long, the stop's point at its
    // head in a terminus): where, to date the vehicle's leaving once it moves
    final seat = precise ? ride.alongInPlatformZone(fix, input.accuracy ?? 0) : null;
    if (seat != null) {
      current = current.copyWith(preciseAlong: () => seat, preciseAt: () => input.fixAt ?? input.now);
    }

    // Still at the stop by a precise fix only
    if (untilDeparture <= const Duration(seconds: -90) && fix != null && precise) {
      final start = ride.start;
      final stillAtStop = (seat != null || start != null && metersBetween(fix, start) < 150) && speed < 2;
      if (stillAtStop) {
        // A vehicle only scheduled is often a few minutes late: given up later than one the real time saw leave; one the
        // real time says is at the stop has not left
        final realtime = vehicle?.realtime ?? (input.vehicleStep == current.step && input.realtimeDepartures);
        final missed = vehicle?.atStop != true &&
            untilDeparture <= (realtime ? const Duration(seconds: -90) : -_scheduledLateness);
        if (missed && current.issue == null && !current.fired.contains('missed-${current.step}')) {
          current = current.copyWith(issue: () => GoIssue.missed);
          alerts.add(GoAlert(id: 'missed-${current.step}', title: currentL10n.alertMissed(lineLabel),
              body: currentL10n.alertMissedBody));
        }
        return current;
      }
      // Neither at the stop nor on the way: elsewhere, not on the vehicle gone (at home; a later one may still be taken)
      if (_offPath(ride, fix, input.accuracy ?? 0)) {
        return current;
      }
      return _board(current, input.now, departure, byClock: true);
    }

    // No position, or only rough ones (underground station): assume the user boarded; not while the GPS gave a precise
    // fix a moment ago (indoors, the network's positions come between the GPS's)
    final unseen = fix == null ? _noFixFor(current, input.now) : !precise && !_recentlyPrecise(current, input.now);
    if (untilDeparture <= const Duration(seconds: -60) && unseen && current.issue == null) {
      return _board(current, input.now, departure, byClock: true);
    }
    return current;
  }

  /// A move's path not joined yet, the user this close to where it starts is still leaving the place (a station and its
  /// platforms), not off the way
  static const _leavingMeters = 400.0;

  /// The destination is reached by a fix this close to it, or to the end of the walk to it (an address may be a point
  /// inside a building that the walk stops in front of)…
  static const _arrivalMeters = 25.0;

  /// …and this precise: a rougher one (the network's, indoors) may be 100 m off
  static const _arrivalAccuracy = 25.0;

  /// Its time past by this, [_nearArrivalMeters] from the destination is enough: a big place whose point can't be
  /// walked to (a park), or indoors where only rough fixes come
  static const _arrivalLateness = Duration(minutes: 2);
  static const _nearArrivalMeters = 60.0;

  /// [fix], of [accuracy], is right by the destination: within a few tens of meters by a precise fix, never more than a
  /// hundred meters ahead of the user as rough fixes and the progress along the path would say
  bool _atDestination(GoProgress progress, LatLng fix, double? accuracy, DateTime now) {
    final last = steps.lastOrNull;
    final ends = [?destination, if (last != null && !last.isRide && last.line.points.isNotEmpty) last.line.points.last];
    final distance = ends.fold(double.infinity, (closest, end) => math.min(closest, metersBetween(fix, end)));
    if (distance <= _arrivalMeters && (accuracy ?? 0) <= _arrivalAccuracy) {
      return true;
    }
    return distance <= _nearArrivalMeters && !now.isBefore(journey.arrival.add(progress.shift + _arrivalLateness));
  }

  /// Seen on board [ride] at [fix]: moving fast along its line, or [far] along it from the stop whatever the speed
  /// (the network's positions have none, back from a tunnel), beyond where its vehicle may stand at the stop
  /// ([GoStep.platformZone]: someone seated in a train waiting at the platform is not on their way), not where the line
  /// passes by the stop again
  static PolylineProjection? _riding(GoStep ride, LatLng fix, double speed, {bool far = true}) {
    final projection = ride.line.project(fix);
    if (projection == null) {
      return null;
    }
    if (speed >= _movingSpeed && projection.distance < 60 && projection.along > 80) {
      return projection;
    }
    final start = ride.start;
    final awayFromStop = start == null || metersBetween(fix, start) > 150;
    final beyond = math.max(_farAlong, ride.platformZone.to + _beyondZoneMeters);
    return far && awayFromStop && projection.distance < 100 && projection.along >= beyond ? projection : null;
  }

  /// Nobody waits this far down the line from their stop: seen there, the user is on board…
  static const _farAlong = 400.0;

  /// …nor this far beyond where its vehicle stands at the stop
  static const _beyondZoneMeters = 200.0;

  /// A vehicle moving: its passengers' GPS says at least this (m/s), sure of it ([sureSpeed])
  static const _movingSpeed = 4.0;

  /// When the vehicle the user is on left the stop, seen [along] meters from it at [now]: at [speed] near the stop (the
  /// first fixes on board) from where the user was seen in it at the platform ([seat]), else on the ride's times (the
  /// stops on the way slow it)
  static DateTime _leftAt(GoStep ride, DateTime now, double along, double speed, {double? seat}) {
    final from = seat ?? (ride.stopAlongs.isEmpty ? 0.0 : ride.stopAlongs.first);
    final run = math.max(0.0, along - from);
    return speed >= _movingSpeed && run <= 500
        ? now.subtract(Duration(milliseconds: (run / speed * 1000).round()))
        : now.subtract(ride.scheduledTo(along));
  }

  /// Waiting for a vehicle only scheduled, how late it may still come before it is given up for missed
  static const _scheduledLateness = Duration(minutes: 3);

  /// When the vehicle the user is on left, seen [along] meters from the stop at [now] and estimated to have [left]
  /// then. Close to the stop (the first fixes on board), that is well known: the [expected] departure when it is
  /// within a minute of it (its real time is the more precise), else the user is on another vehicle than expected: a
  /// late one (taken after it was given up for missed and the next one retained) or one before the planned one.
  /// Further, stops on the way blur it: only an expected departure still to come is surely not the one taken.
  static DateTime _departureTaken(DateTime expected, DateTime now, double along, DateTime left) {
    final anotherVehicle = expected.isAfter(now.add(const Duration(minutes: 1))) ||
        along <= 500 && expected.difference(left).abs() > const Duration(minutes: 1);
    return anotherVehicle ? left : expected;
  }

  GoProgress _board(GoProgress progress, DateTime? now, DateTime? departure, {bool byClock = false}) {
    final ride = stepOf(progress);
    if (ride == null) {
      return progress;
    }
    // Schedule shift from the real departure: later or earlier than planned (an earlier vehicle, a late one taken
    // after the next one was retained), clamped so that a wrong detection never shifts by hours
    var shift = progress.shift;
    if (departure != null) {
      final measured = departure.difference(ride.section.departure);
      shift = Duration(seconds: measured.inSeconds.clamp(-1800, 3600));
    }
    return progress.copyWith(
      phase: GoPhase.onBoard,
      along: 0,
      stopIndex: 0,
      shift: shift,
      issue: () => null,
      preciseAlong: () => null,
      preciseAt: () => null,
      stopFloor: 0,
      departedAt: () => departure ?? now,
      byClock: byClock,
      seenStep: () => byClock ? _seenBefore(progress) : null,
      hintStop: 0,
      pendingHintStop: () => null,
    );
  }

  /// A stop is left once the vehicle is this far beyond it…
  static const _leftStopMeters = 30.0;

  /// …or, underground, this long after its time (the vehicle stands at the stop)
  static const _dwell = Duration(seconds: 20);

  /// The alighting stop is reached a little before it (the vehicle brakes, the doors are near)
  static const _arrivingMeters = 40.0;

  /// "Get ready" comes once the stop before is left and the arrival is this close: a direct train's stop before is
  /// where it was boarded, ten minutes away
  static const prepareAhead = Duration(minutes: 4);

  /// A precise fix this close to the ride's path is on it (the shapes are a little off the tracks)…
  static const _onPathMeters = 100.0;

  /// …and says where the user is between the stops for this long; older (a tunnel), the clock does
  static const _preciseValidity = Duration(seconds: 12);

  /// On board. [GoProgress.stopIndex] is the last stop the vehicle has left, so that "next stop" is only said once
  /// it is really the next one: not while the vehicle pulls in to the one before.
  ///
  /// The GPS leads whenever it is precise: a precise fix on the ride's path says which stops were left and when the
  /// alighting stop is reached, and nothing else does while one came in the last minute. Its times measure how late the
  /// vehicle is ([GoProgress.shift], see [_recalibrated]), so that the clock taking over in a tunnel goes on from where
  /// the GPS last saw the vehicle. Without one (underground, the network's positions only), the clock leads: the stop
  /// times shifted by that delay, never further than the vehicle can have gone since the GPS last saw it ([_reach]),
  /// set right by a rough position near a station ([_hint]).
  GoProgress _ride(GoProgress progress, GoInput input, LatLng? fix, List<GoAlert> alerts) {
    final ride = steps[progress.step];
    final stops = ride.section.stops;
    // Without the served stops, only the end and the arrival time say where the vehicle is
    final withStops = stops.length >= 2;
    final last = math.max(0, stops.length - 1);
    final now = input.now;
    final accuracy = input.accuracy ?? 0;
    final at = input.fixAt ?? now;
    final precise = fix != null && accuracy <= _preciseAccuracy;
    var current = progress;
    var gpsArrived = false;
    int? gpsIndex;

    if (fix != null && precise) {
      final projection = ride.line.project(fix, minAlong: math.max(0, (current.preciseAlong ?? 0) - 100));
      if (projection != null && projection.distance < _onPathMeters) {
        final along = projection.along;
        // Two precise fixes on board at least: how late the vehicle is where it is (the first one may be the one that
        // saw the user board)
        if (current.preciseAt != null && current.preciseAt!.isBefore(at)) {
          current = current.copyWith(shift: _recalibrated(ride, current, along, at, input.speed ?? 0));
        }
        gpsIndex = _stopLeft(ride, along);
        gpsArrived = withStops && ride.stopAlongs[last] <= along + _arrivingMeters;
        final issue = current.issue == GoIssue.offRoute ? null : current.issue;
        current = current.copyWith(
          along: math.max(current.along, along),
          preciseAlong: () => math.max(progress.preciseAlong ?? 0, along),
          preciseAt: () => at,
          stopFloor: math.max(current.stopFloor, gpsIndex),
          offRouteSince: () => null,
          issue: () => issue,
        );
      } else if (projection == null || projection.distance - accuracy > _offLineMeters) {
        // Far from the line by a fix sure of it: not on this vehicle (the wrong train, off too early)
        current = _offLine(current, now, alerts);
      }
      final end = ride.end;
      gpsArrived = gpsArrived || end != null && metersBetween(fix, end) < 60;
    }

    final recentPrecise = current.preciseAt != null && !now.isAfter(current.preciseAt!.add(_noFixDelay));
    // Underground: a rough position near a station, now and then, says about where the vehicle is
    final position = input.position;
    if (!recentPrecise && !precise && position != null && accuracy <= _hintAccuracy && now.difference(at) <= _fixValidity) {
      current = _hint(ride, current, position, accuracy, at);
    }

    final shiftedArrival = (withStops ? ride.stopTime(last) : ride.section.arrival).add(current.shift);
    var index = current.stopIndex;
    var arrived = gpsArrived;
    if (recentPrecise) {
      if (gpsIndex != null) {
        index = math.max(current.stopFloor, gpsIndex);
      }
    } else {
      // The clock, the vehicle's delay measured, as far as it can have gone; never before a stop the GPS saw left
      final reach = _reach(ride, current, now);
      var clockIndex = 0;
      for (var k = 1; k < last; k++) {
        if (!now.isBefore(ride.stopTime(k).add(current.shift + _dwell)) && ride.stopAlongs[k] <= reach) {
          clockIndex = k;
        }
      }
      index = math.max(current.stopFloor, clockIndex);
      final behind = fix != null && !precise && _roughlyBehind(ride, fix, accuracy);
      arrived = arrived || !now.isBefore(shiftedArrival) && (!withStops || ride.stopAlongs[last] <= reach) && !behind;
    }
    current = current.copyWith(stopIndex: index);

    final alightName = ride.section.to?.name ?? '';
    final left = withStops ? last - current.stopIndex : 1;
    final untilArrival = shiftedArrival.difference(now);
    // Get ready once the stop before has been left and the arrival is near (without the stops: two minutes before it)
    if (!arrived && (withStops ? left == 1 && untilArrival <= prepareAhead : untilArrival <= const Duration(minutes: 2))) {
      alerts.add(GoAlert(id: 'prepare-${current.step}', title: currentL10n.alertPrepare, body: currentL10n.goNextStop(alightName)));
    }
    if (arrived) {
      alerts.add(GoAlert(id: 'alight-${current.step}', title: currentL10n.alertGetOffNow, body: alightName, urgent: true));
      return _advance(current.copyWith(stopIndex: last), now, byClock: !gpsArrived);
    }
    return current;
  }

  /// Off the line this far (m), the fix's accuracy taken off, the user is not on the ride's vehicle
  static const _offLineMeters = 300.0;

  /// Rough positions this sure of themselves (m) may still say near which station a vehicle underground is
  static const _hintAccuracy = 300.0;

  /// …within this of it, the accuracy added
  static const _hintMeters = 150.0;

  /// A vehicle said near a station is there within this of the clock's time for it
  static const _hintSlack = Duration(seconds: 60);

  /// The delay measured by a precise fix moves the clock by at most this (fixes a few seconds apart smooth it)
  static const _maxRecalibration = Duration(seconds: 30);

  /// Back on board the ride the clock got the user off: on its line this far before where they get off, or moving
  static const _backOnBoardMeters = 500.0;

  /// The last stop left at [along] meters along [ride]
  static int _stopLeft(GoStep ride, double along) {
    var index = 0;
    for (var k = 0; k < ride.stopAlongs.length - 1; k++) {
      if (ride.stopAlongs[k] + _leftStopMeters <= along) {
        index = k;
      }
    }
    return index;
  }

  /// The delay of the vehicle the user is on, measured by a precise fix [along] meters along [ride] at [at]: moving, the
  /// time it is there less the schedule's; standing (at a station, a signal), at least that, since it hasn't left yet.
  /// By [_maxRecalibration] at most per fix.
  static Duration _recalibrated(GoStep ride, GoProgress progress, double along, DateTime at, double speed) {
    final shift = progress.shift;
    var target = at.difference(ride.scheduledAt(along));
    if (speed < _movingSpeed) {
      final atStation = ride.stopAlongs.any((stop) => (stop - along).abs() <= 100);
      final late = target - (atStation ? _dwell : Duration.zero);
      target = late > shift ? late : shift;
    }
    var change = target - shift;
    if (change > _maxRecalibration) {
      change = _maxRecalibration;
    } else if (change < -_maxRecalibration) {
      change = -_maxRecalibration;
    }
    return Duration(seconds: (shift + change).inSeconds.clamp(-1800, 3600));
  }

  /// How far along [ride] the vehicle can be at [now]: where the GPS last saw it, plus its top speed since
  static double _reach(GoStep ride, GoProgress progress, DateTime now) {
    final along = progress.preciseAlong;
    final at = progress.preciseAt;
    if (along == null || at == null) {
      return double.infinity;
    }
    return along + ride.topSpeed * math.max(0, now.difference(at).inMilliseconds) / 1000;
  }

  /// A rough position on [ride]'s line well before where the user gets off: not there yet, whatever the clock says
  static bool _roughlyBehind(GoStep ride, LatLng fix, double accuracy) {
    if (ride.stopAlongs.length < 2) {
      return false;
    }
    final projection = ride.line.project(fix);
    return projection != null && projection.distance < 200 && ride.stopAlongs.last - projection.along > accuracy + 500;
  }

  /// The last stop of [ride] the clock says the vehicle has reached at [at]
  static int _clockStop(GoStep ride, GoProgress progress, DateTime at) {
    var stop = 0;
    for (var k = 1; k < ride.section.stops.length; k++) {
      if (!at.isBefore(ride.stopTime(k).add(progress.shift))) {
        stop = k;
      }
    }
    return stop;
  }

  /// Underground, a rough [position] near a station of [ride] at [at]: the vehicle is about there, the clock set right
  /// to it. Each station once, never one behind the last taken (a position the system keeps giving while the metro takes
  /// the user stations away); one more than two stations behind the clock only when a second one further on confirms it
  /// (the vehicle really late), none further than one ahead.
  static GoProgress _hint(GoStep ride, GoProgress progress, LatLng position, double accuracy, DateTime at) {
    final k = ride.stopNear(position, accuracy + _hintMeters);
    if (k == null || k == 0 || k <= progress.hintStop) {
      return progress;
    }
    final clock = _clockStop(ride, progress, at);
    if (k > clock + 1) {
      return progress;
    }
    if (k < clock - 2) {
      final pending = progress.pendingHintStop;
      if (pending == null || pending >= k) {
        return progress.copyWith(pendingHintStop: () => k);
      }
    }
    final arrives = ride.stopTime(k).add(progress.shift);
    final from = arrives.subtract(_hintSlack);
    final to = arrives.add(_dwell + _hintSlack);
    // Out of the clock's time there: the vehicle at the station then, standing halfway through its stop
    final shift = at.isBefore(from) || at.isAfter(to) ? at.difference(ride.stopTime(k).add(_dwell ~/ 2)) : progress.shift;
    return progress.copyWith(
      shift: Duration(seconds: shift.inSeconds.clamp(-1800, 3600)),
      hintStop: k,
      pendingHintStop: () => null,
    );
  }

  /// On board, a precise fix far from the ride's line for a minute: off the way
  GoProgress _offLine(GoProgress progress, DateTime now, List<GoAlert> alerts) {
    final since = progress.offRouteSince ?? now;
    var current = progress.copyWith(offRouteSince: () => since);
    if (now.difference(since) >= const Duration(minutes: 1) && current.issue == null &&
        !current.fired.contains('offroute-${current.step}')) {
      current = current.copyWith(issue: () => GoIssue.offRoute);
      alerts.add(GoAlert(id: 'offroute-${current.step}', title: currentL10n.goOffRoute, body: currentL10n.alertOffRouteBody));
    }
    return current;
  }

  /// Off a ride by the clock (underground, the GPS lost), a precise fix still on its line before where the user gets off,
  /// moving with the vehicle or well before that stop: back on board, where the GPS says, its "get off" to come again
  GoProgress? _backOnBoard(GoProgress progress, GoInput input, LatLng fix) {
    final previous = progress.step - 1;
    if (!progress.byClock || progress.joined || progress.phase == GoPhase.onBoard || previous < 0 ||
        previous >= steps.length || !steps[previous].isRide) {
      return null;
    }
    final ride = steps[previous];
    final projection = ride.line.project(fix);
    if (ride.stopAlongs.length < 2 || projection == null || projection.distance > 50) {
      return null;
    }
    final before = ride.stopAlongs.last - projection.along;
    final moving = (input.speed ?? 0) >= _movingSpeed;
    if (!(before > _backOnBoardMeters || moving && before > _arrivingMeters)) {
      return null;
    }
    final index = _stopLeft(ride, projection.along);
    return GoProgress(
      step: previous,
      phase: GoPhase.onBoard,
      along: projection.along,
      preciseAlong: projection.along,
      preciseAt: input.fixAt ?? input.now,
      stopIndex: index,
      stopFloor: index,
      shift: progress.shift,
      lastFixAt: progress.lastFixAt,
      fired: {...progress.fired}..remove('alight-$previous'),
    );
  }

  /// Where a precise fix may be on [step] in [phase]: along a move's path, at a ride's stop (or riding it, seen moving),
  /// anywhere near its line on board
  bool _onStep(GoStep step, GoPhase phase, LatLng fix, double accuracy, double speed) {
    final projection = step.line.project(fix);
    final distance = projection?.distance ?? double.infinity;
    return switch (phase) {
      GoPhase.moving => distance <= _onPathMeters + accuracy,
      GoPhase.waiting => step.alongInPlatformZone(fix, accuracy) != null || speed >= _movingSpeed && distance <= _onPathMeters + accuracy,
      GoPhase.onBoard => distance - accuracy <= _offLineMeters,
      GoPhase.arrived => true,
    };
  }

  /// Taken further by the clock, a precise fix sure to be off the step in progress and back on a step the clock got the
  /// user through since the GPS last saw them ([GoProgress.seenStep]): the user is there, never got further (indoors,
  /// a minute of rough positions ended the walk; the user is still at home). On a move, where the fix is along it; at a
  /// ride's stop, waiting for it. The latest such step; never back on board (see [_backOnBoard]).
  GoProgress? _backToSeen(GoProgress progress, GoInput input, LatLng fix) {
    if (!progress.byClock || progress.phase == GoPhase.arrived) {
      return null;
    }
    final accuracy = input.accuracy ?? 0;
    final current = stepOf(progress);
    if (current == null || _onStep(current, progress.phase, fix, accuracy, input.speed ?? 0)) {
      return null;
    }
    final seen = progress.seenStep ?? math.max(0, progress.step - 1);
    for (var s = math.min(progress.step, steps.length) - 1; s >= seen; s--) {
      final step = steps[s];
      final base = GoProgress(step: s, phase: _phaseOf(s), shift: progress.shift, lastFixAt: progress.lastFixAt, fired: progress.fired);
      if (step.isRide) {
        final moving = (input.speed ?? 0) >= _movingSpeed;
        if (!moving && step.alongInPlatformZone(fix, accuracy) != null) {
          return base;
        }
        continue;
      }
      final projection = step.line.project(fix);
      if (projection != null && projection.distance <= _onPathMeters + accuracy) {
        return base.copyWith(along: projection.along, joined: projection.distance < 80);
      }
    }
    return null;
  }

  /// The step the clock says is going on at [now]: the last one whose (shifted) departure is past
  int _clockStep(GoProgress progress, DateTime now) {
    var clock = 0;
    for (var s = 0; s < steps.length; s++) {
      if (!now.isBefore(steps[s].section.departure.add(progress.shift))) {
        clock = s;
      }
    }
    return clock;
  }

  /// The location back (turned on again, a restart, a long tunnel): [fix] is wherever the user got meanwhile, not
  /// necessarily on the step in progress. On a step further on, of all the journey's that pass by it the one closest to
  /// where the clock is; one back when the step in progress was only reached by the clock. Null when the user is still
  /// on the step in progress; off the way when nowhere near the journey.
  GoProgress? _relocate(GoProgress progress, GoInput input, LatLng fix, List<GoAlert> alerts) {
    final accuracy = input.accuracy ?? 0;
    final reach = _onPathMeters + accuracy;
    final current = stepOf(progress);
    final here = current?.line.project(fix);
    if (here != null && here.distance <= reach) {
      return null;
    }
    final lowest = progress.byClock ? math.max(0, progress.step - 1) : progress.step;
    final clock = _clockStep(progress, input.now);
    (int, PolylineProjection)? best;
    var closest = here?.distance ?? double.infinity;
    for (var s = lowest; s < steps.length; s++) {
      final projection = steps[s].line.project(fix);
      if (projection == null) {
        continue;
      }
      closest = math.min(closest, projection.distance);
      if (s == progress.step || projection.distance > reach) {
        continue;
      }
      if (best == null || (s - clock).abs() < (best.$1 - clock).abs()) {
        best = (s, projection);
      }
    }
    if (best == null) {
      if (closest - accuracy > _offLineMeters && progress.issue == null && !progress.fired.contains('offroute-${progress.step}')) {
        alerts.add(GoAlert(id: 'offroute-${progress.step}', title: currentL10n.goOffRoute, body: currentL10n.alertOffRouteBody));
        return progress.copyWith(issue: () => GoIssue.offRoute, offRouteSince: () => input.now);
      }
      return null;
    }
    final (step, projection) = best;
    final target = steps[step];
    final base = GoProgress(step: step, phase: _phaseOf(step), shift: progress.shift, lastFixAt: progress.lastFixAt, fired: progress.fired);
    if (!target.isRide) {
      return base.copyWith(along: projection.along, joined: projection.distance < 80);
    }
    final precise = accuracy <= _preciseAccuracy;
    final moving = (input.speed ?? 0) >= _movingSpeed;
    if (!moving && projection.along <= target.platformZone.to + _beyondZoneMeters) {
      return base;
    }
    final index = _stopLeft(target, projection.along);
    return base.copyWith(
      phase: GoPhase.onBoard,
      along: projection.along,
      preciseAlong: precise ? () => projection.along : null,
      preciseAt: precise ? () => input.fixAt ?? input.now : null,
      stopIndex: index,
      stopFloor: precise ? index : 0,
    );
  }

  GoProgress _advance(GoProgress progress, DateTime? now, {bool byClock = false}) {
    final next = progress.step + 1;
    if (next >= steps.length) {
      return _arrive(progress, now ?? DateTime.now());
    }
    return GoProgress(
      step: next,
      phase: _phaseOf(next),
      shift: progress.shift,
      lastFixAt: progress.lastFixAt,
      fired: progress.fired,
      byClock: byClock,
      seenStep: byClock ? _seenBefore(progress) : null,
    );
  }

  /// The step the GPS last saw the user on, [progress] being left by the clock
  static int _seenBefore(GoProgress progress) => progress.byClock ? progress.seenStep ?? math.max(0, progress.step - 1) : progress.step;

  GoProgress _arrive(GoProgress progress, DateTime now) => GoProgress(
        step: steps.length,
        phase: GoPhase.arrived,
        shift: progress.shift,
        lastFixAt: progress.lastFixAt,
        fired: progress.fired,
        arrivedAt: now,
      );
}
