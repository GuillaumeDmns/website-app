import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/models.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/time_format.dart';

/// Step followed in GO mode: a ride (wait at the stop, then on board) or a move (walk, transfer, bike…).
class GoStep {
  GoStep._(this.section, this.sectionIndex, this.line, this.stopAlongs);

  factory GoStep(JourneySection section, int sectionIndex) {
    final points = section.shape.length >= 2
        ? [for (final point in section.shape) LatLng(point[1], point[0])]
        : [
            if (section.from != null) LatLng(section.from!.lat, section.from!.lon),
            if (section.to != null) LatLng(section.to!.lat, section.to!.lon),
          ];
    final line = MeasuredPolyline(points);

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
  });

  /// Index in [GoTracker.steps]
  final int step;
  final GoPhase phase;

  /// Meters done along the current step's path
  final double along;

  /// Ride: index of the last stop reached (0 = boarding stop)
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
  const GoInput({required this.now, this.position, this.accuracy, this.speed, this.fixAt, this.vehicle, this.vehicleStep});

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
}

/// Follows a journey from positions, the clock and real time. Pure: [update] returns the new progress and the
/// alerts to give.
///
/// - Moving: position projected on the path; done near its end, or on schedule without a position (underground).
/// - Waiting: boarding detected when moving fast along the line, or assumed after the departure without a position;
///   still at the stop after the departure means the vehicle was missed.
/// - On board: stop reached from the position on the line, or from the stop times (+ shift) without one.
class GoTracker {
  GoTracker(this.journey) : steps = _steps(journey);

  final JourneyOption journey;
  final List<GoStep> steps;

  static const _maxAccuracy = 100.0;
  static const _fixValidity = Duration(seconds: 30);

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

  /// Next ride from the current step on (the current one included)
  GoStep? nextRide(GoProgress progress) {
    for (var i = progress.step; i < steps.length; i++) {
      if (steps[i].isRide) {
        return steps[i];
      }
    }
    return null;
  }

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

  // Manual corrections

  /// Waiting: the user says they boarded; otherwise the step is done
  GoProgress next(GoProgress progress) =>
      progress.phase == GoPhase.waiting ? _board(progress, null, null) : _advance(progress, null);

  /// The user says they are at [step] (a step of the list, or `steps.length` for the arrival)
  GoProgress jumpTo(GoProgress progress, int step) {
    if (step >= steps.length) {
      return _arrive(progress, DateTime.now());
    }
    return GoProgress(
      step: step,
      phase: _phaseOf(step),
      shift: progress.shift,
      lastFixAt: progress.lastFixAt,
      fired: progress.fired,
    );
  }

  /// The user takes the vehicle leaving at [departure] instead of the planned one
  GoProgress takeVehicle(GoProgress progress, DateTime departure) {
    final ride = stepOf(progress);
    if (ride == null || !ride.isRide) {
      return progress;
    }
    final shift = departure.difference(ride.section.departure);
    // Alerts of this ride can be given again for the new vehicle
    final fired = {...progress.fired}..removeWhere((id) => id.endsWith('-${progress.step}'));
    return progress.copyWith(phase: GoPhase.waiting, shift: shift, issue: () => null, fired: fired);
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
      alerts.add(GoAlert(id: 'arrived', title: 'Vous êtes arrivé', body: journey.sections.lastOrNull?.to?.name));
    }

    final fresh = alerts.where((alert) => !current.fired.contains(alert.id)).toList();
    if (fresh.isNotEmpty) {
      current = current.copyWith(fired: {...current.fired, ...fresh.map((alert) => alert.id)});
    }
    return (current, fresh);
  }

  LatLng? _usableFix(GoInput input) {
    final position = input.position;
    if (position == null || (input.accuracy ?? 0) > _maxAccuracy) {
      return null;
    }
    final at = input.fixAt ?? input.now;
    return input.now.difference(at) <= _fixValidity ? position : null;
  }

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
            alerts.add(GoAlert(id: 'offroute-${current.step}', title: 'Vous vous êtes écarté du trajet',
                body: 'Recalculez l\'itinéraire depuis votre position'));
          }
        } else if (projection.distance < 80) {
          current = current.copyWith(offRouteSince: () => null, issue: () => current.issue == GoIssue.offRoute ? null : current.issue);
        }
      }
      final end = step.end;
      done = step.line.length - current.along < 40 || (end != null && metersBetween(fix, end) < 40);

      // Already riding the next vehicle
      if (!done && nextStep != null && nextStep.isRide && (input.speed ?? 0) >= 4) {
        final onLine = nextStep.line.project(fix);
        done = onLine != null && onLine.distance < 50 && onLine.along > 80;
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
            title: 'Pressez le pas',
            body: '${line?.mode.label ?? ''} ${line?.name ?? ''} dans ${(margin / 60).ceil()} min, '
                'encore ${metersLeft(current).round()} m',
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
    final lineLabel = '${line?.mode.label ?? ''} ${line?.name ?? ''}'.trim();
    final vehicle = input.vehicleOf(progress.step);
    final departure = expectedDeparture(ride, progress, vehicle);
    final untilDeparture = departure.difference(input.now);
    var current = progress;

    if (vehicle?.cancelled == true && current.issue == null) {
      current = current.copyWith(issue: () => GoIssue.cancelled);
      alerts.add(GoAlert(id: 'cancel-${current.step}', title: '$lineLabel supprimé', body: 'Prenez le suivant ou recalculez', urgent: true));
      return current;
    }

    // Delay of the planned vehicle
    if (vehicle != null && vehicle.time.difference(plannedDeparture(ride, current)) >= const Duration(minutes: 3)) {
      alerts.add(GoAlert(
        id: 'delay-${current.step}',
        title: '$lineLabel en retard',
        body: 'Départ prévu à ${formatClock(vehicle.time)}${vehicle.platform != null ? ', voie ${vehicle.platform}' : ''}',
      ));
    }

    if (untilDeparture > Duration.zero && untilDeparture <= const Duration(minutes: 2)) {
      alerts.add(GoAlert(
        id: 'soon-${current.step}',
        title: '$lineLabel dans ${math.max(1, untilDeparture.inSeconds ~/ 60)} min',
        body: 'Direction ${ride.section.headsign ?? ''}',
      ));
    }

    // Moving fast along the line: on board
    if (fix != null && (input.speed ?? 0) >= 4) {
      final projection = ride.line.project(fix);
      if (projection != null && projection.distance < 60 && projection.along > 80) {
        return _board(current, input.now, departure);
      }
    }

    if (untilDeparture <= const Duration(seconds: -90) && fix != null) {
      final start = ride.start;
      final stillAtStop = start != null && metersBetween(fix, start) < 150 && (input.speed ?? 0) < 2;
      if (stillAtStop) {
        if (current.issue == null && !current.fired.contains('missed-${current.step}')) {
          current = current.copyWith(issue: () => GoIssue.missed);
          alerts.add(GoAlert(id: 'missed-${current.step}', title: '$lineLabel manqué',
              body: 'Prenez le suivant ou recalculez l\'itinéraire'));
        }
        return current;
      }
      return _board(current, input.now, departure);
    }

    // No position (underground station): assume the user boarded
    if (untilDeparture <= const Duration(seconds: -60) && _noFixFor(current, input.now) && current.issue == null) {
      return _board(current, input.now, departure);
    }
    return current;
  }

  GoProgress _board(GoProgress progress, DateTime? now, DateTime? departure) {
    final ride = stepOf(progress);
    if (ride == null) {
      return progress;
    }
    // Schedule shift from the real departure (clamped: a wrong detection must not shift by hours)
    var shift = progress.shift;
    if (departure != null) {
      final measured = departure.difference(ride.section.departure);
      shift = Duration(seconds: measured.inSeconds.clamp(-120, 3600));
    }
    return progress.copyWith(phase: GoPhase.onBoard, along: 0, stopIndex: 0, shift: shift, issue: () => null);
  }

  GoProgress _ride(GoProgress progress, GoInput input, LatLng? fix, List<GoAlert> alerts) {
    final ride = steps[progress.step];
    final stops = ride.section.stops;
    final last = math.max(0, stops.length - 1);
    var current = progress;
    var index = current.stopIndex;
    var reachedEnd = false;

    if (fix != null) {
      final projection = ride.line.project(fix, minAlong: math.max(0, current.along - 50));
      if (projection != null && projection.distance < 200) {
        current = current.copyWith(along: math.max(current.along, projection.along));
        for (var k = index; k < ride.stopAlongs.length; k++) {
          if (ride.stopAlongs[k] <= current.along + 40) {
            index = k;
          }
        }
      }
      final end = ride.end;
      reachedEnd = end != null && metersBetween(fix, end) < 60;
    } else if (_noFixFor(current, input.now)) {
      // Underground: stop times, shifted by the real departure
      for (var k = index; k <= last; k++) {
        if (!input.now.isBefore(ride.stopTime(k).add(current.shift))) {
          index = k;
        }
      }
      if (stops.isEmpty) {
        reachedEnd = !input.now.isBefore(ride.section.arrival.add(current.shift));
      }
    }
    current = current.copyWith(stopIndex: math.max(current.stopIndex, index));

    final alightName = ride.section.to?.name ?? '';
    final left = stops.isEmpty ? (reachedEnd ? 0 : 1) : last - current.stopIndex;
    final untilArrival = ride.section.arrival.add(current.shift).difference(input.now);
    if (left == 1 || (left == 2 && untilArrival <= const Duration(minutes: 2))) {
      alerts.add(GoAlert(id: 'prepare-${current.step}', title: 'Préparez-vous à descendre', body: 'Prochain arrêt : $alightName'));
    }
    if (left <= 0 || reachedEnd) {
      alerts.add(GoAlert(id: 'alight-${current.step}', title: 'Descendez maintenant', body: alightName, urgent: true));
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
