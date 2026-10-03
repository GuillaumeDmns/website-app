import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/line_badge.dart';
import '../favorites/favorite_widgets.dart';
import '../journey/journey_request.dart';
import '../traffic/disruption_widgets.dart';
import '../traffic/traffic_providers.dart';
import 'widgets/stop_departures_card.dart';

final stopAreaProvider = FutureProvider.autoDispose.family<StopAreaDetail, String>(
  (ref, stopAreaId) => ref.watch(mobilityApiProvider).stopArea(stopAreaId),
);

/// Departures of a stop area, refreshed every 30 s while shown
final stopDeparturesProvider = FutureProvider.autoDispose.family<StopDepartures, String>((ref, stopAreaId) async {
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(mobilityApiProvider).stopDepartures(stopAreaId, limit: 3);
});

class StopScreen extends ConsumerWidget {
  const StopScreen({super.key, required this.stopAreaId});

  final String stopAreaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stop = ref.watch(stopAreaProvider(stopAreaId));
    final scheme = Theme.of(context).colorScheme;
    final detail = stop.value;

    return MapOverlayScope(
      overlay: detail == null
          ? MapOverlay.empty
          : MapOverlay(
              pins: [
                for (final quay in detail.quays)
                  MapPin(point: LatLng(quay.lat, quay.lon), color: scheme.secondary, size: 8, label: quay.name),
                MapPin(
                  point: LatLng(detail.lat, detail.lon),
                  color: scheme.primary,
                  icon: Icons.directions_transit,
                  size: 26,
                  label: detail.name,
                ),
              ],
              fit: [LatLng(detail.lat, detail.lon)],
            ),
      child: AsyncView(
        value: stop,
        onRetry: () => ref.invalidate(stopAreaProvider(stopAreaId)),
        data: (detail) => _StopContent(detail: detail),
      ),
    );
  }
}

class _StopContent extends ConsumerWidget {
  const _StopContent({required this.detail});

  final StopAreaDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final departures = ref.watch(stopDeparturesProvider(detail.id));
    final now = ref.watch(nowProvider).value ?? DateTime.now();

    return RefreshIndicator(
      onRefresh: () => ref.refresh(stopDeparturesProvider(detail.id).future),
      child: ListView(
        controller: PanelScrollScope.of(context),
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
        children: [
          Row(
            children: [
              IconButton(tooltip: 'Retour', icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
              Expanded(
                child: Text(detail.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (detail.wheelchairBoarding == 1)
                Tooltip(
                  message: 'Accessible en fauteuil roulant',
                  child: Icon(Icons.accessible, color: theme.colorScheme.primary),
                ),
              FavoriteStopButton(stopAreaId: detail.id),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: const Icon(Icons.directions, size: 18),
                label: const Text('Y aller'),
                onPressed: () => context.push(Routes.journey(JourneyRequest(
                  from: const JourneyPlace.currentLocation(),
                  to: JourneyPlace.stopArea(name: detail.name, id: detail.id, lat: detail.lat, lon: detail.lon),
                ))),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 0, 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final line in detail.lines)
                  InkWell(
                    onTap: () => context.push(Routes.line(line.id)),
                    child: LineBadge(line, size: 28),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StopDisruptions(detail: detail),
                Text('Prochains départs', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                AsyncView(
                  value: departures,
                  onRetry: () => ref.invalidate(stopDeparturesProvider(detail.id)),
                  data: (departures) => _DepartureList(departures: departures, now: now),
                ),
                if (detail.connections.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Correspondances à pied', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  for (final connection in detail.connections)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.directions_walk),
                      title: Text(connection.name),
                      trailing: connection.minTransferSeconds == null
                          ? null
                          : Text('${(connection.minTransferSeconds! / 60).ceil()} min'),
                      onTap: () => context.push(Routes.stop(connection.id)),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Disruptions of the stop (elevators…) and of its main lines, with the line badges
class _StopDisruptions extends ConsumerWidget {
  const _StopDisruptions({required this.detail});

  final StopAreaDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disruptions = ref.watch(stopDisruptionsProvider(detail.id)).value;
    if (disruptions == null || disruptions.isEmpty) {
      return const SizedBox.shrink();
    }
    final lines = {for (final line in detail.lines) line.id: line};

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DisruptionList(
        disruptions: disruptions,
        leading: (disruption) {
          final badges = disruption.lineIds.map((id) => lines[id]).nonNulls.take(2).toList();
          if (badges.isEmpty) {
            return null;
          }
          return Row(mainAxisSize: MainAxisSize.min, children: [for (final line in badges) LineBadge(line, size: 24)]);
        },
      ),
    );
  }
}

class _DepartureList extends StatelessWidget {
  const _DepartureList({required this.departures, required this.now});

  final StopDepartures departures;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final rows = departures.lines.where((line) => line.departures.isNotEmpty).toList();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!departures.realtimeAvailable)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Temps réel indisponible, horaires prévus', style: TextStyle(color: Colors.orange.shade700)),
          ),
        if (rows.isEmpty)
          Text('Aucun départ dans les 2 prochaines heures', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        for (final row in rows) ...[
          LineDeparturesRow(row: row, now: now, onTap: () => context.push(Routes.line(row.line.id))),
          const Divider(height: 1),
        ],
      ],
    );
  }
}
