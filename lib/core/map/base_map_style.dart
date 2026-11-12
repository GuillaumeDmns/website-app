import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// OpenFreeMap's Liberty style (free, no key, OpenStreetMap data), in dark mode too: its dark style (Fiord) showed too
/// little of the streets. Both maps draw it: MapLibre on Android, iOS and the web, vector_map_tiles on desktop.
const baseMapStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';

/// Layers of the style taken out once it is loaded: its points of interest (shops, restaurants… by importance) and
/// its stations, which the app's own stop pins show better; streets, places and the 3D buildings stay
const hiddenStyleLayers = ['poi_r1', 'poi_r7', 'poi_r20', 'poi_transit'];

/// [theme] without the [hiddenStyleLayers]; a style without one of them (another version of it) is fine as it is
vtr.Theme withoutHiddenLayers(vtr.Theme theme) => vtr.Theme(
      id: theme.id,
      version: theme.version,
      layers: [for (final layer in theme.layers) if (!hiddenStyleLayers.contains(layer.id)) layer],
    );

/// The style for the desktop map (vector_map_tiles), read once: its layers without the hidden ones, its tile sources,
/// its sprites. Riverpod tries again after a failure (offline at startup).
final baseMapStyleProvider = FutureProvider<vmt.Style>((ref) async {
  final style = await vmt.StyleReader(uri: baseMapStyleUrl).read();
  return vmt.Style(
    name: style.name,
    theme: withoutHiddenLayers(style.theme),
    providers: style.providers,
    sprites: style.sprites,
    center: style.center,
    zoom: style.zoom,
  );
});
