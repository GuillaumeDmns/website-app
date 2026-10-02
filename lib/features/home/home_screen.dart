import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../auth/auth_controller.dart';
import 'nearby_departures.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final origin = ref.watch(nearbyOriginProvider);
    final key = nearbyKey(origin.position);
    final stops = ref.watch(nearbyDeparturesProvider(key)).value ?? const <StopDepartures>[];
    final theme = Theme.of(context);

    return MapOverlayScope(
      overlay: MapOverlay(pins: nearbyStopPins(context, stops)),
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
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('À proximité', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    if (!origin.isUser)
                      Text('Position indisponible : autour du centre de la carte',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverToBoxAdapter(child: NearbyDeparturesList(position: key)),
            ),
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
              Text('Où allez-vous ?', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16)),
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
    return PopupMenuButton<void>(
      tooltip: 'Compte',
      icon: const Icon(Icons.account_circle_outlined),
      itemBuilder: (context) => [
        PopupMenuItem(
          onTap: () => ref.read(authControllerProvider.notifier).signOut(),
          child: const ListTile(leading: Icon(Icons.logout), title: Text('Se déconnecter'), contentPadding: EdgeInsets.zero),
        ),
      ],
    );
  }
}
