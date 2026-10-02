import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/shell.dart';
import '../../core/api/models.dart';
import '../../core/map/map_overlay.dart';
import 'nearby_departures.dart';

/// Departures around a searched address or place
class AroundScreen extends ConsumerWidget {
  const AroundScreen({super.key, required this.position, required this.name});

  final LatLng position;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = nearbyKey(position);
    final stops = ref.watch(nearbyDeparturesProvider(key)).value ?? const <StopDepartures>[];
    final theme = Theme.of(context);

    return MapOverlayScope(
      overlay: MapOverlay(
        pins: [
          MapPin(point: position, color: theme.colorScheme.error, icon: Icons.place, size: 26, label: name),
          ...nearbyStopPins(context, stops),
        ],
        fit: [position],
      ),
      child: ListView(
        controller: PanelScrollScope.of(context),
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
        children: [
          Row(
            children: [
              IconButton(tooltip: 'Retour', icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
              Expanded(
                child: Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 0, 12),
            child: Text('Départs à proximité', style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: NearbyDeparturesList(position: key),
          ),
        ],
      ),
    );
  }
}
