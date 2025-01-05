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
      body: Column(
        children: [
          if (isLoading) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: [
                for (var departure in nextDepartures) ...[
                  ListTile(
                    leading: Text(TimeUtils.getTimeFromIso8601(
                        departure.expectedDepartureTime)),
                    title: Text(departure.destinationName ?? ''),
                    subtitle: Text(departure.arrivalPlatformName ?? ''),
                  ),
                  if (departure != nextDepartures.last) Divider(height: 0),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
