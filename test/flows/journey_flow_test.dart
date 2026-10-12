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

    await tapOn(tester, find.byType(JourneyCard));
    // The ride with its next departures from the boarding stop
    expect(find.text('Gare de Lyon'), findsWidgets);
    expect(backend.requestsTo('/api/v2/lines/C01371/rides'), isNotEmpty);

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
}
