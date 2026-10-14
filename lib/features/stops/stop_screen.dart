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
import '../../core/platform/share.dart';
import '../../core/utils/refresh.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/line_badge.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/l10n.dart';
import '../favorites/favorite_widgets.dart';
import '../journey/journey_preferences.dart';
import '../journey/journey_request.dart';
import '../service_hours/service_hours.dart';
import '../traffic/disruption_widgets.dart';
import '../traffic/traffic_providers.dart';
import 'widgets/stop_departures_card.dart';

final stopAreaProvider = FutureProvider.autoDispose.family<StopAreaDetail, String>(
  (ref, stopAreaId) => ref.watch(mobilityApiProvider).stopArea(stopAreaId),
);

/// Departures of a stop area, refreshed every 30 s while shown
final stopDeparturesProvider = FutureProvider.autoDispose.family<StopDepartures, String>((ref, stopAreaId) async {
  ref.refreshEvery(const Duration(seconds: 30));
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
    void goThere() => context.push(
      Routes.journey(
        ref
            .read(journeyPreferencesProvider)
            .apply(
              JourneyRequest(
                from: const JourneyPlace.currentLocation(),
                to: JourneyPlace.stopArea(name: detail.name, id: detail.id, lat: detail.lat, lon: detail.lon),
              ),
            ),
      ),
    );

    return RefreshIndicator(
      onRefresh: () => ref.refresh(stopDeparturesProvider(detail.id).future),
      child: ListView(
        controller: PanelScrollScope.of(context),
        padding: const EdgeInsets.fromLTRB(4, 0, 16, 32),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: context.l10n.back,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(detail.name, style: theme.textTheme.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              FavoriteStopButton(
                stop: StopAreaSummary(id: detail.id, name: detail.name, lat: detail.lat, lon: detail.lon, lines: detail.lines),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 0, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final line in detail.lines)
                  InkWell(onTap: () => context.push(Routes.line(line.id)), child: LineBadge(line, size: 28)),
                if (detail.wheelchairBoarding == 1)
                  Tooltip(
                    message: context.l10n.wheelchairAccessible,
                    child: IconBubble(Icons.accessible, color: theme.colorScheme.secondary, size: 28),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 0, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(child: RoundAction(icon: Icons.directions, label: context.l10n.goThere, primary: true, onPressed: goThere)),
                if (detail.lines.isNotEmpty)
                  Expanded(
                    child: RoundAction(
                      icon: Icons.schedule,
                      label: context.l10n.timetableShort,
                      onPressed: () => context.push(Routes.timetable(detail.id)),
                    ),
                  ),
                Expanded(
                  child: RoundAction(
                    icon: Icons.ios_share,
                    label: context.l10n.share,
                    onPressed: () => shareLink(context, title: detail.name, location: Routes.stop(detail.id)),
                  ),
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
                SectionTitle(context.l10n.nextDepartures),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: AsyncView(
                    value: departures,
                    onRetry: () => ref.invalidate(stopDeparturesProvider(detail.id)),
                    data: (departures) => _DepartureList(departures: departures, now: now),
                  ),
                ),
                StopServiceHoursSection(stopAreaId: detail.id),
                if (detail.connections.isNotEmpty) ...[
                  SectionTitle(context.l10n.walkingConnections),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (index, connection) in detail.connections.indexed) ...[
                          if (index > 0) const Divider(indent: 56),
                          ListTile(
                            leading: const IconBubble(Icons.directions_walk, size: 32),
                            title: Text(connection.name),
                            trailing: connection.minTransferSeconds == null
                                ? const Icon(Icons.chevron_right)
                                : Text(
                                    context.l10n.minutesShort((connection.minTransferSeconds! / 60).ceil()),
                                    style: theme.textTheme.bodySmall,
                                  ),
                            onTap: () => context.push(Routes.stop(connection.id)),
                          ),
                        ],
                      ],
                    ),
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
      padding: const EdgeInsets.only(top: 16),
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
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: NoticeLine(icon: Icons.schedule, text: context.l10n.realtimeUnavailable),
          ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(context.l10n.noDepartureTwoHours, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) const Divider(indent: 40),
          LineDeparturesRow(row: row, now: now, onTap: () => context.push(Routes.line(row.line.id))),
        ],
      ],
    );
  }
}
