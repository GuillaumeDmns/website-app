import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:website_app/core/api/models.dart';
import 'package:website_app/features/journey/widgets/journey_card.dart';
import 'package:website_app/l10n/l10n.dart';

import '../../../support/samples.dart';

void main() {
  setUp(() => useLocale(const Locale('fr')));
  final start = DateTime.utc(2026, 11, 14, 7);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));

  /// On foot to the metro, the metro for [ride] minutes
  JourneyOption direct(int ride) => journey([walk(start, 300), transit(at(5), ride * 60)]);

  /// The metro then the RER
  JourneyOption withTransfer(int minutes) => journey([
        transit(start, 300, to: gareDeLyon),
        transit(at(7), (minutes - 7) * 60, line: rerA, from: gareDeLyon),
      ]);

  test("the planner's own words tell an option apart: its tags first", () {
    final l10n = currentL10n;
    // As IDFM's Navitia answers
    expect(journeyTag(direct(18).copyWith(type: 'best', tags: ['walking', 'reliable', 'ecologic', 'asap'])), l10n.journeyAsap);
    expect(journeyTag(direct(18).copyWith(type: 'best', tags: ['walking', 'ecologic', 'proposal'])), l10n.journeyBest);
    expect(journeyTag(direct(28).copyWith(type: 'comfort', tags: ['walking', 'reliable', 'ecologic', 'less_transfers'])), l10n.journeyComfort);
    expect(journeyTag(direct(35).copyWith(type: 'comfort', tags: ['walking', 'ecologic', 'less_fallbacks'])), l10n.journeyLessWalk);
  });

  test('tags and types several options carry say nothing', () {
    expect(journeyTag(withTransfer(23).copyWith(type: 'rapid', tags: ['walking', 'reliable', 'ecologic'])), isNull);
    expect(journeyTag(direct(22).copyWith(type: 'comfort', tags: ['walking', 'ecologic'])), isNull);
    expect(journeyTag(direct(22).copyWith(type: null)), isNull);
    expect(journeyTag(direct(22).copyWith(type: 'a_new_one')), isNull);
  });

  test('without a tag, the type: a way without public transport by its kind', () {
    final l10n = currentL10n;
    final onFoot = journey([walk(start, 1800)]);
    expect(journeyTag(onFoot.copyWith(type: 'non_pt_walk', tags: ['non_pt', 'non_pt_walking', 'walking', 'ecologic'])), l10n.journeyWalk);
    expect(journeyTag(onFoot.copyWith(type: 'bike_share', tags: ['bike_share'])), l10n.journeyBikeShare);
    expect(journeyTag(direct(18).copyWith(type: 'best')), l10n.journeyBest);
    expect(journeyTag(direct(18).copyWith(type: 'fastest')), l10n.journeyRapid);
  });

  test('the fare is only worth showing when the options do not cost the same', () {
    expect(faresDiffer([direct(20).copyWith(fare: 250), direct(25).copyWith(fare: 250)]), isFalse);
    expect(faresDiffer([direct(20).copyWith(fare: 250), direct(25).copyWith(fare: 205)]), isTrue);
    expect(faresDiffer([direct(20).copyWith(fare: 250), direct(25)]), isTrue);
    expect(faresDiffer([direct(20), direct(25)]), isFalse);
  });
}
