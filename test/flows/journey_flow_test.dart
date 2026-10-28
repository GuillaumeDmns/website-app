import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';
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
