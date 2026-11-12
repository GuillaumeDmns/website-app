import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/geo.dart';
import 'package:website_app/features/go/go_cards.dart';
import 'package:website_app/features/go/go_controller.dart';
import 'package:website_app/features/go/go_state.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  final start = DateTime.utc(2026, 11, 2, 8, 0);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));
  const vincennes = JourneyPoint(name: 'Cours de Vincennes', lat: 48.8475, lon: 2.4000);

  // Walk to Châtelet, metro 1 to Nation, walk on
  final metro = GoTracker(journey([
    walk(at(0), 240),
    transit(at(6), 480, via: [gareDeLyon]),
    walk(at(14), 180, from: point(nation), to: vincennes),
  ]));
  List<(GoCardKind, int)> kinds(List<GoCard> cards) => [for (final card in cards) (card.kind, card.step)];

  test('like Citymapper: a ride is its departures then the ride, a metro is got out of before walking on', () {
    expect(kinds(goCards(metro)), [
      (GoCardKind.walk, 0),
      (GoCardKind.departures, 1),
      (GoCardKind.ride, 1),
      (GoCardKind.exit, 2),
      (GoCardKind.walk, 2),
      (GoCardKind.arrival, 3),
    ]);
  });

  test('a transfer is walked in the departures card of the ride after it; a bus stop has no way out to find', () {
    final transfer = JourneySection(
      kind: SectionKind.transfer,
      departure: at(14),
      arrival: at(17),
      duration: 180,
      from: point(nation),
      to: point(nation),
    );
    final tracker = GoTracker(journey([
      walk(at(0), 240),
      transit(at(6), 480, via: [gareDeLyon]),
      transfer,
      transit(at(18), 300, line: bus38, from: nation, to: gareDeLyon),
      walk(at(23), 120, from: point(gareDeLyon), to: vincennes),
    ]));
    final cards = goCards(tracker);

    expect(kinds(cards), [
      (GoCardKind.walk, 0),
      (GoCardKind.departures, 1),
      (GoCardKind.ride, 1),
      (GoCardKind.departures, 3),
      (GoCardKind.ride, 3),
      (GoCardKind.walk, 4),
      (GoCardKind.arrival, 5),
    ]);
    expect(cards[3].transfer, 2);
    // Walking the transfer: the departures it leads to are what is going on
    expect(goCurrentCard(cards, const GoProgress(step: 2, phase: GoPhase.moving)), 3);
  });

  test('the card going on follows the progress: out of the station first, then the walk', () {
    final cards = goCards(metro);
    int current(GoProgress progress, {double? exitAlong}) => goCurrentCard(cards, progress, exitAlong: exitAlong);

    expect(current(const GoProgress(step: 0, phase: GoPhase.moving, along: 100)), 0);
    expect(current(const GoProgress(step: 1, phase: GoPhase.waiting)), 1);
    expect(current(const GoProgress(step: 1, phase: GoPhase.onBoard, stopIndex: 1)), 2);
    // Without the station's ways out, its first meters; with them, up to the best one
    expect(current(const GoProgress(step: 2, phase: GoPhase.moving, along: 30)), 3);
    expect(current(const GoProgress(step: 2, phase: GoPhase.moving, along: 80)), 4);
    expect(current(const GoProgress(step: 2, phase: GoPhase.moving, along: 80), exitAlong: 120), 3);
    expect(current(GoProgress(step: 3, phase: GoPhase.arrived, arrivedAt: at(17))), 5);
  });

  test("the best way out leaves the least to walk; the best way in is the first on the way", () {
    // A walk east from the station, 400 m
    final walk = MeasuredPolyline(const [LatLng(48.8484, 2.3959), LatLng(48.8484, 2.4013)]);
    const behind = StationEntrance(id: 'behind', code: '1', name: 'Behind', lat: 48.8484, lon: 2.3950);
    const onTheWay = StationEntrance(id: 'way', code: '2', name: 'On the way', lat: 48.8486, lon: 2.3968);
    const aside = StationEntrance(id: 'aside', code: '3', name: 'Aside', lat: 48.8496, lon: 2.3962);

    final exit = bestExit(walk, const [behind, aside, onTheWay])!;
    expect(exit.entrance.id, 'way');
    expect(exit.along, closeTo(66, 2));
    // Walking the other way, into the station at its end
    final reversed = MeasuredPolyline(walk.points.reversed.toList());
    expect(bestEntrance(reversed, const [behind, aside, onTheWay])!.entrance.id, 'way');
    expect(bestExit(walk, const []), isNull);
  });

  test("the way out and in Navitia's path takes wins over the best guess", () {
    // A walk east from the station, 400 m, Navitia's path leaving by the entrance behind it
    final walk = MeasuredPolyline(const [LatLng(48.8484, 2.3950), LatLng(48.8484, 2.4013)]);
    const behind = StationEntrance(id: 'behind', code: '1', name: 'Behind', lat: 48.8484, lon: 2.3950, wheelchairBoarding: 1);
    const onTheWay = StationEntrance(id: 'way', code: '2', name: 'On the way', lat: 48.8486, lon: 2.3968);
    // Navitia's access point: the same GTFS entrance, then another station's on the way
    const taken = StationEntrance(id: 'behind', name: 'Behind', lat: 48.8484, lon: 2.3950);
    const elsewhere = StationEntrance(id: 'elsewhere', name: 'Elsewhere', lat: 48.8484, lon: 2.4013);

    expect(bestExit(walk, const [behind, onTheWay])!.entrance.id, 'way');
    final exit = takenExit(walk, const [taken, elsewhere], const [behind, onTheWay])!;
    // The station's own entrance, with what its page says of it
    expect(exit.entrance, behind);
    expect(exit.along, closeTo(0, 1));

    // Walking the other way, into the station by the entrance Navitia's path ends at
    final reversed = MeasuredPolyline(walk.points.reversed.toList());
    expect(takenEntrance(reversed, const [elsewhere, taken], const [behind, onTheWay])!.entrance.id, 'behind');
    // Without an access of this station, the guess
    expect(takenExit(walk, const [elsewhere], const [behind, onTheWay]), isNull);
    expect(takenExit(walk, const [], const [behind, onTheWay]), isNull);
  });

  test('"Je suis ici" on a walk after a station: out of it already', () {
    final progress = metro.jumpTo(const GoProgress(step: 1, phase: GoPhase.onBoard), 2, along: 120);

    expect(progress.phase, GoPhase.moving);
    expect(progress.along, 120);
    // A ride starts at its stop whatever is said
    expect(metro.jumpTo(progress, 1, along: 120).along, 0);
  });

  test('getting-off alerts of a ride switched off are not felt; the others are', () {
    final state = GoState(
      tracker: metro,
      request: const JourneyRequest(),
      progress: const GoProgress(step: 1, phase: GoPhase.onBoard),
      startedAt: at(0),
      plannedArrival: at(17),
      alightAlertsOff: const {1},
    );
    const prepare = GoAlert(id: 'prepare-1', title: 'Préparez-vous');
    const alight = GoAlert(id: 'alight-1', title: 'Descendez', urgent: true);
    const platform = GoAlert(id: 'platform-1-B', title: 'Voie B');

    expect(goAlertFelt(state, prepare), isFalse);
    expect(goAlertFelt(state, alight), isFalse);
    expect(goAlertFelt(state, platform), isTrue);
    expect(goAlertFelt(state.copyWith(alightAlertsOff: const {}), alight), isTrue);
    expect(goAlertFelt(state.copyWith(alightAlertsOff: const {}, muted: true), alight), isFalse);
  });
}
