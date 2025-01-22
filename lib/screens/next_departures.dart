import 'package:flutter/material.dart';
import 'package:website_app/models/call_unit.dart';
import 'package:website_app/models/stops_by_line_dto.dart';

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


    try {
      final response =
          await api.fetchNextDepartures(widget.stop.id!, widget.lineId);
      nextDepartures = response.nextPassages;
      nextDepartures.sort((a, b) {
        return DateTime.parse(a.expectedDepartureTime ?? a.expectedArrivalTime!)
                .isBefore(DateTime.parse((b.expectedDepartureTime ?? b.expectedArrivalTime!)))
            ? -1
            : 1;
      });
      nextDeparturesDestinations = response.nextPassageDestinations;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching next departures: $e')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    setState(() {
      isLoading = true;
    });
    fetchNextDepartures();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.stop.name!),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: fetchNextDepartures,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ListView(
            children: [
              for (var destination in nextDeparturesDestinations)
                NextDepartureCard(
                  destination: destination,
                  nextDepartures: List.from(nextDepartures
                      .where((departure) =>
                  departure.destinationName == destination)
                      .toList()),
                ),
            ],
          ),
        ),
      ),
    );
  }

}
