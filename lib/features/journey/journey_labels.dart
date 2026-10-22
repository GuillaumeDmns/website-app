import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../l10n/l10n.dart';

/// User-facing name of a Navitia journey type
String journeyTypeLabel(String? type) => switch (type) {
      'best' => currentL10n.journeyBest,
      'rapid' => currentL10n.journeyRapid,
      'comfort' => currentL10n.journeyComfort,
      'less_fallback_walk' => currentL10n.journeyLessWalk,
      'non_pt_walk' => currentL10n.journeyWalk,
      'non_pt_bike' || 'non_pt_bss' => currentL10n.journeyBike,
      'bike_share' => currentL10n.journeyBikeShare,
      'car' => currentL10n.journeyCar,
      _ => currentL10n.journeyOther,
    };

/// Icon of a move: a bike for a bike ride, a walker otherwise
IconData moveIcon(SectionKind kind) => kind == SectionKind.bike ? Icons.pedal_bike : Icons.directions_walk;

/// What to do on a move, in GO's instructions: `Marchez`, `Pédalez`, `Correspondance : marchez`
String moveVerb(SectionKind kind) => switch (kind) {
      SectionKind.bike => currentL10n.goVerbBike,
      SectionKind.car => currentL10n.goVerbCar,
      SectionKind.transfer => currentL10n.goVerbTransferWalk,
      _ => currentL10n.goVerbWalk,
    };

/// `à l'avant ou au milieu`: where to board along the train, from a section's `boardingPositions`
String boardingPositionNames(List<String> positions) => positions
    .map((position) => switch (position) {
          'front' => currentL10n.boardFront,
          'middle' => currentL10n.boardMiddle,
          'back' => currentL10n.boardBack,
          _ => position,
        })
    .join(' ${currentL10n.or} ');

/// `Montez à l'avant`, or `Montez n'importe où` when the whole train fits
String boardingLabel(List<String> positions) =>
    positions.length >= 3 ? currentL10n.boardAnywhere : currentL10n.boardAt(boardingPositionNames(positions));

/// `voie 2` for a train, `quai B` otherwise; null when the real time doesn't say
String? platformLabel(LineSummary? line, String? platform) {
  final value = platform?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return line?.mode.isRail ?? false ? currentL10n.goPlatform(value) : currentL10n.goQuay(value);
}
