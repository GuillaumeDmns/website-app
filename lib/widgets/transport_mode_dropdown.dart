import 'package:flutter/material.dart';

class TransportModeDropdown extends StatelessWidget {
  final String? selectedMode;
  final Map<String, int> transportModeCount;
  final ValueChanged<String?> onModeSelected;

  const TransportModeDropdown({
    super.key,
    required this.selectedMode,
    required this.transportModeCount,
    required this.onModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      hint: const Text('Sélectionnez un mode de transport'),
      value: selectedMode,
      items: transportModeCount.keys.map((String mode) {
        final count = transportModeCount[mode] ?? 0;
        return DropdownMenuItem<String>(
          value: mode,
          child: Text("$mode ($count)"),
        );
      }).toList(),
      onChanged: onModeSelected,
    );
  }
}
