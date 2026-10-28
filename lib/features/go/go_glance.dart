import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/models.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import '../journey/journey_labels.dart';
import 'go_guidance.dart';
import 'go_instruction.dart';
import 'go_state.dart';
import 'go_tracker.dart';

/// How a moment of GO feels: all well, needs attention (late, missed, off the way), act now (get off, leaving)
enum GoTone { ok, warn, urgent }

/// One moment of GO read at a glance, like the banner over the map and the lock screen show it: a few words of
/// context, what to do in large, one figure (meters, minutes, stops) and where. One main piece of information, the
/// rest stays in the panel.
@immutable
class GoGlance {
  const GoGlance({
    required this.kicker,
    required this.action,
    required this.tone,
    this.hero,
    this.heroUnit,
    this.place,
    this.icon,
    this.line,
  });

  /// Context, small, above the action: `À pied · vers Gare d'Argenteuil`, `Direction Gallieni`
  final String kicker;

  /// What to do: `Tournez à droite`, `Prenez le J`, `Descendez à Saint-Lazare`
  final String action;
  final GoTone tone;

  /// The figure that counts down: `120` m, `4` min, `3` arrêts
  final String? hero;
  final String? heroUnit;

  /// Where, under the action: the street, the direction and where to board, the next stop
  final String? place;
  final IconData? icon;

  /// Shown as a badge instead of [icon]
  final LineSummary? line;

  /// The figure and its unit on one line, for the notification's chip
  String? get heroText => hero == null ? null : [hero!, ?heroUnit].join(' ');
}

/// On the last stretch of a ride, getting off is what to do now (red) from this long before the arrival
const getOffSoon = Duration(minutes: 2);

/// `120` `m`, `1,2` `km`: a distance as a figure and its unit, rounded as people read it while walking
(String, String) _distance(double meters) {
  if (meters < 1000) {
    final rounded = meters < 100 ? (meters / 5).round() * 5 : (meters / 10).round() * 10;
    return ('${math.max(0, rounded)}', 'm');
  }
  return (NumberFormat('0.0', currentL10n.localeName).format(meters / 1000), 'km');
}

GoGlance goGlance(GoState state, DateTime now) {
  final tracker = state.tracker;
  final progress = state.progress;
  final step = tracker.stepOf(progress);
  final instruction = goInstruction(state, now);
  final issue = progress.issue != null;

  if (progress.phase == GoPhase.arrived || step == null) {
    return GoGlance(
      kicker: state.journey.sections.lastOrNull?.to?.name ?? '',
      action: instruction.title,
      place: instruction.detail,
      icon: Icons.flag,
      tone: GoTone.ok,
    );
  }

  final section = step.section;
  final line = section.line;
  switch (progress.phase) {
    case GoPhase.waiting:
      final departure = tracker.expectedDeparture(step, progress, state.currentVehicle);
      final minutes = minutesLeft(departure.difference(now));
      final platform = platformLabel(line, state.currentVehicle?.platform);
      final boarding = section.boardingPositions;
      final towards = currentL10n.direction(section.headsign ?? '');
      // The vehicle missed (or cancelled) and the next one kept: said first, with how much later the arrival is
      if (state.retained case final retained? when retained.step == progress.step) {
        final later = retained.later.roundedMinutes;
        return GoGlance(
          line: line,
          kicker: [section.from?.name ?? '', ?platform?._capitalized].where((part) => part.isNotEmpty).join(' · '),
          action: retained.cancelled ? currentL10n.goCancelledShort(line?.label ?? '') : currentL10n.goMissedShort(line?.label ?? ''),
          hero: later > 0 ? '+$later' : null,
          heroUnit: later > 0 ? currentL10n.minutesUnit : null,
          place: currentL10n.goRetained,
          tone: GoTone.warn,
        );
      }
      // A train's platform changed: the new one is what to do, the old one recalled
      final previous = platform == null ? null : previousPlatform(state);
      if (platform != null && previous != null) {
        return GoGlance(
          line: line,
          kicker: currentL10n.goPlatformChangedKicker,
          action: currentL10n.goGoToPlatform(platform),
          hero: minutes == 0 ? currentL10n.now : '$minutes',
          heroUnit: minutes == 0 ? null : currentL10n.minutesUnit,
          place: '${line?.label ?? ''} · $towards · ${currentL10n.goPlatformInsteadOf(platform, platformLabel(line, previous) ?? previous)}',
          tone: GoTone.warn,
        );
      }
      return GoGlance(
        line: line,
        icon: Icons.directions_transit,
        kicker: [section.from?.name ?? '', ?platform?._capitalized].where((part) => part.isNotEmpty).join(' · '),
        action: instruction.title,
        hero: departure.isBefore(now) && minutes == 0 ? null : (minutes == 0 ? currentL10n.now : '$minutes'),
        heroUnit: minutes == 0 ? null : currentL10n.minutesUnit,
        place: [
          towards,
          if (boarding.isNotEmpty && boarding.length < 3) currentL10n.goBoard(boardingPositionNames(boarding)),
        ].join(' · '),
        tone: issue ? GoTone.warn : (instruction.urgent ? GoTone.urgent : GoTone.ok),
      );

    case GoPhase.onBoard:
      final left = tracker.stopsLeft(progress);
      final stops = section.stops;
      final nextStop = progress.stopIndex + 1 < stops.length ? stops[progress.stopIndex + 1].name : null;
      final arrival = section.arrival.add(progress.shift);
      // The last stretch counts the minutes left, red once the stop is close: a direct train's ten minutes to its only
      // stop are no emergency
      final last = left <= 1;
      final minutes = minutesLeft(arrival.difference(now));
      return GoGlance(
        line: line,
        icon: Icons.directions_transit,
        kicker: currentL10n.direction(section.headsign ?? ''),
        action: last ? currentL10n.goGetOffNext : currentL10n.goGetOffAtStop(section.to?.name ?? ''),
        hero: last ? (minutes == 0 ? currentL10n.now : '$minutes') : '$left',
        heroUnit: last ? (minutes == 0 ? null : currentL10n.minutesUnit) : currentL10n.goStopsUnit(left),
        place: [
          if (last) section.to?.name ?? '' else if (nextStop != null) currentL10n.goNextStopShort(nextStop),
          currentL10n.arrivalAt(formatClock(arrival)),
        ].where((part) => part.isNotEmpty).join(' · '),
        tone: last && arrival.difference(now) <= getOffSoon ? GoTone.urgent : (issue ? GoTone.warn : GoTone.ok),
      );

    case GoPhase.moving:
      final margin = walkMargin(state, now);
      final late = margin != null && margin.level != MarginLevel.ahead;
      final tone = issue || late ? GoTone.warn : GoTone.ok;
      final nextStep = progress.step + 1 < tracker.steps.length ? tracker.steps[progress.step + 1] : null;
      final nextLine = nextStep != null && nextStep.isRide ? nextStep.section.line : null;
      final mode = section.kind == SectionKind.bike ? currentL10n.goKickerByBike : currentL10n.goKickerOnFoot;
      final towards = section.to?.name ?? '';
      final meters = metersToGo(state);

      // Off the way: said first, with the recalculation coming on its own
      if (progress.issue == GoIssue.offRoute) {
        final at = state.recalculateAt;
        return GoGlance(
          icon: Icons.wrong_location,
          kicker: currentL10n.goKickerTowards(mode, towards),
          action: currentL10n.goOffRoute,
          place: state.recalculating
              ? currentL10n.recalculate
              : at == null
                  ? null
                  : currentL10n.goRecalculateIn(math.max(0, at.difference(now).inSeconds)),
          tone: GoTone.warn,
        );
      }
      final maneuver = nextManeuver(step, progress.along);
      // Too slow for the ride: walking faster is what to do, unless a turn is right there
      if (late && nextLine != null && (maneuver == null || maneuver.meters > 30)) {
        final (figure, unit) = _distance(meters);
        final vehicle = state.vehicleStep == progress.step + 1 ? state.vehicle : null;
        return GoGlance(
          icon: Icons.directions_run,
          kicker: currentL10n.goKickerTowards(mode, towards),
          action: margin.level == MarginLevel.hurry ? currentL10n.goMarginHurry : currentL10n.goMarginLate,
          hero: figure,
          heroUnit: unit,
          place: [
            // The same meters as the figure
            currentL10n.alertHurryBody(
                nextLine.label, math.max(0, margin.departure.difference(now).inMinutes), unit == 'm' ? int.parse(figure) : meters.round()),
            ?platformLabel(nextLine, vehicle?.platform),
          ].join(' · '),
          tone: GoTone.warn,
        );
      }
      if (maneuver != null && maneuver.meters <= maneuverAhead) {
        final (figure, unit) = _distance(maneuver.meters);
        return GoGlance(
          icon: maneuver.icon,
          kicker: currentL10n.goKickerTowards(mode, towards),
          action: maneuver.label,
          hero: figure,
          heroUnit: unit,
          place: maneuver.walk.name ?? instruction.towards,
          tone: tone,
        );
      }
      final walkMinutes = math.max(1, (meters / movePace(state, step) / 60).ceil());
      // Through a station: the line to follow is what the signs say
      if (section.kind == SectionKind.transfer && nextLine != null) {
        return GoGlance(
          icon: Icons.transfer_within_a_station,
          kicker: currentL10n.goKickerTransfer(section.from?.name ?? ''),
          action: currentL10n.goFollowLine(nextLine.label),
          hero: '$walkMinutes',
          heroUnit: currentL10n.minutesUnit,
          place: [currentL10n.direction(nextStep!.section.headsign ?? ''), if (meters >= 1) formatDistance(meters.round())].join(' · '),
          tone: tone,
        );
      }
      return GoGlance(
        icon: moveIcon(section.kind),
        kicker: mode,
        action: instruction.title,
        hero: '$walkMinutes',
        heroUnit: currentL10n.minutesUnit,
        place: [if (meters >= 1) formatDistance(meters.round()), ?instruction.detail].join(' · '),
        tone: tone,
      );

    case GoPhase.arrived:
      throw StateError('handled above');
  }
}

/// The platform announced before the current one for the ride waited for, when it changed (from the platform
/// alerts given: `platform-<step>-<platform>`); null otherwise
String? previousPlatform(GoState state) {
  final step = state.progress.step;
  final current = state.currentVehicle?.platform?.trim();
  if (current == null || current.isEmpty) {
    return null;
  }
  final prefix = 'platform-$step-';
  return state.progress.fired
      .where((id) => id.startsWith(prefix) && id != '$prefix$current')
      .map((id) => id.substring(prefix.length))
      .lastOrNull;
}

extension on String {
  /// `voie 3` → `Voie 3`, at the start of a line
  String get _capitalized => isEmpty ? this : this[0].toUpperCase() + substring(1);
}
