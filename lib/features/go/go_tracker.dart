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
/// - Moving: position projected on the path; done near its end, or on schedule without a position (underground).
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

  /// Estimated arrival at the destination; [vehicle]: real-time departure of the current ride's vehicle
  DateTime eta(GoProgress progress, Departure? vehicle, {DateTime? now}) {
    if (progress.arrivedAt != null) {
      return progress.arrivedAt!;
    }
    var delay = progress.shift;
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

  /// Meters along the current step's path where the user is: on board, between the stops ([betweenStops]); else
  /// [GoProgress.along]
  double alongNow(GoProgress progress, DateTime now) {
    final share = betweenStops(progress, now);
    final ride = stepOf(progress);
    if (share == null || ride == null) {
      return progress.along;
    }
    final k = math.min(progress.stopIndex, ride.stopAlongs.length - 2);
    return ride.stopAlongs[k] + (ride.stopAlongs[k + 1] - ride.stopAlongs[k]) * share;
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
    var index = 0;
    for (var k = 0; k < ride.stopAlongs.length - 1; k++) {
      if (ride.stopAlongs[k] + _leftStopMeters <= progress.along) {
        index = k;
      }
    }
    final gap = departed.difference(ride.section.departure);
    final shift = gap.abs() <= const Duration(minutes: 1) ? Duration.zero : Duration(seconds: gap.inSeconds.clamp(-1800, 3600));
    return progress.copyWith(stopIndex: index, shift: shift);
  }

  GoProgress dismissIssue(GoProgress progress) => progress.copyWith(issue: () => null, offRouteSince: () => null);

  // Automatic progress

  (GoProgress, List<GoAlert>) update(GoProgress progress, GoInput input) {
    final alerts = <GoAlert>[];
    final fix = _usableFix(input);
    var current = fix != null ? progress.copyWith(lastFixAt: input.fixAt ?? input.now) : progress;

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

    // Close to the destination on the last step
    final destination = this.destination;
    if (current.phase != GoPhase.arrived && fix != null && destination != null && current.step >= steps.length - 1 &&
        metersBetween(fix, destination) < 50) {
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

        // Away from the path for more than a minute
        if (projection.distance > 150) {
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
      done = step.line.length - current.along < 40 || (end != null && metersBetween(fix, end) < 40);

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
      // Underground or indoor: follow the schedule
      done = !input.now.isBefore(step.section.arrival.add(current.shift));
    }

    return done ? _advance(current, input.now) : current;
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
    if (fix != null) {
      final riding = _riding(ride, fix, speed);
      if (riding != null) {
        final left = _leftAt(ride, input.now, riding.along, speed);
        return _board(current, input.now, _departureTaken(departure, input.now, riding.along, left));
      }
    }

    // Still at the stop by a precise fix only
    final precise = fix != null && (input.accuracy ?? 0) <= _preciseAccuracy;
    if (untilDeparture <= const Duration(seconds: -90) && fix != null && precise) {
      final start = ride.start;
      final stillAtStop = start != null && metersBetween(fix, start) < 150 && speed < 2;
      if (stillAtStop) {
        // A vehicle only scheduled is often a few minutes late: given up later than one the real time saw leave
        final realtime = vehicle?.realtime ?? (input.vehicleStep == current.step && input.realtimeDepartures);
        final missed = untilDeparture <= (realtime ? const Duration(seconds: -90) : -_scheduledLateness);
        if (missed && current.issue == null && !current.fired.contains('missed-${current.step}')) {
          current = current.copyWith(issue: () => GoIssue.missed);
          alerts.add(GoAlert(id: 'missed-${current.step}', title: currentL10n.alertMissed(lineLabel),
              body: currentL10n.alertMissedBody));
        }
        return current;
      }
      return _board(current, input.now, departure);
    }

    // No position, or only rough ones (underground station): assume the user boarded
    final unseen = fix == null ? _noFixFor(current, input.now) : !precise;
    if (untilDeparture <= const Duration(seconds: -60) && unseen && current.issue == null) {
      return _board(current, input.now, departure);
    }
    return current;
  }

  /// Seen on board [ride] at [fix]: moving fast along its line, or [far] along it from the stop whatever the speed
  /// (the network's positions have none, back from a tunnel), not where the line passes by the stop again
  static PolylineProjection? _riding(GoStep ride, LatLng fix, double speed, {bool far = true}) {
    final projection = ride.line.project(fix);
    if (projection == null) {
      return null;
    }
    if (speed >= 4 && projection.distance < 60 && projection.along > 80) {
      return projection;
    }
    final start = ride.start;
    final awayFromStop = start == null || metersBetween(fix, start) > 150;
    return far && awayFromStop && projection.distance < 100 && projection.along >= _farAlong ? projection : null;
  }

  /// Nobody waits this far down the line from their stop: seen there, the user is on board
  static const _farAlong = 400.0;

  /// When the vehicle the user is on left the stop, seen [along] meters from it at [now]: at [speed] near the stop (the
  /// first fixes on board), else on the ride's times (the stops on the way slow it)
  static DateTime _leftAt(GoStep ride, DateTime now, double along, double speed) => speed >= 4 && along <= 500
      ? now.subtract(Duration(milliseconds: (along / speed * 1000).round()))
      : now.subtract(ride.scheduledTo(along));

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

  GoProgress _board(GoProgress progress, DateTime? now, DateTime? departure) {
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
  GoProgress _ride(GoProgress progress, GoInput input, LatLng? fix, List<GoAlert> alerts) {
    final ride = steps[progress.step];
    final stops = ride.section.stops;
    // Without the served stops, only the end and the arrival time say where the vehicle is
    final withStops = stops.length >= 2;
    final last = math.max(0, stops.length - 1);
    final shiftedArrival = (withStops ? ride.stopTime(last) : ride.section.arrival).add(progress.shift);
    var current = progress;
    var index = current.stopIndex;
    var arrived = false;

    if (fix != null) {
      final projection = ride.line.project(fix, minAlong: math.max(0, current.along - 50));
      if (projection != null && projection.distance < 200) {
        current = current.copyWith(along: math.max(current.along, projection.along));
        for (var k = index; k < last; k++) {
          if (ride.stopAlongs[k] + _leftStopMeters <= current.along) {
            index = k;
          }
        }
        arrived = withStops && ride.stopAlongs[last] <= current.along + _arrivingMeters;
      }
      // The GPS's: where the user is between the stops (see betweenStops)
      if (projection != null && projection.distance < _onPathMeters && (input.accuracy ?? 0) <= _preciseAccuracy) {
        final seen = math.max(current.preciseAlong ?? 0, projection.along);
        current = current.copyWith(preciseAlong: () => seen, preciseAt: () => input.fixAt ?? input.now);
      }
      final end = ride.end;
      arrived = arrived || end != null && metersBetween(fix, end) < 60;
    }
    // Underground: stop times, shifted by the real departure; with only rough positions too, which may stay at a
    // station the vehicle has left (the further of the two)
    if (fix == null ? _noFixFor(current, input.now) : (input.accuracy ?? 0) > _preciseAccuracy) {
      for (var k = index; k < last; k++) {
        if (!input.now.isBefore(ride.stopTime(k).add(current.shift + _dwell))) {
          index = k;
        }
      }
      arrived = arrived || !input.now.isBefore(shiftedArrival);
    }
    current = current.copyWith(stopIndex: math.max(current.stopIndex, index));

    final alightName = ride.section.to?.name ?? '';
    final left = withStops ? last - current.stopIndex : 1;
    final untilArrival = shiftedArrival.difference(input.now);
    // Get ready once the stop before has been left and the arrival is near (without the stops: two minutes before it)
    if (!arrived && (withStops ? left == 1 && untilArrival <= prepareAhead : untilArrival <= const Duration(minutes: 2))) {
      alerts.add(GoAlert(id: 'prepare-${current.step}', title: currentL10n.alertPrepare, body: currentL10n.goNextStop(alightName)));
    }
    if (arrived) {
      alerts.add(GoAlert(id: 'alight-${current.step}', title: currentL10n.alertGetOffNow, body: alightName, urgent: true));
      return _advance(current.copyWith(stopIndex: last), input.now);
    }
    return current;
  }

  GoProgress _advance(GoProgress progress, DateTime? now) {
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
    );
  }

  GoProgress _arrive(GoProgress progress, DateTime now) => GoProgress(
        step: steps.length,
        phase: GoPhase.arrived,
        shift: progress.shift,
        lastFixAt: progress.lastFixAt,
        fired: progress.fired,
        arrivedAt: now,
      );
}
