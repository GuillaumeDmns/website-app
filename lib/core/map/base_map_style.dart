/// OpenFreeMap's Liberty style (free, no key, OpenStreetMap data), in dark mode too: its dark style (Fiord) showed too
/// little of the streets. Drawn by MapLibre on every platform.
const baseMapStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';

/// Layers of the style taken out once it is loaded: its points of interest (shops, restaurants… by importance) and
/// its stations, which the app's own stop pins show better; streets, places and the 3D buildings stay
const hiddenStyleLayers = ['poi_r1', 'poi_r7', 'poi_r20', 'poi_transit'];
