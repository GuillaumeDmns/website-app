import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/theme.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/core/utils/time_format.dart';
import 'package:website_app/core/widgets/departure_time.dart';
import 'package:website_app/features/journey/widgets/ride_departures.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));
  final now = DateTime.now().toUtc();
  DateTime inMinutes(int minutes) => now.add(Duration(minutes: minutes));

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('fr'),
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ));

  testWidgets('a bus listed twice at the same minute: one row raised, the other one can be chosen', (tester) async {
    // The 341 serves two stops of Charles de Gaulle - Étoile: the same bus arrives at each
    final first = ride(inMinutes(10), ride: const Duration(minutes: 6));
    final second = ride(inMinutes(10), ride: const Duration(minutes: 10));
    final later = ride(inMinutes(21));
    Ride? chosen;
    await pump(
      tester,
      RideDepartureList(rides: [first, second, later], now: now, selected: first, onSelect: (ride) => chosen = ride),
    );

    final raised = tester.widgetList<Material>(find.byType(Material)).where((material) {
      final shape = material.shape;
      return shape is RoundedRectangleBorder && shape.side.width == 1.5;
    });
    expect(raised, hasLength(1));

    // The other one, by its own arrival
    await tester.tap(find.text(formatClock(second.arrivalAt!)));
    expect(chosen, second);
  });

  testWidgets('late and early departures: the planned time struck through, the new one beside it, no sign to add up',
      (tester) async {
    final late = ride(inMinutes(13), aimed: inMinutes(10));
    final early = ride(inMinutes(30), aimed: inMinutes(32));
    await pump(tester, RideDepartureList(rides: [late, early], now: now, selected: late, onSelect: (_) {}));

    for (final (moved, planned, color) in [
      (late, inMinutes(10), AppColors.light.delayed),
      (early, inMinutes(32), AppTheme.lightTheme.colorScheme.secondary),
    ]) {
      expect(tester.widget<Text>(find.text(formatClock(planned))).style?.decoration, TextDecoration.lineThrough);
      expect(tester.widget<Text>(find.text(formatClock(moved.departure.time))).style?.color, color);
    }
    expect(find.textContaining('+'), findsNothing);
    expect(find.textContaining(RegExp(r'^-\d')), findsNothing);
  });

  for (final (phone, rideTime) in [(const Size(412, 900), true), (const Size(360, 800), false)]) {
    testWidgets('a long platform is cut, the times keep their size (${phone.width.round()} wide)', (tester) async {
      // A Transilien L replacement bus: its "platform" is the stop's name
      tester.view.physicalSize = phone * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final rides = [
        ride(inMinutes(13), aimed: inMinutes(9)).copyWith(
            departure: departure(inMinutes(13), aimed: inMinutes(9), platform: 'BECON LES BRUYERES')),
        ride(inMinutes(36), aimed: inMinutes(32)).copyWith(departure: departure(inMinutes(36), aimed: inMinutes(32), platform: '4')),
      ];
      // As in the journey detail, past the timeline on the left
      await pump(
        tester,
        Padding(
          padding: const EdgeInsets.only(left: 60, right: 12),
          child: RideDepartureList(rides: rides, now: now, selected: rides.first, compact: true, onSelect: (_) {}),
        ),
      );

      for (final ride in rides) {
        final clock = find.text(formatClock(ride.departure.time));
        // Drawn at its own size: not scaled down to make room
        expect(tester.getRect(clock).height, moreOrLessEquals(tester.getSize(clock).height));
      }
      final platform = tester.renderObject<RenderParagraph>(find.text(currentL10n.platform('BECON LES BRUYERES')));
      expect(platform.didExceedMaxLines, isTrue);
      expect(find.text(currentL10n.platform('4')), findsOneWidget);
      // A small phone leaves the ride time out first
      expect(find.text(currentL10n.minutesShort(8).replaceAll(' ', '\u00a0')), rideTime ? findsNWidgets(2) : findsNothing);
    });
  }

  group('compact, in the journey detail', () {
    testWidgets('each thing once: no destination every row has; each row its own ride time, missions differ', (tester) async {
      final rides = [for (final minutes in [10, 19]) ride(inMinutes(minutes)), ride(inMinutes(30), ride: const Duration(minutes: 5))];
      await pump(tester, RideDepartureList(rides: rides, now: now, selected: rides.first, compact: true, onSelect: (_) {}));

      // The times at both stops, the ride time, the time left: the direction is said above the list
      expect(find.text(formatClock(rides.first.departure.time)), findsOneWidget);
      expect(find.text(formatClock(rides.first.arrivalAt!)), findsOneWidget);
      expect(find.text('Nation'), findsNothing);
      expect(find.text(currentL10n.minutesShort(8).replaceAll(' ', '\u00a0')), findsNWidgets(2));
      expect(find.text(currentL10n.minutesShort(5).replaceAll(' ', '\u00a0')), findsOneWidget);
      expect(find.byType(DepartureTime), findsNWidgets(3));
    });

    testWidgets('destinations that differ are told, with their mission', (tester) async {
      final rides = [
        ride(inMinutes(10)).copyWith(departure: departure(inMinutes(10), mission: 'PAPE')),
        ride(inMinutes(19)).copyWith(destination: 'Boissy-Saint-Léger'),
      ];
      await pump(tester, RideDepartureList(rides: rides, now: now, selected: rides.first, compact: true, onSelect: (_) {}));

      expect(find.text('Nation'), findsOneWidget);
      expect(find.text('PAPE'), findsOneWidget);
      expect(find.text('Boissy-Saint-Léger'), findsOneWidget);
    });

    testWidgets("hours ahead, the row's clock time is not said again as the time left", (tester) async {
      final rides = [for (final minutes in [364, 373]) ride(inMinutes(minutes))];
      await pump(tester, RideDepartureList(rides: rides, now: now, selected: rides.first, compact: true, onSelect: (_) {}));

      expect(find.text(formatClock(rides.first.departure.time)), findsOneWidget);
      expect(find.byType(DepartureTime), findsNothing);

      // Elsewhere (GO, at the stop), the full rows
      await pump(tester, RideDepartureList(rides: rides, now: now, selected: rides.first, onSelect: (_) {}));
      expect(find.byType(DepartureTime), findsNWidgets(2));
      expect(find.text('Nation'), findsNWidgets(2));
    });
  });
}
