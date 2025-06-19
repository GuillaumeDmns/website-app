import 'package:flutter/material.dart';

import '../models/navitia/journey.dart';
import '../models/navitia/section.dart';

class JourneyCard extends StatelessWidget {
  final Journey journey;

  const JourneyCard({super.key, required this.journey});

  String _formatTime(String? dateTimeString) {
    if (dateTimeString == null || dateTimeString.length < 13) {
      return '--:--';
    }

    try {
      final String hour = dateTimeString.substring(9, 11);
      final String minute = dateTimeString.substring(11, 13);

      return '$hour:$minute';
    } catch (e) {
      print('Erreur lors de l\'extraction de l\'heure : $e');
      return '--:--';
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalDurationInMinutes = (journey.duration ?? 0) ~/ 60;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      elevation: 3.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildJourneyHeader(totalDurationInMinutes),
            const SizedBox(height: 16),
            _buildJourneySections(),
          ],
        ),
      ),
    );
  }

  Widget _buildJourneyHeader(int duration) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              _formatTime(journey.departureDateTime),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Icon(Icons.arrow_forward, size: 18, color: Colors.black54),
            ),
            Text(
              _formatTime(journey.arrivalDateTime),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        Text(
          '$duration min',
          style: const TextStyle(fontSize: 16, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildJourneySections() {
    if (journey.sections == null || journey.sections!.isEmpty) {
      return const SizedBox.shrink();
    }

    final sectionsToDisplay =
        journey.sections!.where((s) => !["crow_fly", "waiting", "transfer"].contains(s.type)).toList();

    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: sectionsToDisplay.length,
        itemBuilder: (context, index) {
          final section = sectionsToDisplay[index];
          return _buildSectionItem(section);
        },
        separatorBuilder: (context, index) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.0),
          child: Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildSectionItem(Section section) {
    if (section.type == 'public_transport' &&
        section.displayInformations != null) {
      final displayInfo = section.displayInformations!;
      return Row(
        children: [
          Icon(
            _getTransportIcon(displayInfo.physicalMode),
            color: _hexToColor(displayInfo.color),
            size: 24,
          ),
          const SizedBox(width: 6),
          if (displayInfo.code != null && displayInfo.code!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _hexToColor(displayInfo.color),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                displayInfo.code!,
                style: TextStyle(
                  color: _hexToColor(displayInfo.textColor),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      );
    }
    else if (section.mode == 'walking') {
      return const Icon(Icons.directions_walk, color: Colors.black54, size: 24);
    }
    else {
      return const SizedBox.shrink();
    }
  }

  IconData _getTransportIcon(String? physicalMode) {
    switch (physicalMode?.toLowerCase()) {
      case 'métro':
        return Icons.subway_outlined;
      case 'bus':
        return Icons.directions_bus_outlined;
      case 'rer':
      case 'transilien':
      case 'ter':
        return Icons.train_outlined;
      case 'tram':
        return Icons.tram_outlined;
      default:
        return Icons.place_outlined;
    }
  }

  Color _hexToColor(String? hexColor) {
    hexColor = (hexColor ?? '808080').replaceAll('#', '');
    if (hexColor.length == 6) {
      return Color(int.parse('FF$hexColor', radix: 16));
    }
    return Colors.grey;
  }
}
