import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../../l10n/l10n.dart';
import '../auth/auth_controller.dart';
import '../bikes/bike_widgets.dart';
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
    final theme = Theme.of(context);

    return MapOverlayScope(
      // Stops above the stations
      overlay: MapOverlay(pins: [...bikeStationPins(context, bikes), ...nearbyStopPins(context, stops)]),
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(nearbyDeparturesProvider(key).future),
        child: CustomScrollView(
          controller: PanelScrollScope.of(context),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(child: _SearchBox(onTap: () => context.push(Routes.search))),
                    const _AccountMenu(),
                  ],
                ),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverToBoxAdapter(child: FavoriteShortcuts()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              sliver: SliverToBoxAdapter(child: TrafficSummaryCard()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(child: FavoriteStopsSection()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              sliver: SliverToBoxAdapter(child: FavoriteLinesSection()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.homeNearby, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    if (!origin.isUser)
                      Text(context.l10n.homeNoPosition,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    // Settings can only be opened on phones
                    if (!origin.isUser && !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS))
                      if (ref.watch(locationIssueProvider) case final issue?)
                        TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          icon: const Icon(Icons.my_location, size: 18),
                          label: Text(issue == LocationIssue.serviceDisabled ? context.l10n.locationTurnOn : context.l10n.locationAllow),
                          onPressed: () => fixLocationIssue(ref, issue),
                        ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(child: NearbyDeparturesList(position: key)),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              sliver: SliverToBoxAdapter(child: NearbyBikesSection(bikeKey: bikeKey)),
            ),
            SliverToBoxAdapter(child: HomeWidgetSync(closest: stops.firstOrNull)),
          ],
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(context.l10n.homeSearchHint, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16)),
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
    return PopupMenuButton<void>(
      tooltip: l10n.account,
      icon: const Icon(Icons.account_circle_outlined),
      itemBuilder: (context) => [
        PopupMenuItem(
          onTap: () => ref.read(localeProvider.notifier).toggle(),
          child: ListTile(leading: const Icon(Icons.translate), title: Text(l10n.otherLanguage), contentPadding: EdgeInsets.zero),
        ),
        PopupMenuItem(
          onTap: () => ref.read(authControllerProvider.notifier).signOut(),
          child: ListTile(leading: const Icon(Icons.logout), title: Text(l10n.signOut), contentPadding: EdgeInsets.zero),
        ),
      ],
    );
  }
}
