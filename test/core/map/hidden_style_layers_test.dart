import 'package:flutter_test/flutter_test.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';
import 'package:website_app/core/map/base_map_style.dart';

void main() {
  test('the base map loses its points of interest and stations, not its streets, places nor 3D buildings', () {
    // Layer ids of OpenFreeMap's Liberty style
    expect(hiddenStyleLayers, containsAll(['poi_r1', 'poi_r7', 'poi_r20', 'poi_transit']));
    expect(hiddenStyleLayers.every((id) => id.startsWith('poi_')), isTrue);
    expect(hiddenStyleLayers, isNot(contains('building-3d')));
  });

  test('the desktop map reads the style without the hidden layers, the others kept in order', () {
    Map<String, Object> layer(String id, String type) => {
          'id': id,
          'type': type,
          'source': 'openmaptiles',
          'source-layer': 'poi',
          if (type == 'symbol') 'layout': {'text-field': '{name}'},
          'paint': {type == 'symbol' ? 'text-color' : '$type-color': '#888888'},
        };
    final theme = ThemeReader().read({
      'id': 'liberty',
      'version': 8,
      'layers': [
        {'id': 'background', 'type': 'background', 'paint': {'background-color': '#f8f4f0'}},
        layer('highway_minor', 'line'),
        layer('poi_r20', 'symbol'),
        layer('building', 'fill'),
        layer('poi_r7', 'symbol'),
        layer('poi_r1', 'symbol'),
        layer('poi_transit', 'symbol'),
        layer('label_city', 'symbol'),
      ],
    });

    final shown = withoutHiddenLayers(theme);

    expect(shown.layers.map((layer) => layer.id), ['background', 'highway_minor', 'building', 'label_city']);
    expect(shown.id, theme.id);
    expect(shown.version, theme.version);
  });
}
