import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_instruction.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  final start = DateTime.utc(2026, 10, 10, 8, 0);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));

  // Walk to Châtelet, RER A at 8:06 to Gare de Lyon, then bus 38
  final plan = journey([
    walk(at(0), 240),
    transit(at(6), 300, line: rerA, to: gareDeLyon),
    transit(at(13), 300, line: bus38, from: gareDeLyon, to: chatelet),
  ]);
  final tracker = GoTracker(plan);

  GoState state(GoProgress progress, {String? platform, int vehicleStep = 1}) => GoState(
        tracker: tracker,
        request: const JourneyRequest(),
        progress: progress,
        startedAt: at(0),
        plannedArrival: plan.arrival,
        vehicle: departure(at(6)).copyWith(platform: platform),
        vehicleStep: vehicleStep,
      );

  test('the platform of the train waited for, or of the next ride', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);
    expect(goPlatformText(state(waiting, platform: '2')), 'voie 2');
    expect(goPlatformText(state(tracker.initial(), platform: '2')), 'RER A voie 2');
    // Not announced yet
    expect(goPlatformText(state(waiting)), isNull);
    // A bus has a "quai"
    final onBoard = tracker.jumpTo(tracker.initial(), 1).copyWith(phase: GoPhase.onBoard);
    expect(goPlatformText(state(onBoard, platform: 'B', vehicleStep: 2)), 'Bus 38 quai B');
  });

  test('the GO card says the platform while walking to the train', () {
    final instruction = goInstruction(state(tracker.initial(), platform: '2'), at(1));
    expect(instruction.detail, contains('voie 2'));
  });
}
