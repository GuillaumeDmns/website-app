import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/features/journey/journey_labels.dart';

void main() {
  test("a place's town apart from its name", () {
    expect(placeParts('14 Rue Auber (Paris)'), (name: '14 Rue Auber', town: 'Paris'));
    expect(placeParts('3 Avenue Léon de Bertalot (Courbevoie)'), (name: '3 Avenue Léon de Bertalot', town: 'Courbevoie'));
  });

  test('a town that only repeats the name is not said twice', () {
    expect(placeParts('Asnières-sur-Seine (Asnières-sur-Seine)'), (name: 'Asnières-sur-Seine', town: null));
  });

  test('a name without town, or with brackets in it, is kept whole', () {
    expect(placeParts('Châtelet'), (name: 'Châtelet', town: null));
    expect(placeParts('Gare (RER) de Nanterre'), (name: 'Gare (RER) de Nanterre', town: null));
  });

  test('a stop of the timeline goes by its name', () {
    expect(stopName('Gare Saint-Lazare (Paris)'), 'Gare Saint-Lazare');
    expect(stopName('Opéra'), 'Opéra');
  });
}
