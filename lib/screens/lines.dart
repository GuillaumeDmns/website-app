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

class _LinesScreenState extends State<LinesScreen> with SingleTickerProviderStateMixin {
  final List<String> transportModes = [
    "METRO",
    "RER",
    "TRANSILIEN",
    "TRAM",
    "BUS",
    "NOCTILIEN",
    "TER",
  ];

  final Map<String, String> _modeLabels = {
    "METRO": "Métro",
    "RER": "RER",
    "TRANSILIEN": "Transilien",
    "TRAM": "Tramway",
    "BUS": "Bus",
    "NOCTILIEN": "Noctilien",
    "TER": "TER",
  };

  List<LineDTO> lines = [];
  bool _isLoading = true;
  final api = ApiRepository();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: transportModes.length, vsync: this);
    fetchLines();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> fetchLines() async {
    try {
      final response = await api.fetchLines();
      setState(() {
        lines = response.lines;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lignes & arrêts'),
        bottom: TabBar(
          controller: _tabController,
          tabAlignment: TabAlignment.start,
          isScrollable: true,
          dividerColor: colorScheme.outlineVariant,
          indicatorColor: colorScheme.primary,
          indicatorWeight: 3,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurface.withValues(alpha: 0.55),
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          tabs: transportModes
              .map((mode) => Tab(text: _modeLabels[mode] ?? mode))
              .toList(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: transportModes.map((String mode) {
                return LineList(
                  selectedMode: mode,
                  lines: lines,
                  onLineSelected: (line) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => StopsScreen(line: line)),
                    );
                  },
                );
              }).toList(),
            ),
    );
  }
}
