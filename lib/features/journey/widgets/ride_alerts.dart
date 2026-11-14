import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/ui.dart';
import '../../../l10n/l10n.dart';
import '../../traffic/disruption_widgets.dart';
import '../../traffic/traffic_providers.dart';

/// What may go wrong on a ride of a journey: its line's disruptions, the line's at the two stops of the ride (a
/// station closed, a stop not served) and their elevators out of order. Information messages are left out.
class RideAlerts {
  const RideAlerts({this.line = const [], this.stops = const []});

  /// Disruptions of the line itself, worst first
  final List<Disruption> line;

  /// At the stops where the ride gets on and off
  final List<StopAlerts> stops;

  bool get isEmpty => line.isEmpty && stops.every((stop) => stop.isEmpty);

  /// The worst disruption's; null with elevator outages only
  DisruptionSeverity? get severity {
    final severities = {for (final disruption in [...line, for (final stop in stops) ...stop.disruptions]) disruption.severity};
    return DisruptionSeverity.values.reversed.where(severities.contains).firstOrNull;
  }

  int get elevatorCount => stops.fold(0, (count, stop) => count + stop.elevators.length);
}

/// A ride's alerts at one of its stops
class StopAlerts {
  const StopAlerts({required this.name, this.disruptions = const [], this.elevators = const []});

  final String name;

  /// The line's disruptions there
  final List<Disruption> disruptions;
  final List<Disruption> elevators;

  bool get isEmpty => disruptions.isEmpty && elevators.isEmpty;
}

/// [RideAlerts] of a ride on [lineId] from its line's disruptions (`/lines/{id}/disruptions`: the line's own, then
/// those of its stops) and those of the stops where it gets on and off (`/stops/{id}/disruptions`: every line's there,
/// its main lines' and its elevators). A stop's disruption counts when the line has it too: not another line's at the
/// same stop (the buses around Châtelet), nor the line's own once more.
RideAlerts rideAlerts({
  required String lineId,
  required List<Disruption> line,
  required List<({String name, List<Disruption> disruptions})> stops,
}) {
  bool matters(Disruption disruption) => disruption.active && disruption.severity != DisruptionSeverity.info;
  // The same text often comes as several disruptions (one per impact), each list keeping one of them
  (String?, String?) text(Disruption disruption) => (disruption.title, disruption.message);
  final own = [for (final disruption in line) if (matters(disruption) && disruption.lineIds.contains(lineId)) disruption];
  final atItsStops = {for (final disruption in line) if (!disruption.lineIds.contains(lineId)) text(disruption)};
  // Each said once: the line's own are already, one about both stops is at the first
  final said = {for (final disruption in own) text(disruption)};
  return RideAlerts(
    line: own,
    stops: [
      for (final stop in stops)
        StopAlerts(
          name: stop.name,
          disruptions: [
            for (final disruption in stop.disruptions)
              if (matters(disruption) &&
                  disruption.category != DisruptionCategory.elevator &&
                  atItsStops.contains(text(disruption)) &&
                  said.add(text(disruption)))
                disruption,
          ],
          elevators: [
            for (final disruption in stop.disruptions)
              if (disruption.active && disruption.category == DisruptionCategory.elevator) disruption,
          ],
        ),
    ],
  );
}

/// What a ride's [RideAlerts] say in one line: the worst disruption's title (`Travaux sur la ligne J`), else what it
/// is (`Trafic perturbé`), then its elevators out of order
String rideAlertsText(RideAlerts alerts) {
  final severity = alerts.severity;
  final worst = [...alerts.line, for (final stop in alerts.stops) ...stop.disruptions]
      .where((disruption) => disruption.severity == severity)
      .firstOrNull;
  final title = worst?.title?.trim();
  final elevators = alerts.elevatorCount;
  return [
    if (title != null && title.isNotEmpty) title else if (severity != null) severityLabel(severity),
    if (elevators > 0) currentL10n.brokenElevators(elevators),
  ].join(' · ');
}

/// A ride's [RideAlerts] under its line's row in the journey detail, written in clear: what goes wrong in the color of
/// the worst of them (red interrupted, orange disrupted or elevators out of order), on a tint of it; a tap shows them
/// in a sheet. Nothing when all is well.
class RideAlertsLine extends ConsumerWidget {
  const RideAlertsLine({super.key, required this.section, this.padding = EdgeInsets.zero});

  final JourneySection section;

  /// Around the line, when there is one
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = section.line;
    if (line == null || line.id.isEmpty) {
      return const SizedBox.shrink();
    }
    final alerts = rideAlerts(
      lineId: line.id,
      line: ref.watch(lineDisruptionsProvider(line.id)).value ?? const [],
      stops: [
        for (final point in [section.from, section.to])
          if (point?.stopAreaId case final stopAreaId?)
            (name: point!.name, disruptions: ref.watch(stopDisruptionsProvider(stopAreaId)).value ?? const <Disruption>[]),
      ],
    );
    if (alerts.isEmpty) {
      return const SizedBox.shrink();
    }
    final severity = alerts.severity;
    final color = severity == null ? context.colors.warning : severityColor(severity, Theme.of(context).colorScheme);
    return Padding(
      padding: padding,
      child: Semantics(
        button: true,
        label: context.l10n.rideAlertsOf(rideAlertsText(alerts)),
        excludeSemantics: true,
        child: Material(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showRideAlertsSheet(context, section: section, alerts: alerts),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(
                children: [
                  Icon(severity == null ? Icons.elevator_outlined : severityIcon(severity), size: 17, color: color),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      rideAlertsText(alerts),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ride's alerts in a sheet, their messages unfolded: the line's disruptions, then each stop's with its elevators
/// out of order
Future<void> showRideAlertsSheet(BuildContext context, {required JourneySection section, required RideAlerts alerts}) {
  return showModalBottomSheet<void>(
    context: context,
    // Above the whole app, not inside the panel or the bottom sheet
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(context.l10n.rideAlerts, style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            Row(
              children: [
                if (section.line case final line?) ...[LineBadge(line, size: 26), const SizedBox(width: 8)],
                Expanded(
                  child: Text(
                    context.l10n.direction(section.headsign ?? ''),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DisruptionList(disruptions: alerts.line, expanded: true),
            for (final stop in alerts.stops)
              if (!stop.isEmpty) ...[
                SectionTitle(context.l10n.atStop(stop.name), padding: const EdgeInsets.fromLTRB(4, 8, 4, 8)),
                DisruptionList(disruptions: [...stop.disruptions, ...stop.elevators], expanded: true),
              ],
          ],
        ),
      );
    },
  );
}
