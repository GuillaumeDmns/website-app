import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/theme.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/time_format.dart';
import 'package:website_app/features/journey/journey_labels.dart';
import 'package:website_app/features/journey/widgets/journey_card.dart';
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
    // Each option with its first ride's departure and the next ones, on one line
    expect(find.textContaining(RegExp(r'à \d\d:\d\d · \d\d:\d\d')), findsWidgets);

    await tapOn(tester, find.byType(JourneyCard));
    // The ride with its next departures from the boarding stop, and the next one in case it is missed
    expect(find.text('Gare de Lyon'), findsWidgets);
    expect(backend.requestsTo('/api/v2/lines/C01371/rides'), isNotEmpty);
    expect(find.textContaining(currentL10n.goIfMissed('', 0).split(':').first), findsWidgets);
    // GO at hand at the bottom
    expect(find.widgetWithText(FilledButton, currentL10n.go), findsOneWidget);

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

  testWidgets("a ride's alerts behind one small icon of its line's row, read in a sheet; no boarding nor platform tag", (tester) async {
    final backend = standardBackend();
    DateTime inMinutes(int minutes) => DateTime.now().toUtc().add(Duration(minutes: minutes));
    backend.on('GET', '/api/v2/journeys', (_) => FakeResponse(JourneyPlan(journeys: [
          journey([
            walk(inMinutes(2), 300),
            transit(inMinutes(7), 480, to: gareDeLyon).copyWith(boardingPositions: ['front']),
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

    // Where to board is GO's, the platform the departures list's
    expect(find.text(boardingLabel(['front'])), findsNothing);
    expect(find.text(platformLabel(metro1, '2')!), findsNothing);
    expect(find.text(currentL10n.platform('2')), findsWidgets);
    // The line interrupted and Châtelet's elevator: one red icon, not their texts
    expect(find.text(metroStopped.title!), findsNothing);
    expect(find.text(currentL10n.brokenElevators(1)), findsNothing);
    final alerts = find.byTooltip(currentL10n.rideAlertsOf('${currentL10n.severityBlocking} · ${currentL10n.brokenElevators(1)}'));
    expect(alerts, findsOneWidget);
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

    // Without a choice, a mode chip keeps that mode only
    await tapOn(tester, find.widgetWithText(FilterChip, TransportMode.metro.label));
    expect(backend.requestsTo('/api/v2/journeys').last.queryParameters['modes'], 'METRO');
    // Then each one adds or removes its mode
    await tapOn(tester, find.widgetWithText(FilterChip, TransportMode.bus.label));
    expect(backend.requestsTo('/api/v2/journeys').last.queryParameters['modes']?.split(','), containsAll(['METRO', 'BUS', 'NOCTILIEN']));

    await tapOn(tester, find.widgetWithText(FilterChip, currentL10n.journeyBikeShare));
    expect(backend.requestsTo('/api/v2/journeys').last.queryParameters['bikeShare'], isTrue);

    await tapOn(tester, find.text(currentL10n.leaveInMinutes(15)));
    final at = DateTime.parse(backend.requestsTo('/api/v2/journeys').last.queryParameters['datetime']!);
    expect(at.difference(DateTime.now()).inMinutes, inInclusiveRange(13, 15));
    // And back to now
    expect(find.widgetWithText(ActionChip, currentL10n.leaveNow), findsOneWidget);

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

  testWidgets('when to leave: arrive by tomorrow at a time, in one sheet and one button', (tester) async {
    final backend = standardBackend();
    await pumpApp(tester, backend);
    await tapOn(tester, find.text('Châtelet'));
    await tapOn(tester, find.text(currentL10n.goThere));

    await tapOn(tester, find.text(currentL10n.leaveNow));
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
