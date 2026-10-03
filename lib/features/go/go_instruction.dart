import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/time_format.dart';
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
  return minutes <= 0 ? 'maintenant' : 'dans $minutes min';
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
      title: 'Vous êtes arrivé',
      subtitle: state.journey.sections.lastOrNull?.to?.name,
      detail: 'À ${formatClock(arrivedAt)}'
          '${late.abs() >= 1 ? ' (prévu ${formatClock(state.journey.arrival)})' : ', comme prévu'}',
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
        title: 'Prenez le ${_lineLabel(section.line)}',
        subtitle: 'Direction ${section.headsign ?? ''}',
        detail: [
          departure.isBefore(now.subtract(const Duration(seconds: 30)))
              ? 'Parti à ${formatClock(departure)}'
              : 'Départ ${_minutes(departure.difference(now))} (${formatClock(departure)})',
          if (vehicle == null) 'horaire prévu',
          if (platform != null && platform.isNotEmpty) 'voie $platform',
          if (boarding.isNotEmpty && boarding.length < 3) 'montez ${boarding.map(_position).join(' ou ')}',
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
        title: left <= 1 ? 'Descendez au prochain arrêt' : 'Restez à bord',
        subtitle: left <= 1
            ? section.to?.name
            : 'Descendez dans $left arrêts à ${section.to?.name ?? ''}',
        detail: [
          if (nextStop != null && left > 1) 'Prochain arrêt : $nextStop',
          'Arrivée vers ${formatClock(arrival)}',
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
        SectionKind.bike => 'Pédalez',
        SectionKind.car => 'Roulez',
        SectionKind.transfer => 'Correspondance : marchez',
        _ => 'Marchez',
      };
      String? detail;
      if (nextStep != null && nextStep.isRide) {
        final vehicle = state.vehicleStep == progress.step + 1 ? state.vehicle : null;
        final departure = tracker.expectedDeparture(nextStep, progress, vehicle);
        detail = '${_lineLabel(nextStep.section.line)} ${_minutes(departure.difference(now))} (${formatClock(departure)})';
      }
      return GoInstruction(
        icon: section.kind == SectionKind.bike ? Icons.pedal_bike : Icons.directions_walk,
        title: '$verb jusqu\'à ${section.to?.name ?? ''}',
        subtitle: meters >= 1 ? '${formatDistance(meters.round())} · $walkMinutes min' : null,
        detail: detail,
      );

    case GoPhase.arrived:
      throw StateError('handled above');
  }
}

String _position(String position) => switch (position) {
      'front' => 'à l\'avant',
      'middle' => 'au milieu',
      'back' => 'à l\'arrière',
      _ => position,
    };

/// One line per step of the journey, for the step list
String goStepLabel(GoStep step) {
  final section = step.section;
  return switch (section.kind) {
    SectionKind.transit => '${_lineLabel(section.line)} → ${section.headsign ?? ''}'
        '${section.stops.length > 1 ? ' · ${section.stops.length - 1} arrêt${section.stops.length > 2 ? 's' : ''}' : ''}',
    SectionKind.transfer => 'Correspondance ${formatDuration(section.duration)}',
    SectionKind.bike => 'Vélo ${formatDuration(section.duration)} jusqu\'à ${section.to?.name ?? ''}',
    _ => 'Marche ${formatDuration(section.duration)} jusqu\'à ${section.to?.name ?? ''}',
  };
}
