import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../app/theme.dart';
import '../../core/map/map_overlay.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/l10n.dart';
import '../auth/auth_controller.dart';
import '../bikes/bike_widgets.dart';
import '../daily_trips/daily_trip_widgets.dart';
import '../favorites/favorite_widgets.dart';
import '../home_widget/home_widget_sync.dart';
import '../traffic/traffic_screen.dart';
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

    return MapOverlayScope(
      // Stops above the stations; only what the filter shows
      overlay: MapOverlay(pins: [
        if (filter == NearbyFilter.all || filter == NearbyFilter.bikes) ...bikeStationPins(context, bikes),
        if (filter != NearbyFilter.bikes)
          ...nearbyStopPins(context, [
            for (final departures in stops)
              if (filter == NearbyFilter.all || departures.lines.any((line) => filter.shows(line.line.mode))) departures,
          ]),
      ]),
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(nearbyDeparturesProvider(key).future),
        child: CustomScrollView(
          controller: PanelScrollScope.of(context),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(child: _SearchBox(onTap: () => context.push(Routes.search))),
                    const SizedBox(width: 4),
                    const _AccountMenu(),
                  ],
                ),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              sliver: SliverToBoxAdapter(child: FavoriteShortcuts()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(child: TrafficSummaryCard()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(child: DailyTripsSection()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(child: FavoriteStopsSection()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(child: FavoriteLinesSection()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(context.l10n.homeNearby),
                    if (!origin.isUser)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
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
                    const NearbyFilterBar(),
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountMenu extends ConsumerWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final signedIn = ref.watch(authControllerProvider) == AuthStatus.signedIn;
    return PopupMenuButton<void>(
      tooltip: l10n.account,
      icon: CircleAvatar(
        radius: 20,
        backgroundColor: signedIn ? Theme.of(context).colorScheme.primary : context.colors.card,
        foregroundColor: signedIn ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
        child: Icon(signedIn ? Icons.person : Icons.person_outline, size: 22),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          onTap: () => ref.read(localeProvider.notifier).toggle(),
          child: ListTile(leading: const Icon(Icons.translate), title: Text(l10n.otherLanguage), contentPadding: EdgeInsets.zero),
        ),
        PopupMenuItem(
          onTap: () => context.push(Routes.about),
          child: ListTile(leading: const Icon(Icons.info_outline), title: Text(l10n.about), contentPadding: EdgeInsets.zero),
        ),
        if (signedIn)
          PopupMenuItem(
            onTap: () => context.push(Routes.account),
            child: ListTile(leading: const Icon(Icons.manage_accounts_outlined), title: Text(l10n.accountTitle), contentPadding: EdgeInsets.zero),
          ),
        if (signedIn)
          PopupMenuItem(
            onTap: () => ref.read(authControllerProvider.notifier).signOut(),
            child: ListTile(leading: const Icon(Icons.logout), title: Text(l10n.signOut), contentPadding: EdgeInsets.zero),
          )
        else
          PopupMenuItem(
            onTap: () => context.go(Routes.signIn(Routes.home)),
            child: ListTile(
              leading: const Icon(Icons.login),
              title: Text(l10n.signInAction),
              subtitle: Text(l10n.guestModeHint),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}
