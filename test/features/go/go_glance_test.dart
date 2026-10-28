import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/features/go/go_glance.dart';
import 'package:website_app/features/go/go_live.dart';
import 'package:website_app/features/go/go_state.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  final start = DateTime.utc(2026, 10, 10, 8, 0);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));

  // Walk to Châtelet, RER A at 8:06 to Gare de Lyon (boarding at the front), then bus 38
  final plan = journey([
    walk(at(0), 240),
    transit(at(6), 300, line: rerA, to: gareDeLyon, via: [nation]).copyWith(boardingPositions: ['front']),
    transit(at(13), 300, line: bus38, from: gareDeLyon, to: chatelet),
  ]);
  final tracker = GoTracker(plan);

  GoState state(GoProgress progress, {String? platform}) => GoState(
        tracker: tracker,
        request: const JourneyRequest(),
        progress: progress,
        startedAt: at(0),
        plannedArrival: plan.arrival,
        vehicle: departure(at(6)).copyWith(platform: platform),
        vehicleStep: 1,
      );

  test('walking: where to, the minutes left, the next ride after it', () {
    // 100 m left
    final walking = tracker.initial().copyWith(along: tracker.steps[0].line.length - 100);
    final glance = goGlance(state(walking), at(0));
    expect(glance.kicker, currentL10n.goKickerOnFoot);
    expect(glance.heroUnit, currentL10n.minutesUnit);
    expect(int.parse(glance.hero!), greaterThan(0));
    expect(glance.place, contains('RER A'));
    expect(glance.line, isNull);
    // 6 min to walk 100 m: all well
    expect(glance.tone, GoTone.ok);
  });

  test('walking too slowly to the train: needs attention', () {
    expect(goGlance(state(tracker.initial()), at(5)).tone, GoTone.warn);
  });

  test('waiting: the line, the minutes to the departure, the platform and where to board', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);
    final glance = goGlance(state(waiting, platform: '2'), at(2));
    expect(glance.line, rerA);
    expect(glance.action, currentL10n.goTake('RER A'));
    expect(glance.hero, '4');
    expect(glance.heroUnit, currentL10n.minutesUnit);
    expect(glance.kicker, 'Châtelet · Voie 2');
    expect(glance.place, contains(currentL10n.goBoard(currentL10n.boardFront)));
    expect(glance.tone, GoTone.ok);
    // Leaving now: act
    final now = goGlance(state(waiting), at(6));
    expect(now.hero, currentL10n.now);
    expect(now.heroUnit, isNull);
    expect(now.tone, GoTone.urgent);
  });

  test('on board: the stops left, then get off at the next one in red', () {
    final onBoard = tracker.jumpTo(tracker.initial(), 1).copyWith(phase: GoPhase.onBoard);
    final glance = goGlance(state(onBoard), at(7));
    expect(glance.action, currentL10n.goGetOffAtStop('Gare de Lyon'));
    expect(glance.hero, '2');
    expect(glance.heroUnit, currentL10n.goStopsUnit(2));
    expect(glance.place, startsWith(currentL10n.goNextStopShort('Nation')));
    expect(glance.tone, GoTone.ok);

    // The last stretch counts the minutes, red once the stop is close
    final last = goGlance(state(onBoard.copyWith(stopIndex: 1)), at(7));
    expect(last.action, currentL10n.goGetOffNext);
    expect((last.hero, last.heroUnit), ('4', currentL10n.minutesUnit));
    expect(last.tone, GoTone.ok);
    final close = goGlance(state(onBoard.copyWith(stopIndex: 1)), at(9));
    expect((close.hero, close.heroUnit), ('2', currentL10n.minutesUnit));
    expect(close.tone, GoTone.urgent);
    expect(goGlance(state(onBoard.copyWith(stopIndex: 1)), at(11)).hero, currentL10n.now);
  });

  test('a missed vehicle needs attention', () {
    final missed = tracker.jumpTo(tracker.initial(), 1).copyWith(issue: () => GoIssue.missed);
    expect(goGlance(state(missed), at(8)).tone, GoTone.warn);
  });

  test('the notification says the same moment as the banner', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);
    final glance = goGlance(state(waiting, platform: '2'), at(2));
    final update = goLiveUpdate(state(waiting, platform: '2'), at(2));
    expect(update.title, glance.action);
    expect(update.chip, glance.heroText);
    expect(update.status, glance.place);
  });

  test('walking too slowly: hurry is the instruction, with how far and the train', () {
    final glance = goGlance(state(tracker.initial()), at(4));
    expect(glance.action, anyOf(currentL10n.goMarginHurry, currentL10n.goMarginLate));
    expect(glance.icon, Icons.directions_run);
    expect(glance.heroUnit, anyOf('m', 'km'));
    expect(glance.place, startsWith('RER A'));
    expect(glance.tone, GoTone.warn);
  });

  test('off the way: said first, with the recalculation coming', () {
    final off = tracker.initial().copyWith(issue: () => GoIssue.offRoute);
    final glance = goGlance(state(off).copyWith(recalculateAt: () => at(1).add(const Duration(seconds: 8))), at(1));
    expect(glance.action, currentL10n.goOffRoute);
    expect(glance.place, currentL10n.goRecalculateIn(8));
    expect(glance.tone, GoTone.warn);
  });

  test('a missed train replaced by the next one: said, with how much later', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1);
    final glance = goGlance(
        state(waiting).copyWith(retained: () => (step: 1, later: const Duration(minutes: 8), cancelled: false)), at(2));
    expect(glance.action, currentL10n.goMissedShort('RER A'));
    expect(glance.hero, '+8');
    expect(glance.place, currentL10n.goRetained);
    expect(glance.tone, GoTone.warn);
  });

  test('a platform change: the new platform is the instruction, the old one recalled', () {
    final waiting = tracker.jumpTo(tracker.initial(), 1).copyWith(fired: {'platform-1-3'});
    final glance = goGlance(state(waiting, platform: '5'), at(2));
    expect(glance.kicker, currentL10n.goPlatformChangedKicker);
    expect(glance.action, currentL10n.goGoToPlatform('voie 5'));
    expect(glance.place, contains(currentL10n.goPlatformInsteadOf('voie 5', 'voie 3')));
    // Announced once, without a change: the usual moment
    final announced = tracker.jumpTo(tracker.initial(), 1).copyWith(fired: {'platform-1-5'});
    expect(goGlance(state(announced, platform: '5'), at(2)).action, currentL10n.goTake('RER A'));
  });
}
