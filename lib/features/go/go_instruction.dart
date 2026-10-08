import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import 'go_controller.dart';
import 'go_tracker.dart';

/// What to do now, in a few words
class GoInstruction {
  const GoInstruction({required this.title, this.subtitle, this.detail, this.icon, this.line, this.urgent = false});

  final String title;
  final String? subtitle;
  final String? detail;
  final IconData? icon;

  /// Shown as a badge instead of [icon]
  final LineSummary? line;

  /// Act now (get off, vehicle leaving)
  final bool urgent;
}

String _lineLabel(LineSummary? line) => '${line?.mode.label ?? ''} ${line?.name ?? ''}'.trim();

String _minutes(Duration duration) {
  final minutes = (duration.inSeconds / 60).ceil();
  return minutes <= 0 ? currentL10n.now : currentL10n.inMinutes(minutes);
}

GoInstruction goInstruction(GoState state, DateTime now) {
  final tracker = state.tracker;
  final progress = state.progress;
  final step = tracker.stepOf(progress);

  if (progress.phase == GoPhase.arrived || step == null) {
    final arrivedAt = progress.arrivedAt ?? now;
    final late = arrivedAt.difference(state.journey.arrival).inMinutes;
    return GoInstruction(
      icon: Icons.flag,
      title: currentL10n.goArrived,
      subtitle: state.journey.sections.lastOrNull?.to?.name,
      detail: currentL10n.goArrivedAt(formatClock(arrivedAt)) +
          (late.abs() >= 1 ? currentL10n.goPlannedSuffix(formatClock(state.journey.arrival)) : currentL10n.goAsPlannedSuffix),
    );
  }

  final section = step.section;
  switch (progress.phase) {
    case GoPhase.waiting:
      final vehicle = state.currentVehicle;
      final departure = tracker.expectedDeparture(step, progress, vehicle);
      final platform = vehicle?.platform;
      final boarding = section.boardingPositions;
      return GoInstruction(
        line: section.line,
        icon: Icons.directions_transit,
        title: currentL10n.goTake(_lineLabel(section.line)),
        subtitle: currentL10n.direction(section.headsign ?? ''),
        detail: [
          departure.isBefore(now.subtract(const Duration(seconds: 30)))
              ? currentL10n.goLeftAt(formatClock(departure))
              : currentL10n.goDeparture(_minutes(departure.difference(now)), formatClock(departure)),
          if (vehicle == null) currentL10n.goScheduled,
          if (platform != null && platform.isNotEmpty) currentL10n.goPlatform(platform),
          if (boarding.isNotEmpty && boarding.length < 3) currentL10n.goBoard(boardingPositions(boarding)),
        ].join(' · '),
        urgent: departure.difference(now) <= const Duration(minutes: 1),
      );

    case GoPhase.onBoard:
      final left = tracker.stopsLeft(progress);
      final stops = section.stops;
      final nextStop = progress.stopIndex + 1 < stops.length ? stops[progress.stopIndex + 1].name : null;
      final arrival = section.arrival.add(progress.shift);
      return GoInstruction(
        line: section.line,
        icon: Icons.directions_transit,
        title: left <= 1 ? currentL10n.goGetOffNext : currentL10n.goStayOnBoard,
        subtitle: left <= 1
            ? section.to?.name
            : currentL10n.goGetOffInAt(left, section.to?.name ?? ''),
        detail: [
          if (nextStop != null && left > 1) currentL10n.goNextStop(nextStop),
          currentL10n.goArrivalAround(formatClock(arrival)),
        ].join(' · '),
        urgent: left <= 1,
      );

    case GoPhase.moving:
      // Away from the path: at least the straight distance to the end
      final end = step.end;
      final position = state.position;
      final meters = math.max(tracker.metersLeft(progress),
          end == null || position == null ? 0.0 : metersBetween(position, end));
      final nextStep = progress.step + 1 < tracker.steps.length ? tracker.steps[progress.step + 1] : null;
      final walkMinutes = math.max(1, (meters / 1.2 / 60).ceil());
      final verb = switch (section.kind) {
        SectionKind.bike => currentL10n.goVerbBike,
        SectionKind.car => currentL10n.goVerbCar,
        SectionKind.transfer => currentL10n.goVerbTransferWalk,
        _ => currentL10n.goVerbWalk,
      };
      String? detail;
      if (nextStep != null && nextStep.isRide) {
        final vehicle = state.vehicleStep == progress.step + 1 ? state.vehicle : null;
        final departure = tracker.expectedDeparture(nextStep, progress, vehicle);
        detail = '${_lineLabel(nextStep.section.line)} ${_minutes(departure.difference(now))} (${formatClock(departure)})';
      }
      return GoInstruction(
        icon: section.kind == SectionKind.bike ? Icons.pedal_bike : Icons.directions_walk,
        title: currentL10n.goVerbTo(verb, section.to?.name ?? ''),
        subtitle: meters >= 1 ? '${formatDistance(meters.round())} · ${currentL10n.minutesShort(walkMinutes)}' : null,
        detail: detail,
      );

    case GoPhase.arrived:
      throw StateError('handled above');
  }
}

/// `à l'avant ou au milieu`: where to board along the train
String boardingPositions(List<String> positions) => positions
    .map((position) => switch (position) {
          'front' => currentL10n.boardFront,
          'middle' => currentL10n.boardMiddle,
          'back' => currentL10n.boardBack,
          _ => position,
        })
    .join(' ${currentL10n.or} ');
