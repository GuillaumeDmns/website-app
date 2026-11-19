import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/theme.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/time_format.dart';
import 'package:website_app/features/home/nearby_departures.dart';
import 'package:website_app/features/journey/journey_labels.dart';
import 'package:website_app/features/journey/widgets/journey_card.dart';
import 'package:website_app/features/journey/widgets/ride_alerts.dart';
import 'package:website_app/features/journey/widgets/ride_departures.dart';
import 'package:website_app/features/stops/widgets/stop_departures_card.dart';
import 'package:website_app/features/traffic/traffic_screen.dart';
import 'package:website_app/l10n/l10n.dart';

import '../support/fake_backend.dart';
import '../support/samples.dart';
import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// Journeys: from a stop's "go there" to the detail, and the guest limit
void main() {
  testWidgets('plans a journey to a stop and opens an option', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend);

    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));

    final request = backend.requestsTo('/api/v2/journeys').single;
    expect(request.queryParameters['from'], '48.8584,2.347');
    expect(request.queryParameters['to'], 'IDFM:70001');
    expect(find.byType(JourneyCard), findsNWidgets(2));
    // Each option in two lines: when to leave and the arrival, not the times twice nor its first ride's departures
    // (the detail's), which the results no longer ask
    expect(find.textContaining(RegExp(r'·.arrivée.\d\d:\d\d$'), findRichText: true), findsNWidgets(2));
    expect(find.textContaining(' → '), findsNothing);
    expect(backend.requestsTo('/api/v2/lines/C01371/rides'), isEmpty);
    // No category titles: what the planner says of an option is on its card
    expect(find.descendant(of: find.byType(JourneyCard).first, matching: find.text(currentL10n.journeyBest)), findsOneWidget);
    expect(find.text(currentL10n.journeyRapid), findsNothing);

    await tapOn(tester, find.byType(JourneyCard));
    // The ride with its next departures from the boarding stop, in a list: the next one, should it be missed, is
    // the row under the one taken, nothing says it again
    expect(find.text('Gare de Lyon'), findsWidgets);
    expect(backend.requestsTo('/api/v2/lines/C01371/rides'), isNotEmpty);
    expect(find.byType(RideDepartureList), findsWidgets);
    expect(find.textContaining(currentL10n.goIfMissed('', 0).split(':').first), findsNothing);
    // The essentials once, in the header: the arrival, when to leave
    expect(find.textContaining(RegExp(r'· arrivée \d\d:\d\d$'), findRichText: true), findsWidgets);
    // GO at hand at the bottom
    expect(find.widgetWithText(FilledButton, currentL10n.go), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('the results tell the options apart on their cards, a disrupted line in clear', (tester) async {
    final backend = standardBackend();
    backend.on('GET', '/api/v2/journeys', (_) {
      final start = DateTime.now().toUtc().add(const Duration(minutes: 2));
      DateTime at(int minutes) => start.add(Duration(minutes: minutes));
      return FakeResponse(JourneyPlan(journeys: [
        // The metro (interrupted in the standard traffic) then the RER; the RER alone, slower
        journey([transit(start, 300, to: gareDeLyon), wait(at(5), 120), transit(at(7), 360, line: rerA, from: gareDeLyon)])
            .copyWith(type: 'best', tags: ['walking', 'ecologic', 'asap'], fare: 250),
        journey([walk(start, 300), transit(at(5), 1200, line: rerA)]).copyWith(type: 'comfort', tags: ['walking', 'ecologic', 'less_transfers'], fare: 250),
        journey([walk(start, 300), transit(at(9), 1200, line: rerA)]).copyWith(type: 'rapid', tags: ['walking', 'ecologic'], fare: 250),
      ]).toJson());
    });
    await pumpApp(tester, backend);
    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));

    final cards = find.byType(JourneyCard);
    // What the planner says of each option (its tags), on its card; nothing for the one it says nothing of
    expect(find.descendant(of: cards.at(0), matching: find.text(currentL10n.journeyAsap)), findsOneWidget);
    expect(find.descendant(of: cards.at(1), matching: find.text(currentL10n.journeyComfort)), findsOneWidget);
    for (final label in [currentL10n.journeyRapid, currentL10n.journeyBest, currentL10n.journeyAsap, currentL10n.journeyComfort]) {
      expect(find.descendant(of: cards.at(2), matching: find.text(label)), findsNothing);
    }
    // A third line only where something goes wrong, said in words
    expect(find.descendant(of: cards.at(0), matching: find.text('1 : trafic interrompu')), findsOneWidget);
    expect(find.descendant(of: cards.at(1), matching: find.textContaining('trafic')), findsNothing);
    // The same fare on every card is not worth a place
    expect(find.textContaining('2,50'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('the detail says each thing once: the wait with the transfer, the stops without their town', (tester) async {
    final backend = standardBackend();
    backend.on('GET', '/api/v2/journeys', (_) {
      final start = DateTime.now().toUtc().add(const Duration(minutes: 2));
      DateTime at(int minutes) => start.add(Duration(minutes: minutes));
      const from = JourneyPoint(name: '3 Avenue Léon de Bertalot (Courbevoie)', lat: 48.86, lon: 2.34);
      final lyon = gareDeLyon.copyWith(name: 'Gare de Lyon (Paris)');
      return FakeResponse(JourneyPlan(journeys: [
        journey([
          walk(start, 300, from: from),
          transit(at(5), 300, to: lyon),
          JourneySection(kind: SectionKind.transfer, departure: at(10), arrival: at(14), duration: 240, length: 279),
          wait(at(14), 180),
          transit(at(17), 360, line: rerA, from: lyon),
        ]).copyWith(transfers: 1, fare: 250),
      ]).toJson());
    });
    // The metro a minute after the walk, 8 min long; then 4 min on foot and the RER 6 min later
    DateTime inMinutes(int minutes) => DateTime.now().toUtc().add(Duration(minutes: minutes));
    backend.on('GET', '/api/v2/lines/*/rides', (_) => FakeResponse([for (final minutes in [8, 26]) ride(inMinutes(minutes)).toJson()]));
    await pumpApp(tester, backend);
    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));
    await tapOn(tester, find.byType(JourneyCard));

    // The header: the duration and the arrival, when to leave, the transfers and the fare
    expect(find.textContaining(RegExp(r'·.1.corresp\..·.2,50'), findRichText: true), findsOneWidget);
    // An address with its town beside it, a stop by its name alone
    expect(find.textContaining('3 Avenue Léon de Bertalot Courbevoie', findRichText: true), findsOneWidget);
    expect(find.text(currentL10n.getOffAt('Gare de Lyon')), findsOneWidget);
    expect(find.textContaining('(Paris)'), findsNothing);
    // On foot, then the transfer and its wait on one line: no row of its own for the wait
    expect(find.textContaining(RegExp(r'^5.min à pied · 360 m')), findsOneWidget);
    expect(find.textContaining(RegExp(r"^Correspondance · 4.min à pied, 6.min.d'attente$")), findsOneWidget);
    expect(find.textContaining('Attendre'), findsNothing);
    // The departures stay a list, one under the other
    expect(find.byType(RideDepartureList), findsWidgets);

    await closeApp(tester);
  });

  testWidgets('large text (×1.8): the home page, the results and the detail hold', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final backend = standardBackend();
    backend.on('GET', '/api/v2/journeys', (_) {
      final start = DateTime.now().toUtc().add(const Duration(minutes: 2));
      DateTime at(int minutes) => start.add(Duration(minutes: minutes));
      return FakeResponse(JourneyPlan(journeys: [
        journey([
          walk(start, 300),
          transit(at(5), 300, to: gareDeLyon),
          JourneySection(kind: SectionKind.transfer, departure: at(10), arrival: at(14), duration: 240, length: 279),
          wait(at(14), 180),
          transit(at(17), 360, line: rerA, from: gareDeLyon),
        ]).copyWith(transfers: 1, fare: 250),
        journey([walk(start, 300), transit(at(5), 1800, line: bus38)]).copyWith(fare: 205),
      ]).toJson());
    });
    await pumpApp(tester, backend);

    // The traffic on its line, then the departures around and their kinds
    expect(find.byType(TrafficSummaryCard), findsOneWidget);
    await scrollTo(tester, find.byType(StopDeparturesCard));
    expect(find.byType(NearbyFilterChips), findsOneWidget);

    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));
    // Tags, fares that differ, a disrupted line
    expect(find.byType(JourneyCard), findsNWidgets(2));
    await tapOn(tester, find.byType(JourneyCard));
    expect(find.byType(RideDepartureList), findsWidgets);
    await tester.drag(find.byType(ListView).first, const Offset(0, -800));
    await settle(tester);

    await closeApp(tester);
  });

  testWidgets('like Citymapper, the options fill the screen and a tap opens one', (tester) async {
    await pumpApp(tester, standardBackend());
    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));
    double sheetTop() => tester
        .getTopLeft(find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Material)).first)
        .dy;
    expect(sheetTop(), closeTo(915 * (1 - 0.85), 2));

    // The second option, at once: its detail, the map showing it
    await tapOn(tester, find.byType(JourneyCard).at(1));
    expect(find.byType(JourneyCard), findsNothing);
    expect(find.widgetWithText(FilledButton, currentL10n.go), findsOneWidget);
    expect(sheetTop(), closeTo(915 * 0.5, 2));

    await closeApp(tester);
  });

  testWidgets('a ride of the detail shows its stops between in the timeline, not on the map', (tester) async {
    final backend = standardBackend();
    backend.on('GET', '/api/v2/journeys', (_) {
      final start = DateTime.now().toUtc().add(const Duration(minutes: 2));
      return FakeResponse(JourneyPlan(journeys: [
        journey([walk(start, 300), transit(start.add(const Duration(minutes: 5)), 480, via: [gareDeLyon])]),
      ]).toJson());
    });
    await pumpApp(tester, backend);
    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));
    await tapOn(tester, find.byType(JourneyCard));

    // Folded: only the count
    expect(find.text('Gare de Lyon'), findsNothing);
    await tapOn(tester, find.textContaining(currentL10n.stopsCount(1)));
    // One under the other with its time, like the rest of the timeline; nothing written on the map
    expect(find.text('Gare de Lyon'), findsOneWidget);
    expect(find.textContaining('Gare de Lyon ·'), findsNothing);

    await tapOn(tester, find.textContaining(currentL10n.stopsCount(1)));
    expect(find.text('Gare de Lyon'), findsNothing);

    await closeApp(tester);
  });

  testWidgets("a ride's alerts behind one small icon of its line's row, read in a sheet; no real-time, boarding nor platform tag",
      (tester) async {
    final backend = standardBackend();
    DateTime inMinutes(int minutes) => DateTime.now().toUtc().add(Duration(minutes: minutes));
    backend.on('GET', '/api/v2/journeys', (_) => FakeResponse(JourneyPlan(journeys: [
          journey([
            walk(inMinutes(2), 300),
            transit(inMinutes(7), 480, to: gareDeLyon).copyWith(boardingPositions: ['front'], realtime: true),
          ]),
        ]).toJson()));
    backend.on('GET', '/api/v2/lines/*/rides', (_) => FakeResponse([
          for (final minutes in [7, 12, 17])
            ride(inMinutes(minutes)).copyWith(departure: departure(inMinutes(minutes)).copyWith(platform: '2')).toJson(),
        ]));
    await pumpApp(tester, backend);
    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));
    await tapOn(tester, find.byType(JourneyCard));

    // The real time is in the departures (their minutes in green), where to board is GO's, the platform the departures
    // list's
    expect(find.text(currentL10n.realtime), findsNothing);
    expect(find.text(boardingLabel(['front'])), findsNothing);
    expect(find.text(platformLabel(metro1, '2')!), findsNothing);
    expect(find.text(currentL10n.platform('2')), findsWidgets);
    // The line interrupted and Châtelet's elevator, written in clear under the line's row, in red: not a lone icon
    final alerts = find.byType(RideAlertsLine);
    expect(find.descendant(of: alerts, matching: find.text('${metroStopped.title!} · ${currentL10n.brokenElevators(1)}')), findsOneWidget);
    expect(find.descendant(of: alerts, matching: find.byIcon(Icons.block)), findsOneWidget);

    // A tap: their messages at once, the elevators under their stop
    await tapOn(tester, alerts);
    expect(find.text(currentL10n.rideAlerts), findsOneWidget);
    expect(find.text(metroStopped.title!), findsOneWidget);
    expect(find.text(metroStopped.message!), findsOneWidget);
    expect(find.text(currentL10n.atStop('Châtelet')), findsOneWidget);
    expect(find.text(currentL10n.brokenElevators(1)), findsOneWidget);
    expect(find.textContaining(elevatorOutage.title!), findsOneWidget);
    expect(find.text(elevatorOutage.message!), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets("the timeline strikes a ride's planned time through only when its clock prints another minute", (tester) async {
    final backend = standardBackend();
    final soon = DateTime.now().toUtc().add(const Duration(minutes: 10));
    final minute = DateTime.utc(soon.year, soon.month, soon.day, soon.hour, soon.minute);
    // The metro 40 s late, still in its minute; the RER 20 s late, across the minute
    final metro = minute.add(const Duration(seconds: 40));
    final rer = minute.add(const Duration(minutes: 12, seconds: 10));
    final rerPlanned = rer.subtract(const Duration(seconds: 20));
    backend.on('GET', '/api/v2/journeys', (_) => FakeResponse(JourneyPlan(journeys: [
          journey([
            walk(minute.subtract(const Duration(minutes: 5)), 300),
            transit(metro, 480, to: gareDeLyon).copyWith(realtime: true, delay: 40),
            transit(rer, 600, line: rerA, from: gareDeLyon, to: nation).copyWith(realtime: true, delay: 20),
          ]),
        ]).toJson()));
    // No departures to retime the rides with: the timeline shows the journey's own real time
    backend.on('GET', '/api/v2/lines/*/rides', (_) => FakeResponse([]));
    await pumpApp(tester, backend);
    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));
    await tapOn(tester, find.byType(JourneyCard));

    bool struck(DateTime time) =>
        tester.widgetList<Text>(find.text(formatClock(time))).any((text) => text.style?.decoration == TextDecoration.lineThrough);
    // The metro at its minute alone, not "21:11" struck through before "21:11"
    expect(find.text(formatClock(metro)), findsWidgets);
    expect(struck(metro), isFalse);
    // The RER: the planned minute struck through under the new one, in the delay's color
    expect(struck(rerPlanned), isTrue);
    expect(tester.widgetList<Text>(find.text(formatClock(rer))).any((text) => text.style?.color == AppColors.light.delayed), isTrue);

    await closeApp(tester);
  });

  testWidgets('the modes, Vélib and leaving later in one tap', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend);
    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));

    List<String>? modes() => (backend.requestsTo('/api/v2/journeys').last.queryParameters['modes'] as String?)?.split(',');
    FilterChip chip(TransportMode mode) => tester.widget(find.widgetWithText(FilterChip, mode.label));
    // "Éviter": a tap on a mode leaves it out, whatever the others
    expect(find.text(currentL10n.avoidModes), findsOneWidget);
    await tapOn(tester, find.widgetWithText(FilterChip, TransportMode.bus.label));
    expect(modes(), unorderedEquals(['METRO', 'RER', 'TRANSILIEN', 'TER', 'TRAM']));
    expect(chip(TransportMode.bus).selected, isTrue);
    await tapOn(tester, find.widgetWithText(FilterChip, TransportMode.tram.label));
    expect(modes(), unorderedEquals(['METRO', 'RER', 'TRANSILIEN', 'TER']));
    // Another tap brings it back, down to no choice at all
    await tapOn(tester, find.widgetWithText(FilterChip, TransportMode.bus.label));
    expect(modes(), unorderedEquals(['METRO', 'RER', 'TRANSILIEN', 'TER', 'BUS', 'NOCTILIEN']));
    await tapOn(tester, find.widgetWithText(FilterChip, TransportMode.tram.label));
    expect(modes(), isNull);
    expect(chip(TransportMode.tram).selected, isFalse);
    // Everything can't be avoided: the last mode left has no tap
    for (final mode in [TransportMode.rer, TransportMode.transilien, TransportMode.tram, TransportMode.bus]) {
      await tapOn(tester, find.widgetWithText(FilterChip, mode.label));
    }
    expect(modes(), ['METRO']);
    expect(chip(TransportMode.metro).onSelected, isNull);
    await tapOn(tester, find.widgetWithText(FilterChip, TransportMode.bus.label));

    await tapOn(tester, find.widgetWithText(FilterChip, currentL10n.journeyBikeShare));
    expect(backend.requestsTo('/api/v2/journeys').last.queryParameters['bikeShare'], isTrue);

    await tapOn(tester, find.text(currentL10n.leaveInMinutes(15)));
    final at = DateTime.parse(backend.requestsTo('/api/v2/journeys').last.queryParameters['datetime']!);
    expect(at.difference(DateTime.now()).inMinutes, inInclusiveRange(13, 15));
    // And back to now, with the other times after the options
    expect(find.text(currentL10n.leaveLater), findsOneWidget);
    expect(find.widgetWithText(ActionChip, currentL10n.nowShort), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a guest past the journey limit is offered to sign in', (tester) async {
    final backend = standardBackend();
    backend.on('GET', '/api/v2/journeys', (_) => FakeResponse.problem(429, detail: 'used up', code: 'guest_journey_limit'));
    await pumpApp(tester, backend);

    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));
    expect(find.text(currentL10n.errorGuestJourneyLimit), findsOneWidget);

    await tapOn(tester, find.text(currentL10n.signInAction));
    expect(find.text(currentL10n.continueWithGoogle), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('when to leave: to the minute, not by steps of five', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend);
    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));

    final opened = DateTime.now();
    await tapOn(tester, find.text(currentL10n.nowShort));
    await tapOn(tester, find.text(currentL10n.timeLeaveAt));
    // The wheel starts on this minute; one row down is the next minute
    await tester.drag(find.bySemanticsLabel(currentL10n.timeMinutes), const Offset(0, -40));
    await settle(tester);
    await tapOn(tester, find.text(currentL10n.apply));

    final datetime = DateTime.parse(backend.requestsTo('/api/v2/journeys').last.queryParameters['datetime'] as String).toLocal();
    // The test may run across a minute
    expect(datetime.minute, anyOf((opened.minute + 1) % 60, (opened.minute + 2) % 60));

    await closeApp(tester);
  });

  testWidgets('when to leave: the wheels turn with a mouse too (desktop, web): drag, wheel, click', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend);
    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));

    await tapOn(tester, find.text(currentL10n.nowShort));
    await tapOn(tester, find.text(currentL10n.timeLeaveAt));
    final minutes = find.bySemanticsLabel(currentL10n.timeMinutes);
    // The minute the sheet says, "Partir à 08:07 aujourd'hui"
    int shown() {
      final summary = find.textContaining(RegExp('^${currentL10n.timeLeaveAt} \\d\\d:\\d\\d')).evaluate().map((e) => (e.widget as Text).data!).single;
      return int.parse(RegExp(r'\d\d:(\d\d)').firstMatch(summary)!.group(1)!);
    }
    final start = shown();

    // Dragged with the mouse: one row up is the next minute
    await tester.drag(minutes, const Offset(0, -40), kind: PointerDeviceKind.mouse);
    await settle(tester);
    expect(shown(), (start + 1) % 60);
    // One notch of the wheel down: one minute more, whatever the notch's size (100 px in Chrome)
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(minutes)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    await settle(tester);
    expect(shown(), (start + 2) % 60);
    // And back up
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await settle(tester);
    expect(shown(), (start + 1) % 60);
    // A click on a row: that one, here the one under the band
    await tester.tapAt(tester.getCenter(minutes) + const Offset(0, 40), kind: PointerDeviceKind.mouse);
    await settle(tester);
    expect(shown(), (start + 2) % 60);
    await tapOn(tester, find.text(currentL10n.apply));

    final datetime = DateTime.parse(backend.requestsTo('/api/v2/journeys').last.queryParameters['datetime'] as String).toLocal();
    expect(datetime.minute, (start + 2) % 60);

    await closeApp(tester);
  });

  testWidgets('when to leave: arrive by tomorrow at a time, in one sheet and one button', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend);
    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));

    await tapOn(tester, find.text(currentL10n.nowShort));
    expect(find.text(currentL10n.timeSheetTitle), findsOneWidget);
    await tapOn(tester, find.text(currentL10n.timeArriveBy));
    await tapOn(tester, find.text(currentL10n.timeTomorrowCapital));
    expect(find.textContaining(' ${currentL10n.tomorrow}'), findsOneWidget);
    await tapOn(tester, find.text(currentL10n.apply));

    final request = backend.requestsTo('/api/v2/journeys').last.queryParameters;
    expect(request['arriveBy'], isTrue);
    final datetime = DateTime.parse(request['datetime'] as String).toLocal();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect((datetime.year, datetime.month, datetime.day), (tomorrow.year, tomorrow.month, tomorrow.day));

    await closeApp(tester);
  });

  testWidgets('no journey at this time: an hour later in one tap', (tester) async {
    final backend = standardBackend();
    backend.on('GET', '/api/v2/journeys', (_) => FakeResponse(const JourneyPlan(journeys: []).toJson()));
    await pumpApp(tester, backend);
    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));

    expect(find.text(currentL10n.noJourneyFound), findsOneWidget);
    await tapOn(tester, find.text(currentL10n.journeyLater));
    final datetime = DateTime.parse(backend.requestsTo('/api/v2/journeys').last.queryParameters['datetime'] as String);
    expect(datetime.difference(DateTime.now()).inMinutes, inInclusiveRange(55, 61));

    await closeApp(tester);
  });
}
