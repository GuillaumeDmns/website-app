import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/map/maplibre_main_map.dart';

void main() {
  test('the base map loses its points of interest and stations, not its streets, places nor 3D buildings', () {
    // Layer ids of OpenFreeMap's Liberty style
    expect(hiddenStyleLayers, containsAll(['poi_r1', 'poi_r7', 'poi_r20', 'poi_transit']));
    expect(hiddenStyleLayers.every((id) => id.startsWith('poi_')), isTrue);
    expect(hiddenStyleLayers, isNot(contains('building-3d')));
  });
}
