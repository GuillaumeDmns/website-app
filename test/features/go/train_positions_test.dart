import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/theme.dart';
import 'package:website_app/features/go/widgets/go_departures_card.dart';
import 'package:website_app/features/journey/journey_labels.dart';
import 'package:website_app/l10n/l10n.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  test('the cars to board, from the front: two for each third of the train', () {
    expect(TrainPositions.boardedCars(['front']), [true, true, false, false, false, false]);
    expect(TrainPositions.boardedCars(['middle', 'back']), [false, false, true, true, true, true]);
  });

  testWidgets('"Où monter ?" answered over a small train drawn from its front, the way it goes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      locale: const Locale('fr'),
      localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: TrainPositions(positions: ['front'], color: Color(0xFFFFCD00))),
    ));

    expect(find.text(currentL10n.goWhereToBoard), findsOneWidget);
    expect(find.text("À l'avant"), findsOneWidget);
    expect(find.text(currentL10n.goDirectionOfTravel), findsOneWidget);
    // Read out as one sentence
    expect(find.bySemanticsLabel(boardingLabel(['front'])), findsOneWidget);
  });
}
