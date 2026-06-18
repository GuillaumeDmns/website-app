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

  Future<void> fetchNextDepartures() async {
    setState(() => isLoading = true);
    try {
      final response =
          await api.fetchNextDepartures(widget.stop.id!, widget.lineId);
      setState(() {
        nextDepartures = response.nextPassages;
        nextDepartures.sort((a, b) {
          return DateTime.parse(
                      a.expectedDepartureTime ?? a.expectedArrivalTime!)
                  .isBefore(DateTime.parse(
                      (b.expectedDepartureTime ?? b.expectedArrivalTime!)))
              ? -1
              : 1;
        });
        nextDeparturesDestinations = response.nextPassageDestinations;
      });
      HomeWidgetService.updateWidgetData(
          widget.lineId, widget.stop.id!, widget.stop.name!, nextDepartures);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    fetchNextDepartures();
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
              widget.stop.name!,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              'Prochains départs',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.55),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
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
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: fetchNextDepartures,
                  color: colorScheme.primary,
                  child: ListView.separated(
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
    );
  }
}
