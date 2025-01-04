import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../models/call_unit.dart';
import '../models/line_dto.dart';
import '../services/api_repository.dart';
import '../widgets/line_list.dart';

class LinesScreen extends StatefulWidget {
  const LinesScreen({super.key});

  @override
  State<LinesScreen> createState() => _LinesScreenState();
}

class _LinesScreenState extends State<LinesScreen> {
  List<String> transportModes = [
    "BUS",
    "NOCTILIEN",
    "METRO",
    "TRAM",
    "TER",
    "TRANSILIEN",
    "RER"
  ];
  List<LineDTO> lines = [];
  Map<String, int> transportModeCount = {};
  bool isLoadingDepartures = false;
  final api = ApiRepository();

  @override
  void initState() {
    super.initState();
    fetchLines();
  }

  Future<void> fetchLines() async {
    final response = await api.fetchLines();

    lines = response.lines;
    transportModeCount = response.count;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: transportModes.length,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text('Lines & stops'),
          bottom: TabBar(
            tabAlignment: TabAlignment.start,
            isScrollable: true,
            tabs: List.generate(transportModes.length, (index) {
              return Tab(
                child: Text(transportModes[index]),
              );
            }),
          ),
        ),
        body: TabBarView(
          children: transportModes.map((String mode) {
            return Center(
              child: LineList(
                selectedMode: mode,
                lines: lines,
                onLineSelected: (line) {
                  fetchStopsAndShape(line.id!,
                      lineIdBackgroundColor: line.lineIdBackgroundColor!);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> fetchStopsAndShape(String lineId,
      {required String lineIdBackgroundColor}) async {
    final response = await api.fetchStopsAndShape(lineId);
    final lineColor =
        Color(int.parse("FF${lineIdBackgroundColor.toUpperCase()}", radix: 16));

    // handle stops
  }

  void _onMarkerTap(String stopId, String lineName, String lineId) async {
    setState(() {
      isLoadingDepartures = true;
    });

    try {
      final nextDepartures = await api.fetchNextDepartures(stopId, lineId);

      if (nextDepartures.nextPassages != null &&
          nextDepartures.nextPassages!.isNotEmpty) {
        final groupedDepartures = <String, List<CallUnit>>{};

        for (var passage in nextDepartures.nextPassages!) {
          final destination = passage.destinationName ?? 'Unknown Destination';
          groupedDepartures.putIfAbsent(destination, () => []).add(passage);
        }

        _showNextDeparturesDialog(lineName, groupedDepartures);
      } else {
        _showNoDeparturesDialog();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching departures: $e')),
      );
    } finally {
      setState(() {
        isLoadingDepartures = false;
      });
    }
  }

  void _showNextDeparturesDialog(
      String lineName, Map<String, List<CallUnit>> groupedDepartures) {
    showDialog(
      context: AppSettings.navigatorState.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(lineName),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: groupedDepartures.entries.map((entry) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16.0,
                      ),
                    ),
                    ...entry.value.map((callUnit) {
                      return ListTile(
                        title: Text(
                          'Departure: ${_formatTimeRelativeToNow(callUnit.expectedDepartureTime)}',
                        ),
                        subtitle: callUnit.arrivalPlatformName != null
                            ? Text(
                                'Platform: ${callUnit.arrivalPlatformName}',
                              )
                            : null,
                        trailing: Text(
                          callUnit.departureStatus ?? '',
                          style: const TextStyle(color: Colors.green),
                        ),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showNoDeparturesDialog() {
    showDialog(
      context: AppSettings.navigatorState.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Next Departures'),
          content: const Text('No departures available.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _formatTimeRelativeToNow(String? timestamp) {
    if (timestamp == null) return 'N/A';

    final departureTime = DateTime.tryParse(timestamp);
    if (departureTime == null) return 'N/A';

    final now = DateTime.now();
    final difference = departureTime.difference(now);

    if (difference.inMinutes < 1) {
      return 'Now';
    } else if (difference.inMinutes < 60) {
      return 'in ${difference.inMinutes} min';
    } else {
      return 'in ${difference.inHours} h ${difference.inMinutes % 60} min';
    }
  }
}
