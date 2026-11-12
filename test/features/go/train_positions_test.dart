import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/theme.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/go/widgets/go_departures_card.dart';
import 'package:website_app/features/journey/journey_labels.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));

  test('the cars to board, from the front: two for each third of the train', () {
    expect(TrainPositions.boardedCars(['front']), [true, true, false, false, false, false]);
    expect(TrainPositions.boardedCars(['middle', 'back']), [false, false, true, true, true, true]);
  });

  test('the front stops on the right of a metro or tram platform, on the left of a train\'s', () {
    // Running on the right, the platform on their right
    expect(TrainPositions.headRightFor(metro1), isTrue);
    expect(TrainPositions.headRightFor(const LineSummary(id: 'C01390', name: 'T2', mode: TransportMode.tram)), isTrue);
    // Running on the left: RER A on its RATP section too, Transilien, the tram-trains on railway lines
    expect(TrainPositions.headRightFor(rerA), isFalse);
    expect(TrainPositions.headRightFor(const LineSummary(id: 'C01739', name: 'J', mode: TransportMode.transilien)), isFalse);
    expect(TrainPositions.headRightFor(const LineSummary(id: 'C01999', name: 'T11', mode: TransportMode.tram)), isFalse);
    expect(TrainPositions.headRightFor(null), isFalse);
  });

  Future<void> pumpTrain(WidgetTester tester, {required bool headRight}) => tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('fr'),
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TrainPositions(positions: const ['front'], color: const Color(0xFFFFCD00), headRight: headRight)),
      ));

  testWidgets('"Où monter ?" answered over a small train drawn from its front, the way it goes', (tester) async {
    await pumpTrain(tester, headRight: false);

    expect(find.text(currentL10n.goWhereToBoard), findsOneWidget);
    expect(find.text("À l'avant"), findsOneWidget);
    expect(find.text(currentL10n.goDirectionOfTravel), findsOneWidget);
    // Read out as one sentence
    expect(find.bySemanticsLabel(boardingLabel(['front'])), findsOneWidget);
  });

  testWidgets('the way it goes under its front: to the left, or to the right on a metro platform', (tester) async {
    await pumpTrain(tester, headRight: false);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);

    await pumpTrain(tester, headRight: true);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    // Beside the train's right end
    final train = tester.getRect(find.byWidgetPredicate((widget) => widget is CustomPaint && widget.size == const Size.fromHeight(38)));
    expect(tester.getRect(find.byIcon(Icons.arrow_forward)).right, closeTo(train.right, 1));
  });
}
