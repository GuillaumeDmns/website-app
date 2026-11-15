import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/utils/refresh.dart';
import '../../core/widgets/async_view.dart';
import '../../l10n/l10n.dart';
import '../favorites/favorite_widgets.dart';
import '../favorites/favorites_controller.dart';
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
  return ref.mobilityApi.nearbyDepartures(key.lat, key.lon);
});

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

  bool shows(TransportMode mode) => switch (this) {
    all => true,
    rail => mode == TransportMode.metro || mode.isRail,
    bus => mode == TransportMode.bus || mode == TransportMode.noctilien,
    tram => mode == TransportMode.tram,
    bikes => false,
  };
}

class _NearbyFilterController extends Notifier<NearbyFilter> {
  @override
  NearbyFilter build() => NearbyFilter.all;

  void select(NearbyFilter filter) => state = filter;
}

/// The kind of departures shown around, for the time the app runs
final nearbyFilterProvider = NotifierProvider<_NearbyFilterController, NearbyFilter>(_NearbyFilterController.new);

/// Under "À proximité": chips choosing [nearbyFilterProvider], scrolled sideways, which also choose the stops on the
/// map. The kind chosen is filled; tapped again, it goes back to everything.
class NearbyFilterChips extends ConsumerWidget {
  const NearbyFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(nearbyFilterProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in NearbyFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                button: true,
                selected: filter == selected,
                child: Material(
                  color: filter == selected ? scheme.onSurface : Colors.transparent,
                  shape: StadiumBorder(side: filter == selected ? BorderSide.none : BorderSide(color: scheme.outline)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => ref
                        .read(nearbyFilterProvider.notifier)
                        .select(filter == selected && filter != NearbyFilter.all ? NearbyFilter.all : filter),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      child: Text(
                        filter.label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 14,
                          fontWeight: filter == selected ? FontWeight.w600 : FontWeight.w500,
                          color: filter == selected ? scheme.surface : scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cards of the departures around [position], of the kind chosen with [NearbyFilterChips]
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
                child: StopDeparturesCard(
                  departures: departures,
                  now: now,
                  // A long press saves the stop (or takes it out) without opening it
                  onLongPress: () {
                    final favorites = ref.read(favoritesProvider.notifier);
                    final saved = favorites.stopFavorite(departures.stop.id) != null;
                    HapticFeedback.mediumImpact();
                    runFavoriteAction(
                      context,
                      () => favorites.toggleStop(departures.stop),
                      success: saved
                          ? context.l10n.favoriteStopRemoved(departures.stop.name)
                          : context.l10n.favoriteSaved(departures.stop.name),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
