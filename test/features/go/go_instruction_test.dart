import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/features/go/go_instruction.dart';
import 'package:website_app/features/go/go_guidance.dart';
import 'package:website_app/features/go/go_state.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/core/utils/geo.dart';
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

  group('walking view', () {
    final walkLine = tracker.steps[0].line;
    final walking = tracker.initial();

    test('the map follows the walk in progress, the way ahead up', () {
      final position = walkLine.pointAt(20);
      final follow = goFollow(state(walking).copyWith(position: position), 0);
      expect(follow, isNotNull);
      expect(follow!.position, position);
      // Along the path towards Châtelet
      final ahead = walkLine.pointAt(50);
      expect(follow.bearing, closeTo(tracker.steps[0].headingFrom(position, 20), 0.01));
      expect(follow.bearing, closeTo(bearingBetween(position, ahead), 1));
    });

    test('beside the path, it heads along it even when the progress lags', () {
      final step = tracker.steps[0];
      final onPath = walkLine.pointAt(60);
      // 15 m to the side, progress still at 0
      final beside = LatLng(onPath.latitude + 0.000135, onPath.longitude);
      final along = bearingBetween(walkLine.pointAt(60), walkLine.pointAt(90));
      final heading = step.headingFrom(beside, 0);
      expect((((heading - along) % 360) + 540) % 360 - 180, inInclusiveRange(-45, 45));
    });

    test('off the path, it heads back to it', () {
      final aside = LatLng(walkLine.pointAt(0).latitude + 0.002, walkLine.pointAt(0).longitude);
      // The path is south of the user: head south-ish
      final heading = tracker.steps[0].headingFrom(aside, 0);
      expect(heading, inInclusiveRange(90, 270));
    });

    test('not on board, not without a position, not when another step is shown', () {
      expect(goFollow(state(walking), 0), isNull);
      final waiting = tracker.jumpTo(walking, 1);
      expect(goFollow(state(waiting).copyWith(position: walkLine.pointAt(20)), 1), isNull);
      expect(goFollow(state(walking).copyWith(position: walkLine.pointAt(20)), 1), isNull);
    });
  });
}
