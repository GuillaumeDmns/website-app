import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:website_app/widgets/line_icon.dart';

import '../models/line_dto.dart';

class LineList extends StatelessWidget {
  final String? selectedMode;
  final String searchQuery;
  final List<LineDTO> lines;
  final ValueChanged<LineDTO> onLineSelected;

  const LineList({
    super.key,
    required this.selectedMode,
    this.searchQuery = '',
    required this.lines,
    required this.onLineSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = searchQuery.trim().toLowerCase();

    final filteredLines = lines.where((line) {
      final matchesMode = line.transportMode == selectedMode;
      if (!matchesMode) return false;
      if (query.isEmpty) return true;
      final lineName = (line.name ?? '').toLowerCase();
      final lineId = (line.id ?? '').toLowerCase();
      return lineName.contains(query) || lineId.contains(query);
    }).toList();

    filteredLines.sort((a, b) => compareNatural(a.name ?? '', b.name ?? ''));

    if (filteredLines.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_outlined,
                size: 48, color: colorScheme.onSurface.withValues(alpha: 0.25)),
            const SizedBox(height: 12),
            Text(
              query.isNotEmpty ? 'Aucune ligne trouvée pour "$searchQuery"' : 'Aucune ligne',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 12.0,
        mainAxisSpacing: 12.0,
      ),
      itemCount: filteredLines.length,
      itemBuilder: (BuildContext context, int index) {
        final line = filteredLines[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onLineSelected(line),
          child: Center(
            child: LineIcon(line: line),
          ),
        );
      },
    );
  }
}
