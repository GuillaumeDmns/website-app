import 'package:flutter/material.dart';
import 'package:collection/collection.dart';

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
        final isUnselected = false; // Update this logic as needed based on your app state.

        return GestureDetector(
          onTap: () => onLineSelected(line),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 40,
                maxHeight: 40,
              ),
              decoration: BoxDecoration(
                color: getLineBackgroundColor(line),
                borderRadius: getLineBorderRadius(line),
                border: getLineBorder(line),
              ),
              padding: getLinePadding(line),
              alignment: Alignment.center,
              child: Opacity(
                opacity: isUnselected ? 0.5 : 1.0,
                child: Text(
                  line.name ?? '',
                  style: TextStyle(
                    color: getLineTextColor(line),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }


  Color getLineBackgroundColor(LineDTO line) {
    switch (line.transportMode) {
      case "TRAM":
        return Colors.white;
      case "BUS":
      case "NOCTILIEN":
      case "RER":
      case "METRO":
      case "TER":
      default:
        return Color(int.parse("0xFF${line.lineIdBackgroundColor}"));
    }
  }

  Color getLineTextColor(LineDTO line) {
    switch (line.transportMode) {
      case "TRAM":
        return Colors.black;
      case "BUS":
      case "NOCTILIEN":
      case "RER":
      case "METRO":
      case "TER":
      default:
        return Color(int.parse("0xFF${line.lineIdColor}"));
    }
  }

  BorderRadius getLineBorderRadius(LineDTO line) {
    switch (line.transportMode) {
      case "METRO":
        return BorderRadius.circular(20.0);
      case "RER":
      case "TRANSILIEN":
        return BorderRadius.circular(10.0);
      case "BUS":
      case "NOCTILIEN":
      case "TRAM":
      case "TER":
      default:
        return BorderRadius.zero;
    }
  }

  Border getLineBorder(LineDTO line) {
    switch (line.transportMode) {
      case "TRAM":
        BorderSide borderSide = BorderSide(width: 5, color: Color(int.parse('0xFF${line.lineIdBackgroundColor}')));
        return Border(
          top: borderSide,
          bottom: borderSide,
        );
      case "METRO":
      case "BUS":
      case "NOCTILIEN":
      case "RER":
      case "TER":
      default:
        return Border.all(color: Colors.transparent, width: 0.0);
    }
  }

  EdgeInsets getLinePadding(LineDTO line) {
    switch (line.transportMode) {
      case "BUS":
      case "NOCTILIEN":
        return const EdgeInsets.symmetric(horizontal: 5.0);
      case "TRAM":
      case "METRO":
      case "RER":
      case "TER":
      default:
        return const EdgeInsets.all(5.0);
    }
  }
}
