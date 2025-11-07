import 'package:flutter/material.dart';
import 'package:website_app/models/navitia/section.dart';
import 'package:website_app/utils/style_utils.dart';
import 'package:website_app/utils/time_utils.dart';

class SectionListItem extends StatelessWidget {
  final Section section;
  const SectionListItem({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final icon = StyleUtils.getSectionIcon(section);
    final color = StyleUtils.hexToColor(section.displayInformations?.color);
    String title = section.displayInformations?.label ??
        (section.mode == 'walking' ? 'Marche' : 'Section');

    if (section.displayInformations?.direction != null) {
      title += ' (Direction: ${section.displayInformations!.direction})';
    }

    final departureTime = TimeUtils.formatTime(section.departureDateTime);
    final arrivalTime = TimeUtils.formatTime(section.arrivalDateTime);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: color),
                ),
                const SizedBox(height: 4),
                if (section.from != null)
                  Text('$departureTime - ${section.from!.name ?? 'Départ'}'),
                if (section.stopDateTimes != null &&
                    section.stopDateTimes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: section.stopDateTimes!
                          .map((stop) => Text(
                                '• ${TimeUtils.formatTime(stop.arrivalDateTime)}: ${stop.stopPoint?.name ?? ''}',
                                style: TextStyle(
                                    color: Colors.grey[700], fontSize: 12),
                              ))
                          .toList(),
                    ),
                  ),
                if (section.to != null)
                  Text('$arrivalTime - ${section.to!.name ?? 'Arrivée'}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
