import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/map/map_overlay.dart';
import '../../core/utils/refresh.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import '../journey/journey_preferences.dart';
import '../journey/journey_request.dart';
import '../../core/widgets/ui.dart';

typedef BikeKey = ({double lat, double lon, int radius, int limit});

/// Vélib stations around a position, closest first, refreshed every minute while shown (the open data's pace)
final nearbyBikesProvider = FutureProvider.autoDispose.family<List<BikeStation>, BikeKey>((ref, key) async {
  ref.refreshEvery(const Duration(seconds: 60));
  return ref.watch(mobilityApiProvider).bikesNearby(key.lat, key.lon, radius: key.radius, limit: key.limit);
});

/// Vélib green, as on the stations
const velibColor = Color(0xFF4CAF50);

/// Map pins of Vélib stations: the bikes available, faded when none can be taken
List<MapPin> bikeStationPins(BuildContext context, List<BikeStation> stations) => [
      for (final station in stations)
        MapPin(
          point: LatLng(station.lat, station.lon),
          color: velibColor,
          label: context.l10n.bikePinLabel(station.name, station.bikes),
          childSize: const Size(44, 24),
          onTap: () => showBikeStationSheet(context, station),
          child: _BikePin(station: station),
        ),
    ];

class _BikePin extends StatelessWidget {
  const _BikePin({required this.station});

  final BikeStation station;

  @override
  Widget build(BuildContext context) {
    final available = station.renting && station.bikes > 0;
    return Opacity(
      opacity: available ? 1 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          color: available ? velibColor : Colors.grey.shade600,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pedal_bike, size: 13, color: Colors.white),
            const SizedBox(width: 2),
            Text('${station.bikes}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Mechanical and electric bikes, free docks
class BikeCounts extends StatelessWidget {
  const BikeCounts({super.key, required this.station, this.bikes = true, this.docks = true});

  final BikeStation station;
  final bool bikes;
  final bool docks;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget count(IconData icon, int value, String tooltip, Color color) => Tooltip(
          message: tooltip,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: value > 0 ? color : muted),
              const SizedBox(width: 3),
              Text('$value', style: TextStyle(fontWeight: FontWeight.w600, color: value > 0 ? null : muted)),
            ],
          ),
        );

    if (!station.renting && !station.returning) {
      return Text(context.l10n.bikeStationClosed, style: TextStyle(color: Theme.of(context).colorScheme.error));
    }
    return Wrap(
      spacing: 12,
      children: [
        if (bikes) ...[
          count(Icons.pedal_bike, station.mechanical, context.l10n.bikesMechanical, velibColor),
          count(Icons.electric_bike, station.electric, context.l10n.bikesElectric, Colors.blue.shade600),
        ],
        if (docks) count(Icons.local_parking, station.docks, context.l10n.bikeDocksFree, Colors.indigo.shade400),
      ],
    );
  }
}

/// A station: name, distance, availability
class BikeStationTile extends StatelessWidget {
  const BikeStationTile({super.key, required this.station, this.onTap});

  final BikeStation station;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(backgroundColor: velibColor, foregroundColor: Colors.white, child: Icon(Icons.pedal_bike)),
      title: Text(station.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(padding: const EdgeInsets.only(top: 2), child: BikeCounts(station: station)),
      trailing: station.distance == null ? null : Text(formatDistance(station.distance!)),
      onTap: onTap ?? () => showBikeStationSheet(context, station),
    );
  }
}

/// Vélib stations around a position, the closest first
class NearbyBikesSection extends ConsumerWidget {
  const NearbyBikesSection({super.key, required this.bikeKey});

  final BikeKey bikeKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(nearbyBikesProvider(bikeKey)).value ?? const <BikeStation>[];
    if (stations.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Vélib'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(children: [for (final station in stations.take(3)) BikeStationTile(station: station)]),
          ),
        ),
      ],
    );
  }
}

Future<void> showBikeStationSheet(BuildContext context, BikeStation station) {
  final router = GoRouter.of(context);
  return showModalBottomSheet<void>(
    context: context,
    // Above the whole app, not inside the panel or the bottom sheet
    useRootNavigator: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.bikeStation, style: theme.textTheme.labelLarge?.copyWith(fontSize: 13, color: velibColor)),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: Text(station.name, style: theme.textTheme.titleLarge?.copyWith(fontSize: 22, height: 1.25))),
                    if (station.distance case final distance?) ...[
                      const SizedBox(width: 8),
                      Text(formatDistance(distance), style: theme.textTheme.bodySmall?.copyWith(fontSize: 14)),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                // Three figures read at a glance
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (index, (icon, color, value, label)) in [
                      (Icons.pedal_bike, velibColor, station.mechanical, context.l10n.bikesMechanicalCount(station.mechanical)),
                      (Icons.electric_bike, Colors.blue.shade600, station.electric, context.l10n.bikesElectricCount(station.electric)),
                      (Icons.local_parking, Colors.indigo.shade400, station.docks, context.l10n.bikeDocksCount(station.docks)),
                    ].indexed) ...[
                      if (index > 0) const SizedBox(width: 8),
                      Expanded(child: _SheetCount(icon: icon, color: color, value: value, label: label)),
                    ],
                  ],
                ),
                if (!station.renting || !station.returning)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      !station.renting && !station.returning
                          ? context.l10n.bikeStationClosed
                          : !station.renting
                              ? context.l10n.bikeNoRenting
                              : context.l10n.bikeNoReturning,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (station.reportedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(context.l10n.updatedAt(formatClock(station.reportedAt!)),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.directions),
                  label: Text(context.l10n.goThere),
                  onPressed: () {
                    Navigator.pop(context);
                    router.push(Routes.journey(ref.read(journeyPreferencesProvider).apply(JourneyRequest(
                      from: const JourneyPlace.currentLocation(),
                      to: JourneyPlace.point(name: context.l10n.bikeStationNamed(station.name), lat: station.lat, lon: station.lon),
                    ))));
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// A figure of the station sheet: its icon, the number in large, what it counts
class _SheetCount extends StatelessWidget {
  const _SheetCount({required this.icon, required this.color, required this.value, required this.label});

  final IconData icon;
  final Color color;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.colors.subtle, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: value > 0 ? color : context.colors.muted),
          const SizedBox(height: 6),
          Text('$value', style: theme.textTheme.headlineSmall?.copyWith(fontSize: 28, height: 1.1, color: value > 0 ? null : context.colors.muted)),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.3)),
        ],
      ),
    );
  }
}
