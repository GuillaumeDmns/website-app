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
    final displayInfos = section.displayInformations;
    if (displayInfos != null) {
      switch (displayInfos.commercialMode) {
        case 'RER':
        case 'Train Transilien':
          return Icons.train;
        case 'Métro':
          return Icons.subway;
        case 'Tramway':
          return Icons.tram;
        case 'Bus':
          return Icons.directions_bus;
        default:
          return Icons.directions_walk;
      }
    }

    if (section.mode != null) {
      switch (section.mode) {
        case 'walking':
          return Icons.directions_walk;
        case 'public_transport':
        case 'vehicle':
          return Icons.directions_bus;
        case 'transfer':
          return Icons.transfer_within_a_station;
        default:
          return Icons.directions_walk;
      }
    }

    if (section.type != null) {
      switch (section.type) {
        case 'transfer':
          return Icons.transfer_within_a_station;
        case 'waiting':
          return Icons.hourglass_top;
        default:
          return Icons.directions_walk;
      }
    }

    return Icons.directions_walk;
  }
}
