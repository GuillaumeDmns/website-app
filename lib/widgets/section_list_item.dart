import 'package:flutter/material.dart';
import 'package:website_app/models/navitia/section.dart';
import 'package:website_app/utils/journey_utils.dart';
import 'package:website_app/utils/style_utils.dart';
import 'package:website_app/utils/time_utils.dart';

class SectionListItem extends StatelessWidget {
  final Section section;
  final bool isLast;
  final VoidCallback? onTap;

  const SectionListItem({
    super.key,
    required this.section,
    required this.isLast,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = StyleUtils.getSectionIcon(section);
    final color = StyleUtils.hexToColor(section.displayInformations?.color);
    String title = JourneyUtils.getSectionTitle(section);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 40,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 12.0),
                    Icon(icon, color: color, size: 28),
                    Expanded(
                      child: Container(
                        width: 2,
                        color: isLast ? Colors.transparent : color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: color),
                      ),
                      const SizedBox(height: 8),
                      if (section.stopDateTimes != null &&
                          section.stopDateTimes!.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(section.stopDateTimes!.length,
                              (index) {
                            final stop = section.stopDateTimes![index];
                            final stopName = stop.stopPoint?.name ?? '';
                            if (index == 0) {
                              final departureTime =
                                  TimeUtils.formatTime(section.departureDateTime);
                              return Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  '$departureTime - $stopName',
                                  style: TextStyle(
                                    color: Colors.grey[850],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }
                            if (index == section.stopDateTimes!.length - 1) {
                              final arrivalTime =
                                  TimeUtils.formatTime(section.arrivalDateTime);
                              return Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  '$arrivalTime - $stopName',
                                  style: TextStyle(
                                    color: Colors.grey[850],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }
                            final arrivalTime =
                                TimeUtils.formatTime(stop.arrivalDateTime);
                            return Padding(
                              padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                              child: Text(
                                '• $arrivalTime: $stopName',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 13,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
