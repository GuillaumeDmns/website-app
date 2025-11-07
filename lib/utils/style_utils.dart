import 'package:flutter/material.dart';

import '../models/navitia/section.dart';

class StyleUtils {
  static Color hexToColor(String? hexColor) {
    hexColor = (hexColor ?? '808080').replaceAll('#', '');
    if (hexColor.length == 6) {
      return Color(int.parse('FF$hexColor', radix: 16));
    }
    return Colors.grey;
  }

  static IconData getSectionIcon(Section section) {
    switch (section.mode) {
      case 'walking':
        return Icons.directions_walk;
      case 'public_transport':
      case 'vehicle':
        return Icons.directions_bus;
      case 'transfer':
        return Icons.transfer_within_a_station;
      default:
        return Icons.trip_origin;
    }
  }
}