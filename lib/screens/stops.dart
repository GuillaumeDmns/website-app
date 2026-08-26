import 'package:flutter/material.dart';
import 'package:website_app/models/stops_by_line_dto.dart';
import 'package:website_app/screens/next_departures.dart';
import 'package:website_app/widgets/line_icon.dart';

import '../models/line_dto.dart';
import '../services/api_repository.dart';

class StopsScreen extends StatefulWidget {
  const StopsScreen({super.key, required this.line});

  final LineDTO line;

  @override
  State<StopsScreen> createState() => _StopsScreenState();
}

class _StopsScreenState extends State<StopsScreen> {
  final api = ApiRepository();
  List<IDFMStopArea> stops = [];
  bool isLoading = false;
  String searchQuery = '';
  final _searchController = TextEditingController();

  Future<void> fetchStops() async {
    setState(() => isLoading = true);
    try {
      final response = await api.fetchStopsAndShape(widget.line.id!);
      if (mounted) {
        setState(() => stops = response.stops);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    fetchStops();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final filteredStops = stops.where((stop) {
      if (searchQuery.trim().isEmpty) return true;
      final name = (stop.name ?? '').toLowerCase();
      return name.contains(searchQuery.trim().toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LineIcon(line: widget.line),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                widget.line.name ?? '',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Rechercher un arrêt...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  fillColor: colorScheme.surfaceContainerHighest,
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => searchQuery = '');
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),
          if (isLoading) LinearProgressIndicator(color: colorScheme.primary),
          Expanded(
            child: filteredStops.isEmpty && !isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_off_outlined,
                            size: 44,
                            color: colorScheme.onSurface.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(
                          searchQuery.isNotEmpty
                              ? 'Aucun arrêt trouvé pour "$searchQuery"'
                              : 'Aucun arrêt trouvé',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: fetchStops,
                    color: colorScheme.primary,
                    child: ListView.separated(
                      itemCount: filteredStops.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 70,
                        color: colorScheme.outlineVariant,
                      ),
                      itemBuilder: (context, index) {
                        final stop = filteredStops[index];
                        final stopName = stop.name ?? 'Arrêt inconnu';
                        final initial = stopName.isNotEmpty
                            ? stopName[0].toUpperCase()
                            : '?';

                        return ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                initial,
                                style: textTheme.titleSmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            stopName,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                          onTap: () {
                            if (widget.line.id != null && stop.id != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => NextDeparturesScreen(
                                    lineId: widget.line.id!,
                                    stop: stop,
                                  ),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
