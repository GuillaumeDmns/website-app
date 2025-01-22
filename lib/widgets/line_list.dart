import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:website_app/widgets/line_icon.dart';

import '../models/line_dto.dart';

class LineList extends StatelessWidget {
  final String? selectedMode;
  final List<LineDTO> lines;
  final ValueChanged<LineDTO> onLineSelected;

  const LineList({
    super.key,
    required this.selectedMode,
    required this.lines,
    required this.onLineSelected,
  });

  @override
  Widget build(BuildContext context) {
    final filteredLines = lines.where((line) => line.transportMode == selectedMode).toList();

    filteredLines.sort((a, b) => compareNatural(a.name ?? '', b.name ?? ''));

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 10.0,
        mainAxisSpacing: 10.0,
      ),
      itemCount: filteredLines.length,
      itemBuilder: (BuildContext context, int index) {
        final line = filteredLines[index];

        return GestureDetector(
          onTap: () => onLineSelected(line),
          child: Center(
            child: LineIcon(line: line)
          ),
        );
      },
    );
  }
}
