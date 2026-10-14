import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/refresh.dart';
import '../../core/widgets/async_view.dart';
import '../../l10n/l10n.dart';
import '../stops/widgets/stop_departures_card.dart';

typedef NearbyKey = ({double lat, double lon});

/// Rounds a position to about 100 m so that small moves don't refetch
NearbyKey nearbyKey(LatLng position) {
  double round(double value) => (value * 1000).roundToDouble() / 1000;
  return (lat: round(position.latitude), lon: round(position.longitude));
}

/// Departures around a position, refreshed every 30 s while shown
final nearbyDeparturesProvider = FutureProvider.autoDispose.family<List<StopDepartures>, NearbyKey>((ref, key) async {
  ref.refreshEvery(const Duration(seconds: 30));
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

/// Kind of departures shown around: all, rail (metro, RER, trains), buses (and Noctiliens), trams, Vélib
enum NearbyFilter {
  all,
  rail,
  bus,
  tram,
  bikes;

  String get label => switch (this) {
    all => currentL10n.filterAll,
    rail => currentL10n.filterRail,
    bus => currentL10n.filterBus,
    tram => currentL10n.filterTram,
    bikes => 'Vélib',
  };

  IconData get icon => switch (this) {
    all => Icons.near_me_outlined,
    rail => Icons.subway_outlined,
    bus => Icons.directions_bus_outlined,
    tram => Icons.tram_outlined,
    bikes => Icons.pedal_bike,
  };

  bool shows(TransportMode mode) => switch (this) {
    all => true,
    rail => mode == TransportMode.metro || mode.isRail,
    bus => mode == TransportMode.bus || mode == TransportMode.noctilien,
    tram => mode == TransportMode.tram,
    bikes => false,
  };
}

class _NearbyFilterState extends Notifier<NearbyFilter> {
  @override
  NearbyFilter build() => NearbyFilter.all;

  void select(NearbyFilter filter) => state = filter;
}

/// The kind of departures shown around, for the time the app runs
final nearbyFilterProvider = NotifierProvider<_NearbyFilterState, NearbyFilter>(_NearbyFilterState.new);

/// Chips choosing [nearbyFilterProvider], scrolled sideways
class NearbyFilterBar extends ConsumerWidget {
  const NearbyFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(nearbyFilterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in NearbyFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(filter.icon, size: 18),
                label: Text(filter.label),
                selected: filter == selected,
                onSelected: (_) => ref.read(nearbyFilterProvider.notifier).select(filter),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cards of the departures around [position], of the kind chosen with [NearbyFilterBar]
class NearbyDeparturesList extends ConsumerWidget {
  const NearbyDeparturesList({super.key, required this.position});

  final NearbyKey position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearby = ref.watch(nearbyDeparturesProvider(position));
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final filter = ref.watch(nearbyFilterProvider);

    return AsyncView(
      value: nearby,
      onRetry: () => ref.invalidate(nearbyDeparturesProvider(position)),
      data: (stops) {
        final shown = [
          for (final departures in stops)
            if (filter == NearbyFilter.all)
              departures
            else if (departures.lines.where((line) => filter.shows(line.line.mode)).toList() case final lines when lines.isNotEmpty)
              departures.copyWith(lines: lines),
        ];
        if (shown.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              stops.isEmpty ? context.l10n.nearbyNoStop : context.l10n.nearbyNothingForMode,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return Column(
          children: [
            for (final departures in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: StopDeparturesCard(departures: departures, now: now),
              ),
          ],
        );
      },
    );
  }
}
