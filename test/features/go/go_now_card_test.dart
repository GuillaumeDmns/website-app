import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/theme.dart';
import 'package:website_app/features/go/go_state.dart';
import 'package:website_app/features/go/go_tracker.dart';
import 'package:website_app/features/go/widgets/go_now_card.dart';
import 'package:website_app/features/journey/journey_request.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  testWidgets("on board, the user is on the stops' rail where the clock puts them between the two stops, not halfway",
      (tester) async {
    final now = DateTime.now().toUtc();

    /// Where the user's dot is on the rail, as a share of the way from the stop left to the next one, the metro 1
    /// having left Châtelet [minutes] ago for Gare de Lyon (4 min) and Nation (4 min more), underground
    Future<double> shown(int minutes) async {
      final plan = journey([transit(now.subtract(Duration(minutes: minutes)), 480, via: [gareDeLyon])]);
      final state = GoState(
        tracker: GoTracker(plan),
        request: const JourneyRequest(),
        progress: const GoProgress(step: 0, phase: GoPhase.onBoard),
        startedAt: now,
        plannedArrival: plan.arrival,
      );
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('fr'),
          localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: GoNowCard(state: state)),
        ),
      ));
      // Its glide from where it was
      await tester.pump(const Duration(seconds: 1));
      final rail = find.descendant(of: find.byType(GoNowCard), matching: find.byType(Stack));
      // The user's dot is drawn last, over the stops'
      final me = tester.getCenter(find.descendant(of: rail, matching: find.byType(Positioned)).last).dx;
      final left = tester.getCenter(find.text('Châtelet')).dx;
      final next = tester.getCenter(find.text('Gare de Lyon')).dx;
      expect(find.text('Nation'), findsOneWidget);
      return (me - left) / (next - left);
    }

    expect(await shown(1), closeTo(0.25, 0.02));
    expect(await shown(3), closeTo(0.75, 0.02));
  });
}
