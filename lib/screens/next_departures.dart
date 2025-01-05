import 'package:flutter/material.dart';
import 'package:website_app/models/call_unit.dart';
import 'package:website_app/models/stops_by_line_dto.dart';
import 'package:website_app/utils/time_utils.dart';

import '../services/api_repository.dart';

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
    setState(() {
      isLoading = true;
    });

    try {
      final response =
          await api.fetchNextDepartures(widget.stop.id!, widget.lineId);
      nextDepartures = response.nextPassages;
      nextDepartures.sort((a, b) {
        return DateTime.parse(a.expectedDepartureTime!)
                .isBefore(DateTime.parse((b.expectedDepartureTime!)))
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
          : ListView(
              padding: const EdgeInsets.all(8.0),
              children: [
                for (var destination in nextDeparturesDestinations)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(destination),
                          const SizedBox(height: 8.0),
                          ...nextDepartures
                              .where((departure) =>
                                  departure.destinationName == destination)
                              .map(
                                (departure) => Column(
                                  children: [
                                    ListTile(
                                      leading: Text(
                                        TimeUtils.getTimeFromIso8601(
                                            departure.expectedDepartureTime),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      title:
                                          Text(departure.destinationName ?? ''),
                                      subtitle: Text(
                                        departure.arrivalPlatformName != null
                                            ? "Platform ${departure.arrivalPlatformName}"
                                            : '',
                                      ),
                                    ),
                                    if (departure !=
                                        nextDepartures.lastWhere((d) =>
                                            d.destinationName == destination))
                                      const Divider(height: 0),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
