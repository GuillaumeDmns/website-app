import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import 'flutter_main_map.dart';
import 'map_panel.dart';
import 'maplibre_main_map.dart';

/// Background tiles of the map; the tests turn them off (no network), which also keeps the flutter_map map
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

/// MapLibre where it runs natively or in the browser (Android, iOS, web): vector tiles drawn by the GPU. flutter_map
/// with the Plan IGN elsewhere (desktop) and in the tests.
final useMapLibreProvider = Provider<bool>((ref) =>
    ref.watch(mapTilesEnabledProvider) &&
    (kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS));

/// The map behind every page. Shows the overlay of the current page and the user position, frames the overlay's
/// points when the page changes, or follows the user (GO on foot), in the part of the map left above the [panel]: as
/// the panel moves, what is in the middle of that part stays in its middle.
class MainMap extends ConsumerWidget {
  const MainMap({super.key, this.panel, this.onLongPress});

  /// The bottom sheet over the map, none in the wide layout
  final MapPanel? panel;

  /// Long press (right click on desktop) on a point of the map
  final void Function(BuildContext context, LatLng position)? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(useMapLibreProvider)
      ? MapLibreMainMap(panel: panel, onLongPress: onLongPress)
      : FlutterMainMap(panel: panel, onLongPress: onLongPress);
}
