import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../core/api/api_providers.dart';
import '../../core/api/models.dart';
import '../../core/location/location_providers.dart';
import '../../core/map/map_overlay.dart';
import '../../core/platform/share.dart';
import '../../core/utils/refresh.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/line_badge.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/l10n.dart';
import '../favorites/favorite_widgets.dart';
import '../follow/follow_widgets.dart';
import '../home/map_stops.dart';
import '../lines/line_vehicles.dart';
import '../journey/journey_preferences.dart';
import '../journey/journey_request.dart';
import '../service_hours/service_hours.dart';
import '../traffic/disruption_widgets.dart';
import '../traffic/traffic_providers.dart';
import 'widgets/stop_departures_card.dart';

final stopAreaProvider = FutureProvider.autoDispose.family<StopAreaDetail, String>(
  (ref, stopAreaId) => ref.mobilityApi.stopArea(stopAreaId),
);

/// Departures of a stop area, refreshed every 30 s while shown
/// Departures asked per line and destination (the API's most): enough for a station's board of its trains
const stopDeparturesLimit = 5;

final stopDeparturesProvider = FutureProvider.autoDispose.family<StopDepartures, String>((ref, stopAreaId) async {
  ref.refreshEvery(const Duration(seconds: 30));
  return ref.mobilityApi.stopDepartures(stopAreaId, limit: stopDeparturesLimit);
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
                // The same marker as on the page it was opened from, with its lines, and the stops around it: the map
                // doesn't change as a stop opens
                ...stopPins(
                  context,
                  [
                    ...ref.watch(mapStopsProvider).value ?? const <StopAreaSummary>[],
                    StopAreaSummary(id: detail.id, name: detail.name, lat: detail.lat, lon: detail.lon, lines: detail.lines),
                  ],
                  severities: ref.watch(lineSeveritiesProvider),
                  opened: detail.id,
                ),
              ],
              fit: [LatLng(detail.lat, detail.lon)],
            ),
      child: AsyncView(
        value: stop,
        onRetry: () => ref.invalidate(stopAreaProvider(stopAreaId)),
        page: true,
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
    final closedLines = ref.watch(stopClosedLinesProvider(detail.id)).value ?? const <String>{};
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
                for (final line in detail.lines.where((line) => !line.replacement))
                  InkWell(
                    onTap: () => context.push(Routes.line(line.id)),
                    child: closedLines.contains(line.id)
                        // Not stopping here now: faded, crossed
                        ? Tooltip(
                            message: context.l10n.notServed,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Opacity(opacity: 0.35, child: LineBadge(line, size: 28)),
                                Positioned(
                                  right: -4,
                                  top: -4,
                                  child: Icon(Icons.block, size: 16, color: theme.colorScheme.error),
                                ),
                              ],
                            ),
                          )
                        : LineBadge(line, size: 28),
                  ),
                if (detail.wheelchairBoarding == 1)
                  Tooltip(
                    message: context.l10n.wheelchairAccessible,
                    child: IconBubble(Icons.accessible, color: theme.colorScheme.secondary, size: 28),
                  ),
              ],
            ),
          ),
          // Buses replacing a train or RER while it doesn't run: they stop here only then, apart from the lines that
          // always do (their badges, `A` and `L`, read as the trains')
          if (detail.lines.any((line) => line.replacement))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(context.l10n.stopReplacementLines, style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
                  for (final line in detail.lines.where((line) => line.replacement))
                    InkWell(
                      onTap: () => context.push(Routes.line(line.id)),
                      child: Tooltip(message: line.label, child: LineBadge(line, size: 22)),
                    ),
                ],
              ),
            ),
          if (closedLines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
              child: NoticeLine(
                icon: Icons.block,
                text: context.l10n.notServedLines(
                  detail.lines.where((line) => closedLines.contains(line.id)).map((line) => line.label).join(', '),
                ),
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
                SectionTitle(context.l10n.nextDepartures, trailing: UpdatedAgo(value: departures)),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: AsyncView(
                    value: departures,
                    loading: const SkeletonCards(count: 3, height: 52),
                    onRetry: () => ref.invalidate(stopDeparturesProvider(detail.id)),
                    data: (departures) => _DepartureList(departures: departures, now: now, stop: detail),
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

class _DepartureList extends ConsumerWidget {
  const _DepartureList({required this.departures, required this.now, required this.stop});

  final StopDepartures departures;
  final DateTime now;
  final StopAreaDetail stop;

  /// At most this many lines have their vehicles asked, to say where the next one is (one request a minute each where
  /// the backend has no snapshot of the whole network)
  static const _approachLines = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A long press on a departure offers to follow it
    final summary = StopAreaSummary(id: stop.id, name: stop.name, lat: stop.lat, lon: stop.lon, lines: stop.lines);
    VoidCallback? follow(LineDepartures row, String destination, Departure? departure) =>
        followDepartureAction(context, ref, stop: summary, line: row.line, destination: destination, departure: departure);
    final rows = departures.lines.where((line) => line.departures.isNotEmpty).toList();
    final theme = Theme.of(context);
    // Where the vehicles of the lines on the road (bus, tram) are, for their next departure
    final watched = {
      for (final row in rows)
        if (!row.line.mode.isRail && departures.realtimeAvailable) row.line.id,
    }.take(_approachLines);
    final vehicles = {
      for (final id in watched) id: ref.watch(lineVehiclesProvider(id)).value?.vehicles ?? const <Vehicle>[],
    };
    // Each line's frequency now, over its line's departures
    final hours = ref.watch(stopServiceHoursProvider(stop.id)).value;
    String? frequencyOf(LineSummary line) {
      for (final lineHours in hours?.lines ?? const <LineServiceHours>[]) {
        if (lineHours.line.id != line.id) {
          continue;
        }
        for (final direction in lineHours.directions) {
          if (direction.frequencyAt(now) case final frequency?) {
            return frequencyLabel(frequency);
          }
        }
      }
      return null;
    }

    Widget departureRow(LineDepartures row, {bool showBadge = true}) => LineDeparturesRow(
          row: row,
          now: now,
          realtimeAvailable: departures.realtimeAvailable,
          showBadge: showBadge,
          approach: switch (row.departures.firstOrNull) {
            final first? => vehicleApproach(first, stop.id, vehicles[row.line.id] ?? const []),
            null => null,
          },
          onTap: () => context.push(Routes.line(row.line.id)),
          onLongPress: follow(row, row.destination, row.departures.firstOrNull),
        );

    final groups = _groups(rows);
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
        for (final (index, group) in groups.indexed) ...[
          if (index > 0) const Divider(height: 1),
          if (group.first.line.mode.isRail)
            for (final (index, train) in trainBoard(group, perDestination: stopDeparturesLimit).take(_trainsShown).indexed) ...[
              if (index > 0) const Divider(indent: 48),
              TrainDepartureRow(
                line: group.first.line,
                departure: train.departure,
                destination: train.destination,
                now: now,
                onTap: () => context.push(Routes.line(group.first.line.id)),
                onLongPress: follow(group.first, train.destination, train.departure),
              ),
            ]
          else if (group.length == 1)
            departureRow(group.single)
          else ...[
            // Its badge and frequency once, its destinations under them
            _LineHeader(
              line: group.first.line,
              frequency: frequencyOf(group.first.line),
              onTap: () => context.push(Routes.line(group.first.line.id)),
            ),
            for (final (index, row) in group.indexed) ...[
              if (index > 0) const Divider(indent: 48),
              departureRow(row, showBadge: false),
            ],
          ],
        ],
      ],
    );
  }

  /// The rows of each line together, lines in their order
  static List<List<LineDepartures>> _groups(List<LineDepartures> rows) {
    final lines = <String, List<LineDepartures>>{};
    for (final row in rows) {
      lines.putIfAbsent(row.line.id, () => []).add(row);
    }
    return lines.values.toList();
  }

  /// At most, per train line: the timetable has the others
  static const _trainsShown = 10;
}

/// Where the vehicle of [departure] from [stopId] is, among [vehicles] of its line: `en approche` when its next stop
/// is this one, `à 2 arrêts d'ici` further; null when standing there already (the departure says it) or not found (the
/// vehicle expected at the stop within 90 s of the departure)
String? vehicleApproach(Departure departure, String stopId, List<Vehicle> vehicles) {
  if (departure.atStop ?? false) {
    return null;
  }
  for (final vehicle in vehicles) {
    final index = vehicle.calls.indexWhere(
      (call) => call.stopId == stopId && call.expectedAt.difference(departure.time).inSeconds.abs() <= 90,
    );
    if (index >= 0) {
      return index == 0 ? currentL10n.departureVehicleApproaching : currentL10n.departureVehicleAway(index);
    }
  }
  return null;
}

/// A line's badge over its departures, with how often it runs now (`toutes les 12–15 min`)
class _LineHeader extends StatelessWidget {
  const _LineHeader({required this.line, required this.frequency, required this.onTap});

  final LineSummary line;
  final String? frequency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              LineBadge(line, size: 28),
              const SizedBox(width: 12),
              if (frequency case final frequency?)
                Expanded(
                  child: Text(
                    frequency,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.muted),
                  ),
                ),
            ],
          ),
        ),
      );
}
