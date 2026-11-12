import 'package:flutter/foundation.dart';

import '../../core/api/models.dart';
import 'go_tracker.dart';

export '../journey/station_accesses.dart' show StationAccess, bestEntrance, bestExit, stationAccessName, takenEntrance, takenExit;

/// What a card of GO shows, like Citymapper's: a walk; a ride's departures (waiting for it, the transfer walked to it
/// included); the ride on board; getting out of the station after it; the arrival
enum GoCardKind { walk, departures, ride, exit, arrival }

/// One card of GO, swiped like Citymapper's: one moment of the journey
@immutable
class GoCard {
  const GoCard(this.kind, this.step, {this.transfer});

  final GoCardKind kind;

  /// The step it shows ([GoTracker.steps]; their count for the arrival)
  final int step;

  /// Departures: the transfer walked to them, which has no card of its own
  final int? transfer;

  @override
  bool operator ==(Object other) => other is GoCard && other.kind == kind && other.step == step;

  @override
  int get hashCode => Object.hash(kind, step);

  @override
  String toString() => 'GoCard(${kind.name}, $step)';
}

/// The cards of [tracker]'s journey: each move, getting out of the station first after a metro or a train; each ride
/// as its departures then the ride itself, a transfer walked to it in its departures' card; the arrival
List<GoCard> goCards(GoTracker tracker) {
  final steps = tracker.steps;
  final cards = <GoCard>[];
  for (final (index, step) in steps.indexed) {
    if (step.isRide) {
      final transfer = index > 0 && steps[index - 1].section.kind == SectionKind.transfer ? index - 1 : null;
      cards
        ..add(GoCard(GoCardKind.departures, index, transfer: transfer))
        ..add(GoCard(GoCardKind.ride, index));
    } else if (!_walkedToRide(tracker, index)) {
      if (startsWithExit(tracker, index)) {
        cards.add(GoCard(GoCardKind.exit, index));
      }
      cards.add(GoCard(GoCardKind.walk, index));
    }
  }
  return cards..add(GoCard(GoCardKind.arrival, steps.length));
}

/// A transfer before a ride: walked in that ride's departures card
bool _walkedToRide(GoTracker tracker, int step) =>
    tracker.steps[step].section.kind == SectionKind.transfer && step + 1 < tracker.steps.length && tracker.steps[step + 1].isRide;

/// The move [step] starts by getting out of a station: right after a metro or a train (a bus or tram stop has no way
/// out to find)
bool startsWithExit(GoTracker tracker, int step) {
  if (step <= 0 || step >= tracker.steps.length || tracker.steps[step].isRide || _walkedToRide(tracker, step)) {
    return false;
  }
  final ride = tracker.steps[step - 1];
  final mode = ride.section.line?.mode;
  return ride.isRide && (mode == TransportMode.metro || (mode?.isRail ?? false));
}

/// Without the station's ways out, the first meters of a move after a station are getting out of it
const leaveStationMeters = 60.0;

/// The card of what is going on at [progress]: the move's (getting out of the station first, until [exitAlong] meters
/// along it), the ride's departures while waiting (or walking the transfer to them), the ride on board, the arrival
int goCurrentCard(List<GoCard> cards, GoProgress progress, {double? exitAlong}) {
  int indexOf(GoCardKind kind, int step) => cards.indexWhere((card) => card.kind == kind && card.step == step);
  final step = progress.step;
  final index = switch (progress.phase) {
    GoPhase.arrived => cards.length - 1,
    GoPhase.waiting => indexOf(GoCardKind.departures, step),
    GoPhase.onBoard => indexOf(GoCardKind.ride, step),
    GoPhase.moving => () {
        final transfer = cards.indexWhere((card) => card.kind == GoCardKind.departures && card.transfer == step);
        if (transfer >= 0) {
          return transfer;
        }
        final exit = indexOf(GoCardKind.exit, step);
        return exit >= 0 && progress.along < (exitAlong ?? leaveStationMeters) ? exit : indexOf(GoCardKind.walk, step);
      }(),
  };
  return index < 0 ? 0 : index;
}
