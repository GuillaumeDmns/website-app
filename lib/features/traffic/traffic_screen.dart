import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/shell.dart';
import '../../core/api/models.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/line_badge.dart';
import 'disruption_widgets.dart';
import 'traffic_providers.dart';

/// Traffic state: a grid of badges per main mode (colored dot when disrupted), the disrupted lines with their
/// disruption titles, then the disrupted bus lines.
class TrafficScreen extends ConsumerWidget {
  const TrafficScreen({super.key});

  static const _mainModes = [TransportMode.metro, TransportMode.rer, TransportMode.transilien, TransportMode.tram];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traffic = ref.watch(trafficProvider);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(trafficProvider.future),
      child: ListView(
        controller: PanelScrollScope.of(context),
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
              ),
              Expanded(child: Text('Info trafic', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: AsyncView(
              value: traffic,
              onRetry: () => ref.invalidate(trafficProvider),
              data: (lines) {
                final disrupted = lines.where((line) => line.severity != null && line.severity != DisruptionSeverity.info).toList();
                final main = disrupted.where((line) => _mainModes.contains(line.line.mode)).toList();
                final others = disrupted.where((line) => !_mainModes.contains(line.line.mode)).toList();
                final informations = lines.where((line) => line.severity == DisruptionSeverity.info).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final mode in _mainModes)
                      if (lines.where((line) => line.line.mode == mode).toList() case final modeLines when modeLines.isNotEmpty)
                        _ModeGrid(mode: mode, lines: modeLines),
                    const SizedBox(height: 8),
                    if (main.isEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(severityIcon(null), color: severityColor(null, theme.colorScheme)),
                        title: const Text('Trafic normal sur les métros, RER, trains et trams'),
                      ),
                    for (final line in main) _LineTrafficTile(traffic: line),
                    if (others.isNotEmpty)
                      Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text('${others.length} lignes de bus perturbées',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          children: [for (final line in others) _LineTrafficTile(traffic: line)],
                        ),
                      ),
                    if (informations.isNotEmpty)
                      Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text('${informations.length} ligne${informations.length > 1 ? 's' : ''} avec une information',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          children: [for (final line in informations) _LineTrafficTile(traffic: line)],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeGrid extends StatelessWidget {
  const _ModeGrid({required this.mode, required this.lines});

  final TransportMode mode;
  final List<LineTraffic> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mode.label, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final line in lines)
                Tooltip(
                  message: '${line.line.mode.label} ${line.line.name ?? ''} : ${severityLabel(line.severity).toLowerCase()}',
                  child: InkWell(
                    onTap: () => context.push(Routes.line(line.line.id)),
                    child: WithSeverity(severity: line.severity, child: LineBadge(line.line, size: 32)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineTrafficTile extends StatelessWidget {
  const _LineTrafficTile({required this.traffic});

  final LineTraffic traffic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = severityColor(traffic.severity, theme.colorScheme);
    return InkWell(
      onTap: () => context.push(Routes.line(traffic.line.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LineBadge(traffic.line, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(severityIcon(traffic.severity), size: 16, color: color),
                      const SizedBox(width: 4),
                      Text(severityLabel(traffic.severity), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  for (final title in traffic.titles.take(3))
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

/// Home page entry: worst state of the main lines in one line, opens the traffic page
class TrafficSummaryCard extends ConsumerWidget {
  const TrafficSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traffic = ref.watch(trafficProvider).value;
    final theme = Theme.of(context);
    final disrupted = (traffic ?? const <LineTraffic>[])
        .where((line) =>
            TrafficScreen._mainModes.contains(line.line.mode) &&
            (line.severity == DisruptionSeverity.disrupted || line.severity == DisruptionSeverity.blocking))
        .toList();
    final worst = disrupted.any((line) => line.severity == DisruptionSeverity.blocking)
        ? DisruptionSeverity.blocking
        : disrupted.isEmpty
            ? null
            : DisruptionSeverity.disrupted;
    final color = severityColor(worst, theme.colorScheme);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.traffic),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Icon(traffic == null ? Icons.traffic_outlined : severityIcon(worst), color: traffic == null ? null : color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Info trafic', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      traffic == null
                          ? 'Métros, RER, trains et trams'
                          : disrupted.isEmpty
                              ? 'Trafic normal sur les lignes principales'
                              : '${disrupted.length} ligne${disrupted.length > 1 ? 's' : ''} perturbée${disrupted.length > 1 ? 's' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              for (final line in disrupted.take(5))
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: WithSeverity(severity: line.severity, dotSize: 11, child: LineBadge(line.line, size: 24)),
                ),
              if (disrupted.length > 5)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text('+${disrupted.length - 5}', style: theme.textTheme.bodySmall),
                ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
