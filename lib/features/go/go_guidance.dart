import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/api/models.dart';
import '../../core/utils/geo.dart';
import '../../l10n/l10n.dart';
import '../../core/map/map_overlay.dart';
import 'go_state.dart';
import 'go_tracker.dart';

/// A turn ahead on a walk, for turn-by-turn guidance: Navitia's instruction placed along the walking path
@immutable
class Maneuver {
  const Maneuver({required this.walk, required this.meters});

  final WalkStep walk;

  /// From the user to the turn, along the path
  final double meters;

  IconData get icon => turnIcon(walk.direction);

  /// `Tournez à gauche`
  String get label => turnLabel(walk.direction);
}

/// The next turn of the walk [step] after [along] meters on its path, null when none is left (or without
/// instructions). Only real turns count: Navitia also lists going straight on, arriving and entering the station,
/// which tell nothing to do. Where [walkStepAlongs] puts it on the path drawn.
Maneuver? nextManeuver(GoStep step, double along) {
  final walks = step.section.steps;
  if (step.isRide || walks.isEmpty) {
    return null;
  }
  final alongs = walkStepAlongs(step);
  for (final (index, walk) in walks.indexed) {
    if (!_isTurn(walk)) {
      continue;
    }
    final at = alongs[index];
    if (at > along + 3) {
      return Maneuver(walk: walk, meters: at - along);
    }
  }
  return null;
}

/// Turns of at most this many degrees are going straight on
const straightOn = 20;

/// Whether Navitia's instruction [walk] is a turn to make (the first one says where to head from the start: the map
/// shows it)
bool _isTurn(WalkStep walk) => walk.offset > 0 && walk.direction.abs() > straightOn;

/// Where each of Navitia's instructions of the walk [step] starts on its path drawn, in meters along it, in the order
/// of `section.steps`. Navitia's lengths between its turns are the path's, and a turn's `direction` the angle of the
/// path's corner there, but its offsets don't count the way from the start to the street, nor a station's corridors,
/// as drawn (14 m more from 3 Avenue Léon de Bertalot, 150 m less out of Charles de Gaulle - Étoile): scaled to the
/// path, a turn stood tens of meters before its corner. So the offsets are moved by the shift most turns agree with
/// (a corner turning the same way there), one turn alone only near its scaled offset, and each turn is put onto such
/// a corner close by, the instructions after it following it; without any, the offsets scaled to the path.
List<double> walkStepAlongs(GoStep step) => _walkStepAlongs[step] ??= _placeWalkSteps(step);

final _walkStepAlongs = Expando<List<double>>();

/// A corner of the path within this many degrees of an instruction's turn is where it is
const _turnMatch = 30;

/// Turns agree on a shift of the offsets when their corners are within this many meters of it
const _agreeMeters = 10.0;

/// A turn is put onto a corner at most this many meters from where the shifted offsets say
const _snapMeters = 25.0;

List<double> _placeWalkSteps(GoStep step) {
  final walks = step.section.steps;
  final line = step.line;
  if (walks.isEmpty) {
    return const [];
  }
  final total = (step.section.length ?? 0) > 0 ? step.section.length! : walks.last.offset + walks.last.length;
  final scale = total > 0 && line.length > 0 ? line.length / total : 1.0;
  final corners = _corners(line);
  final turns = walks.where(_isTurn).toList();
  bool fits(WalkStep walk, _Corner corner) => _degreesBetween(corner.angle, walk.direction).abs() <= _turnMatch;
  bool agrees(WalkStep walk, double shift) =>
      corners.any((corner) => fits(walk, corner) && (corner.along - walk.offset - shift).abs() <= _agreeMeters);

  // The shift most turns agree with, the closest to the scaled offsets among equals; one turn alone within what the
  // path and Navitia's length differ by
  double? shift;
  var agreeing = 0;
  var fromScaled = double.infinity;
  final reach = _snapMeters + (line.length - total).abs();
  for (final turn in turns) {
    for (final corner in corners) {
      if (!fits(turn, corner)) {
        continue;
      }
      final candidate = corner.along - turn.offset;
      final away = (candidate - turn.offset * (scale - 1)).abs();
      final count = turns.where((other) => agrees(other, candidate)).length;
      if ((count > 1 || away <= reach) && (count > agreeing || count == agreeing && away < fromScaled)) {
        shift = candidate;
        agreeing = count;
        fromScaled = away;
      }
    }
  }

  final alongs = <double>[];
  var previous = 0.0;
  for (final walk in walks) {
    var at = shift == null ? walk.offset * scale : walk.offset + shift;
    if (shift != null && _isTurn(walk)) {
      _Corner? closest;
      for (final corner in corners) {
        final distance = (corner.along - at).abs();
        if (fits(walk, corner) &&
            corner.along > previous &&
            distance <= _snapMeters &&
            (closest == null || distance < (closest.along - at).abs())) {
          closest = corner;
        }
      }
      if (closest != null) {
        at = closest.along;
        shift = at - walk.offset;
      }
    }
    // The first one starts where the path does
    at = walk.offset == 0 ? 0.0 : at.clamp(previous, line.length);
    alongs.add(at);
    previous = at;
  }
  return alongs;
}

/// A corner of a path: [angle] degrees turned there (negative to the left), [along] meters from its start
typedef _Corner = ({double along, double angle});

/// The corners of [line] turning more than going straight on
List<_Corner> _corners(MeasuredPolyline line) {
  final points = line.points;
  final along = line.cumulative;
  final corners = <_Corner>[];
  for (var i = 1; i < points.length - 1; i++) {
    // From and to points a meter away at least: a point given twice turns nowhere
    var before = i - 1;
    while (before > 0 && along[i] - along[before] < 1) {
      before--;
    }
    var after = i + 1;
    while (after < points.length - 1 && along[after] - along[i] < 1) {
      after++;
    }
    if (along[i] - along[before] < 1 || along[after] - along[i] < 1) {
      continue;
    }
    final angle = _degreesBetween(bearingBetween(points[i], points[after]), bearingBetween(points[before], points[i]));
    if (angle.abs() > straightOn) {
      corners.add((along: along[i], angle: angle));
    }
  }
  return corners;
}

/// [a] less [b], from -180 to 180 degrees
double _degreesBetween(num a, num b) => (a - b + 540) % 360 - 180;

/// The arrow of a turn of [direction] degrees (negative to the left)
IconData turnIcon(int direction) => switch (direction) {
      < -135 => Icons.u_turn_left,
      < -60 => Icons.turn_left,
      < -20 => Icons.turn_slight_left,
      <= 20 => Icons.straight,
      <= 60 => Icons.turn_slight_right,
      <= 135 => Icons.turn_right,
      _ => Icons.u_turn_right,
    };

String turnLabel(int direction) => switch (direction) {
      < -135 || > 135 => currentL10n.goTurnBack,
      < -60 => currentL10n.goTurnLeft,
      < -20 => currentL10n.goTurnSlightLeft,
      <= 20 => currentL10n.goStraightOn,
      <= 60 => currentL10n.goTurnSlightRight,
      _ => currentL10n.goTurnRight,
    };

enum MarginLevel {
  /// A minute or more to spare
  ahead,

  /// Less than a minute: walk faster
  hurry,

  /// At this pace, the vehicle leaves before the user gets there
  late,
}

/// Time to spare walking to the next ride: its departure, less now and the walk left at the user's pace
typedef WalkMargin = ({Duration margin, MarginLevel level, DateTime departure});

/// Usual walking pace when the user's own isn't known yet (m/s)
const defaultWalkSpeed = 1.2;

/// While walking to a ride, how much time the user has to spare; null otherwise
WalkMargin? walkMargin(GoState state, DateTime now) {
  final tracker = state.tracker;
  final progress = state.progress;
  final step = tracker.stepOf(progress);
  if (step == null || step.isRide || progress.phase != GoPhase.moving || progress.step + 1 >= tracker.steps.length) {
    return null;
  }
  final ride = tracker.steps[progress.step + 1];
  if (!ride.isRide) {
    return null;
  }
  final vehicle = state.vehicleStep == progress.step + 1 ? state.vehicle : null;
  final departure = tracker.expectedDeparture(ride, progress, vehicle);
  final speed = movePace(state, step);
  final walk = Duration(seconds: (metersToGo(state) / speed).round());
  final margin = departure.difference(now) - walk;
  final level = margin >= const Duration(minutes: 1)
      ? MarginLevel.ahead
      : margin >= Duration.zero
          ? MarginLevel.hurry
          : MarginLevel.late;
  return (margin: margin, level: level, departure: departure);
}

/// The user's pace on [step] (m/s): measured when known, within what is usual on foot or by bike
double movePace(GoState state, GoStep step) => step.section.kind == SectionKind.bike
    ? (state.walkSpeed ?? 4.2).clamp(2.5, 8.0)
    : (state.walkSpeed ?? defaultWalkSpeed).clamp(0.8, 2.0);

/// Meters left on the move in progress: along the path, at least the straight distance to its end (away from it)
double metersToGo(GoState state) {
  final step = state.tracker.stepOf(state.progress);
  final end = step?.end;
  final position = state.position;
  return math.max(state.tracker.metersLeft(state.progress), end == null || position == null ? 0.0 : metersBetween(position, end));
}

/// Seconds of the journey done, by the planned durations of its steps: the steps before the current one, and the
/// share of the current one done (along its path on foot, by its stops on board)
double journeySecondsDone(GoTracker tracker, GoProgress progress) {
  var done = 0.0;
  for (final (index, step) in tracker.steps.indexed) {
    final duration = step.section.duration;
    if (index < progress.step) {
      done += duration;
    } else if (index == progress.step) {
      final fraction = switch (progress.phase) {
        GoPhase.moving => step.line.length == 0 ? 0.0 : progress.along / step.line.length,
        GoPhase.onBoard => step.section.stops.length < 2 ? 0.5 : progress.stopIndex / (step.section.stops.length - 1),
        _ => 0.0,
      };
      done += duration * fraction.clamp(0.0, 1.0);
    }
  }
  return done;
}

/// Share of the journey done (0 to 1), by the planned durations of its steps
double journeyFraction(GoState state) {
  final tracker = state.tracker;
  if (state.progress.phase == GoPhase.arrived) {
    return 1;
  }
  final total = tracker.steps.fold(0, (total, step) => total + step.section.duration);
  return total == 0 ? 0 : (journeySecondsDone(tracker, state.progress) / total).clamp(0.0, 1.0);
}

/// On foot or by bike, the map follows the user with the way ahead up, like Citymapper: a view from above makes
/// little sense when walking. Where the device has a compass, the map turns with it instead (the phone in the hand
/// turns, the map turns). Only for the move in progress, when it is the step shown.
MapFollow? goFollow(GoState state, int shownStep) {
  final progress = state.progress;
  final position = state.position;
  final step = state.tracker.stepOf(progress);
  if (position == null || step == null || step.isRide || progress.phase != GoPhase.moving || shownStep != progress.step) {
    return null;
  }
  // First person on foot and by bike, tilted to see the way ahead; overhead in a car, or in whatever goes faster than
  // the move (followed close up, a vehicle is a blur)
  final firstPerson = !state.inVehicle &&
      switch (step.section.kind) {
        SectionKind.walk || SectionKind.transfer || SectionKind.bike => true,
        _ => false,
      };
  if (!firstPerson) {
    return MapFollow.overhead(position, user: true);
  }
  return MapFollow(
    position: position,
    bearing: step.headingFrom(position, progress.along),
    compass: true,
    pitch: MapFollow.firstPersonPitch,
    user: true,
  );
}

/// Whether a move is ridden in a vehicle the journey doesn't know of: faster than on foot (4.5 m/s) or by bike (9 m/s)
/// two fixes in a row; back on foot after fifteen slower than 60 % of that (a red light doesn't make a car a walk)
class GoVehicleSpeed {
  int _fast = 0;
  int _slow = 0;
  bool _inVehicle = false;

  bool get inVehicle => _inVehicle;

  /// Faster than this on a move of [kind] (m/s): a vehicle
  static double limitOn(SectionKind kind) => kind == SectionKind.bike ? 9 : 4.5;

  /// A fix's [speed] (the one it is sure of, `sureSpeed`) on a move of [kind]
  bool add(SectionKind kind, double? speed) {
    if (speed == null) {
      return _inVehicle;
    }
    final limit = limitOn(kind);
    if (speed > limit) {
      _fast++;
      _slow = 0;
    } else if (speed < limit * 0.6) {
      _slow++;
      _fast = 0;
    }
    if (_fast >= 2) {
      _inVehicle = true;
    } else if (_slow >= 15) {
      _inVehicle = false;
    }
    return _inVehicle;
  }

  void reset() {
    _fast = 0;
    _slow = 0;
    _inVehicle = false;
  }
}

/// Waiting for [ride]: the map frames where to board, with the user at [position] when they are close to it (on their
/// way in, at the other end of a platform), not the whole ride
List<LatLng> goWaitingFit(GoStep ride, LatLng? position) {
  final start = ride.start;
  if (start == null) {
    return const [];
  }
  return [start, if (position != null && metersBetween(position, start) <= 400) position];
}

/// The departure to take instead of a missed or cancelled one: the next one still to come, not cancelled (for a
/// cancellation, one leaving after the planned time, the cancelled one aside); null when the departures don't say
Ride? replacementRide(List<Ride> rides, GoIssue issue, DateTime planned, DateTime now) => rides
    .where((ride) => ride.departure.time.isAfter(now) && ride.departure.cancelled != true)
    .where((ride) => issue != GoIssue.cancelled || ride.departure.time.isAfter(planned.add(const Duration(seconds: 30))))
    .firstOrNull;
