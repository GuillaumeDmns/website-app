import 'package:flutter/material.dart';
import 'package:website_app/widgets/transport_mode_dropdown.dart';

import '../models/line_dto.dart';
import 'line_list.dart';

class TransportModeSelector extends StatelessWidget {
  final Map<String, int> transportModeCount;
  final String? selectedMode;
  final List<LineDTO> lines;
  final ValueChanged<String?> onModeSelected;
  final ValueChanged<LineDTO> onLineSelected;

  const TransportModeSelector({
    super.key,
    required this.transportModeCount,
    required this.selectedMode,
    required this.lines,
    required this.onModeSelected,
    required this.onLineSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TransportModeDropdown(
          selectedMode: selectedMode,
          transportModeCount: transportModeCount,
          onModeSelected: onModeSelected,
        ),
        Expanded(
          child: LineList(
            selectedMode: selectedMode,
            lines: lines,
            onLineSelected: onLineSelected,
          ),
        ),
      ],
    );
  }
}