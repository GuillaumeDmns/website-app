import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../app/theme.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/geo.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/l10n.dart';
import '../auth/account_photo.dart';
import '../auth/account_sheet.dart';
import '../bikes/bike_widgets.dart';
import '../daily_trips/daily_trip_widgets.dart';
import '../daily_trips/daily_trips.dart';
import '../favorites/favorite_widgets.dart';
import '../favorites/favorites_controller.dart';
import '../home_widget/home_widget_sync.dart';
import '../remote_config/remote_config_widgets.dart';
import '../traffic/traffic_screen.dart';
import '../traffic/traffic_providers.dart';
import 'map_stops.dart';
import 'nearby_departures.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final origin = ref.watch(nearbyOriginProvider);
    final key = nearbyKey(origin.position);
    final stops = ref.watch(nearbyDeparturesProvider(key)).value ?? const <StopDepartures>[];
    final bikeKey = (lat: key.lat, lon: key.lon, radius: 500, limit: 10);
    final bikes = ref.watch(nearbyBikesProvider(bikeKey)).value ?? const <BikeStation>[];
    final filter = ref.watch(nearbyFilterProvider);
    final theme = Theme.of(context);
    final place = suggestedPlace(ref, ref.watch(nowProvider).value ?? DateTime.now());
    final commute = place == null ? null : tripTo(ref.watch(dailyTripsProvider).value ?? const [], place);

    return MapOverlayScope(
      // Stops above the stations; only what the filter shows. Close enough, every stop of the part of the map shown
      // has its marker with its lines; the ones around the user, listed at the bottom of the page, on top.
      overlay: MapOverlay(pins: [
        if (filter == NearbyFilter.all || filter == NearbyFilter.bikes) ...bikeStationPins(context, bikes),
        if (filter != NearbyFilter.bikes)
          ...stopPins(
            context,
            [
              ...ref.watch(mapStopsProvider).value ?? const <StopAreaSummary>[],
              // The closest one last: on top
              for (final departures in stops.reversed) markerStop(departures),
            ],
            shows: filter == NearbyFilter.all ? null : filter.shows,
            severities: ref.watch(lineSeveritiesProvider),
          ),
      ]),
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(nearbyDeparturesProvider(key).future),
        child: CustomScrollView(
          controller: PanelScrollScope.of(context),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              sliver: SliverToBoxAdapter(
                child: _SearchBox(onTap: () => context.push(Routes.search)),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(child: RemoteNotice()),
            ),
            if (place != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverToBoxAdapter(child: _Suggestion(place: place, trip: commute)),
              ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              sliver: SliverToBoxAdapter(child: FavoriteShortcuts()),
            ),
            // What the user saved first: their trips, stops and lines; then the traffic, and what is around last (its
            // stops are on the map already)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(child: DailyTripsSection(except: commute?.id)),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(child: FavoriteStopsSection()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(child: FavoriteLinesSection()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(child: TrafficSummaryCard()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                      context.l10n.homeNearby,
                      trailing: UpdatedAgo(value: ref.watch(nearbyDeparturesProvider(key))),
                    ),
                    // Which kind of departures, and of stops on the map
                    const NearbyFilterChips(),
                    if (!origin.isUser)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                        child: Text(context.l10n.homeNoPosition, style: theme.textTheme.bodySmall),
                      ),
                    // Settings can only be opened on phones
                    if (!origin.isUser && !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS))
                      if (ref.watch(locationIssueProvider) case final issue?)
                        TextButton.icon(
                          icon: const Icon(Icons.my_location, size: 18),
                          label: Text(issue == LocationIssue.serviceDisabled ? context.l10n.locationTurnOn : context.l10n.locationAllow),
                          onPressed: () => fixLocationIssue(ref, issue),
                        ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: filter == NearbyFilter.bikes ? const SizedBox.shrink() : NearbyDeparturesList(position: key),
              ),
            ),
            if (filter == NearbyFilter.all || filter == NearbyFilter.bikes)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverToBoxAdapter(child: NearbyBikesSection(bikeKey: bikeKey)),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
            SliverToBoxAdapter(child: HomeWidgetSync(closest: stops.firstOrNull)),
          ],
        ),
      ),
    );
  }
}

/// The place the user likely heads to now: home in the evening, work in the morning (when saved, and away from it)
Favorite? suggestedPlace(WidgetRef ref, DateTime now) {
  final hour = now.toLocal().hour;
  final kind = hour >= 16 || hour < 3
      ? FavoriteKind.home
      : hour >= 5 && hour < 11
          ? FavoriteKind.work
          : null;
  final favorites = ref.watch(favoritesProvider).value ?? const <Favorite>[];
  final place = kind == null ? null : favorites.where((favorite) => favorite.kind == kind).firstOrNull;
  final user = ref.watch(userLocationProvider).value;
  if (place == null || place.lat == null || (user != null && metersBetween(user, LatLng(place.lat!, place.lon!)) < 300)) {
    return null;
  }
  return place;
}

/// What the user likely wants now, in one tap. With a daily trip there, one card: the suggestion and the trip become
/// the same thing, with GO and what threatens the trip ([DailyTripCard]); else a chip searching the way there.
class _Suggestion extends ConsumerWidget {
  const _Suggestion({required this.place, required this.trip});

  final Favorite place;
  final DailyTrip? trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = place.kind == FavoriteKind.home;
    final icon = home ? Icons.home_rounded : Icons.work_rounded;
    final title = home ? context.l10n.homeSuggestHome : context.l10n.homeSuggestWork;
    if (trip case final trip?) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DailyTripCard(key: ValueKey('commute-${trip.id}-${place.kind}'), trip: trip, heading: (icon: icon, title: title)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: Icon(icon, size: 18),
          label: Text(title),
          onPressed: () => goToPlace(context, ref, place),
        ),
      ),
    );
  }
}

/// "Où allez-vous ?": the big entry of the app, opening the search
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: context.colors.card,
      shape: StadiumBorder(side: BorderSide(color: scheme.outline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 3, 4, 3),
          child: Row(
            children: [
              Icon(Icons.search, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.homeSearchHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              const _AccountButton(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who uses the app, at the end of the search box like Google's apps: opens the account and the app's settings
/// ([showAccountSheet])
class _AccountButton extends StatelessWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.account,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
      icon: const AccountAvatar(size: 36),
      onPressed: () => showAccountSheet(context),
    );
  }
}
