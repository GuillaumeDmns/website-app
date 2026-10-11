import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../l10n/l10n.dart';
import '../journey/journey_preferences.dart';
import '../journey/journey_request.dart';

/// Address of a point of the map, null when there is none nearby
final mapPlaceProvider = FutureProvider.autoDispose.family<PlaceResult?, LatLng>(
  (ref, position) => ref.watch(mobilityApiProvider).reverse(position.latitude, position.longitude),
);

/// Long press on the map: the point's address, and going there, leaving from there or the departures around
void showMapPlaceSheet(BuildContext context, LatLng position) {
  // About 1 m: the same point gives the same address
  final point = LatLng(double.parse(position.latitude.toStringAsFixed(5)), double.parse(position.longitude.toStringAsFixed(5)));
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) => MapPlaceSheet(
      position: point,
      onOpen: (location) {
        Navigator.pop(sheetContext);
        context.push(location);
      },
    ),
  );
}

class MapPlaceSheet extends ConsumerWidget {
  const MapPlaceSheet({super.key, required this.position, required this.onOpen});

  final LatLng position;

  /// Opens a location of the app (the sheet closes first)
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final address = ref.watch(mapPlaceProvider(position));
    // Without address (none nearby, no network), the point keeps a plain name
    final name = address.isLoading ? null : address.value?.name ?? l10n.pointOnMap;
    final place = JourneyPlace.point(name: name ?? l10n.pointOnMap, lat: position.latitude, lon: position.longitude);
    String journey(JourneyRequest request) => Routes.journey(ref.read(journeyPreferencesProvider).apply(request));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.place, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: name == null
                      ? const LinearProgressIndicator()
                      : Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.directions, size: 18),
                  label: Text(l10n.goThere),
                  onPressed: name == null
                      ? null
                      : () => onOpen(journey(JourneyRequest(from: const JourneyPlace.currentLocation(), to: place))),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.trip_origin, size: 18),
                  label: Text(l10n.leaveFromHere),
                  onPressed: name == null ? null : () => onOpen(journey(JourneyRequest(from: place))),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.departure_board, size: 18),
                  label: Text(l10n.departuresAround),
                  onPressed: name == null ? null : () => onOpen(Routes.around(position.latitude, position.longitude, place.name)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
