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
  bool _hasError = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
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
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> fetchLines() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final response = await api.fetchLines();
      if (mounted) {
        setState(() {
          lines = response.lines;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lignes & arrêts'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Rechercher une ligne...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      fillColor: colorScheme.surfaceContainerHighest,
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              TabBar(
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
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 48, color: colorScheme.error),
                      const SizedBox(height: 12),
                      Text(
                        'Erreur de chargement des lignes',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: fetchLines,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: fetchLines,
                  color: colorScheme.primary,
                  child: TabBarView(
                    controller: _tabController,
                    children: transportModes.map((String mode) {
                      return LineList(
                        selectedMode: mode,
                        searchQuery: _searchQuery,
                        lines: lines,
                        onLineSelected: (line) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => StopsScreen(line: line),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
                ),
    );
  }
}
