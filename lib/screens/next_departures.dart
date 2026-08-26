import 'dart:async';
import 'package:flutter/material.dart';
import 'package:website_app/models/call_unit.dart';
import 'package:website_app/models/stops_by_line_dto.dart';

import '../home_widgets/home_widget_service.dart';
import '../services/api_repository.dart';
import '../widgets/next_departures_card.dart';

class NextDeparturesScreen extends StatefulWidget {
  const NextDeparturesScreen(
      {super.key, required this.stop, required this.lineId});

  final IDFMStopArea stop;
  final String lineId;

  @override
  State<NextDeparturesScreen> createState() => _NextDeparturesScreenState();
}

class _NextDeparturesScreenState extends State<NextDeparturesScreen> {
  final api = ApiRepository();
  List<CallUnit> nextDepartures = [];
  List<String> nextDeparturesDestinations = [];
  bool isLoading = false;
  Timer? _autoRefreshTimer;
  Timer? _countdownTickTimer;
  String? _disruptionMessage;

  bool _autoRefreshEnabled = false;
  bool get isAutoRefreshing => _autoRefreshEnabled && nextDepartures.isNotEmpty;

  int _scrollYPosition = 0;
  late final ScrollController _scrollController;

  Future<void> fetchNextDepartures({bool showLoading = true}) async {
    if (showLoading) setState(() => isLoading = true);
    try {
      final response =
          await api.fetchNextDepartures(widget.stop.id!, widget.lineId);
      if (!mounted) return;

      setState(() {
        nextDepartures = response.nextPassages;
        nextDepartures.sort((a, b) {
          final aTime = a.expectedDepartureTime ?? a.expectedArrivalTime ?? '';
          final bTime = b.expectedDepartureTime ?? b.expectedArrivalTime ?? '';
          if (aTime.isEmpty || bTime.isEmpty) return 0;
          return DateTime.parse(aTime).isBefore(DateTime.parse(bTime)) ? -1 : 1;
        });
        nextDeparturesDestinations = response.nextPassageDestinations;
      });
      
      if (!_scrollController.hasClients || _scrollYPosition == 0) {
        HomeWidgetService.updateWidgetData(
          widget.lineId, widget.stop.id!, widget.stop.name ?? '', nextDepartures);
      }
    } catch (e) {
      if (mounted && showLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors du rafraîchissement'),
          behavior: SnackBarBehavior.floating,
        ),
      );
}
    } finally {
      if (mounted && showLoading) {
        setState(() => isLoading = false);
      }
    }
  }

  void _enableAutoRefresh() {
    setState(() => _autoRefreshEnabled = true);
    _startAutoRefresh();
  }

  void _disableAutoRefresh() {
    setState(() => _autoRefreshEnabled = false);
    _autoRefreshTimer?.cancel();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      fetchNextDepartures(showLoading: false);
    });
  }

  @override
  void initState() {
    super.initState();
    
    _scrollController = ScrollController();
    
    fetchNextDepartures();
    _countdownTickTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _countdownTickTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              widget.stop.name ?? 'Arrêt',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'En direct',
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          _buildRefreshToggle(),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? _buildSkeletonLoading()
          : nextDeparturesDestinations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.departure_board_outlined,
                          size: 48,
                          color: colorScheme.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun départ à venir',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: fetchNextDepartures,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Actualiser'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: fetchNextDepartures,
                  color: colorScheme.primary,
                  child: ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: nextDeparturesDestinations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final destination = nextDeparturesDestinations[index];
                      return NextDepartureCard(
                        destination: destination,
                        nextDepartures: List.from(nextDepartures
                            .where((d) => d.destinationName == destination)
                            .toList()),
                      );
                    },
                  ),
                ),
      floatingActionButton: _disruptionMessage != null
          ? FloatingActionButton.extended(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_disruptionMessage!),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.warning_rounded),
              label: const Text('Incident'),
            )
          : null,
    );
  }

  Widget _buildRefreshToggle() {
    final isSelected = isAutoRefreshing;
    
    return Checkbox(
      value: isSelected,
      onChanged: (value) {
        setState(() {
          _autoRefreshEnabled = value!;
        });
        
        if (value == true && nextDepartures.isEmpty) {
          _enableAutoRefresh();
        } else if (value == false) {
          _disableAutoRefresh();
        }
      },
    );
  }

  Widget _buildSkeletonLoading() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 3, // Nombre de placeholders
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Container(
          height: 80,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
        );
      },
    );
  }
}
