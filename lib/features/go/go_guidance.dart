import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/utils/geo.dart';
import '../../l10n/l10n.dart';
import 'go_controller.dart';
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
/// instructions). Navitia's lengths are scaled to the path drawn, which may be a little longer or shorter.
Maneuver? nextManeuver(GoStep step, double along) {
  final walks = step.section.steps;
  if (step.isRide || walks.isEmpty) {
    return null;
  }
  final total = (step.section.length ?? 0) > 0 ? step.section.length! : walks.last.offset + walks.last.length;
  final scale = total > 0 && step.line.length > 0 ? step.line.length / total : 1.0;
  for (final walk in walks) {
    // The first one says where to head from the start: the map shows it
    if (walk.offset == 0) {
      continue;
    }
    final at = walk.offset * scale;
    if (at > along + 3) {
      return Maneuver(walk: walk, meters: at - along);
    }
  }
  return null;
}

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

/// Share of the journey done (0 to 1), by the planned durations of its steps
double journeyFraction(GoState state) {
  final tracker = state.tracker;
  final progress = state.progress;
  if (progress.phase == GoPhase.arrived) {
    return 1;
  }
  var total = 0;
  var done = 0.0;
  for (final (index, step) in tracker.steps.indexed) {
    final duration = step.section.duration;
    total += duration;
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
  return total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
}
