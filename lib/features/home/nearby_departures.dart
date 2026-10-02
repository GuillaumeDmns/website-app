import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../../core/widgets/async_view.dart';
import '../stops/widgets/stop_departures_card.dart';

typedef NearbyKey = ({double lat, double lon});

/// Rounds a position to about 100 m so that small moves don't refetch
NearbyKey nearbyKey(LatLng position) {
  double round(double value) => (value * 1000).roundToDouble() / 1000;
  return (lat: round(position.latitude), lon: round(position.longitude));
}

/// Departures around a position, refreshed every 30 s while shown
final nearbyDeparturesProvider = FutureProvider.autoDispose.family<List<StopDepartures>, NearbyKey>((ref, key) async {
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(mobilityApiProvider).nearbyDepartures(key.lat, key.lon);
});

/// Map pins of the stop areas of [stops]
List<MapPin> nearbyStopPins(BuildContext context, List<StopDepartures> stops) => [
      for (final departures in stops)
        MapPin(
          point: LatLng(departures.stop.lat, departures.stop.lon),
          color: Theme.of(context).colorScheme.primary,
          icon: Icons.directions_transit,
          size: 22,
          label: departures.stop.name,
          onTap: () => context.push(Routes.stop(departures.stop.id)),
        ),
    ];

/// Cards of the departures around [position]
class NearbyDeparturesList extends ConsumerWidget {
  const NearbyDeparturesList({super.key, required this.position});

  final NearbyKey position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearby = ref.watch(nearbyDeparturesProvider(position));
    final now = ref.watch(nowProvider).value ?? DateTime.now();

    return AsyncView(
      value: nearby,
      onRetry: () => ref.invalidate(nearbyDeparturesProvider(position)),
      data: (stops) => stops.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucun arrêt à moins de 500 m', textAlign: TextAlign.center),
            )
          : Column(
              children: [
                for (final departures in stops)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StopDeparturesCard(departures: departures, now: now),
                  ),
              ],
            ),
    );
  }
}
