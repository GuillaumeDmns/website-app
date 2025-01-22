import 'package:flutter/material.dart';
import 'package:website_app/screens/stops.dart';

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
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => StopsScreen(line: line)),
                  );
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
