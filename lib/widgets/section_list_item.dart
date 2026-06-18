import 'package:flutter/material.dart';
import 'package:website_app/models/navitia/boarding_position.dart';
import 'package:website_app/models/navitia/section.dart';
import 'package:website_app/models/navitia/stop_area.dart';
import 'package:website_app/models/navitia/vehicle_journey.dart';
import 'package:website_app/utils/journey_utils.dart';
import 'package:website_app/utils/style_utils.dart';
import 'package:website_app/utils/time_utils.dart';

import 'alternative_journeys_selector.dart';

class SectionListItem extends StatelessWidget {
  final Section section;
  final List<StopArea> terminusList;
  final bool isLast;
  final VoidCallback? onTap;
  final Function(VehicleJourney)? onUpdateRequested;

  const SectionListItem({
    super.key,
    required this.section,
    required this.terminusList,
    required this.isLast,
    this.onTap,
    this.onUpdateRequested,
  });

  void _showAlternativeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => AlternativeVehicleSelector(
        originalSection: section,
        onSelected: (VehicleJourney selected) {
          Navigator.pop(ctx);
          if (onUpdateRequested != null) {
            onUpdateRequested!(selected);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final icon = StyleUtils.getSectionIcon(section);
    final color = StyleUtils.hexToColor(section.displayInformations?.color);
    final String title = JourneyUtils.getSectionTitle(section, terminusList);
    final bool isPublicTransport = section.type == 'public_transport';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Timeline column
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    // Icon in colored circle
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 18),
                    ),
                    // Vertical connector
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 2,
                          color: isLast ? Colors.transparent : color.withValues(alpha: 0.35),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                          if (isPublicTransport)
                            Material(
                              color: Colors.transparent,
                              child: IconButton(
                                icon: Icon(Icons.edit_calendar_outlined,
                                    size: 18,
                                    color: colorScheme.onSurface
                                        .withValues(alpha: 0.4)),
                                tooltip: 'Trouver un autre horaire',
                                onPressed: () => _showAlternativeSelector(context),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                      // Boarding indicator
                      if (section.bestBoardingPositions != null &&
                          section.bestBoardingPositions!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Text(
                                'Montée :',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildTrainCar(
                                  color,
                                  section.bestBoardingPositions!
                                      .contains(BoardingPositionEnum.back),
                                  isBack: true),
                              _buildTrainCar(
                                  color,
                                  section.bestBoardingPositions!
                                      .contains(BoardingPositionEnum.middle)),
                              _buildTrainCar(
                                  color,
                                  section.bestBoardingPositions!
                                      .contains(BoardingPositionEnum.front),
                                  isFront: true),
                            ],
                          ),
                        ),
                      const SizedBox(height: 6),
                      // Stops list
                      if (section.stopDateTimes != null &&
                          section.stopDateTimes!.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(
                              section.stopDateTimes!.length, (index) {
                            final stop = section.stopDateTimes![index];
                            final stopName = stop.stopPoint?.name ?? '';

                            if (index == 0) {
                              final time = TimeUtils.formatTime(section.departureDateTime);
                              return _buildStopRow(context, time, stopName,
                                  isEndpoint: true, colorScheme: colorScheme, textTheme: textTheme);
                            }
                            if (index == section.stopDateTimes!.length - 1) {
                              final time = TimeUtils.formatTime(section.arrivalDateTime);
                              return _buildStopRow(context, time, stopName,
                                  isEndpoint: true, colorScheme: colorScheme, textTheme: textTheme);
                            }
                            final time = TimeUtils.formatTime(stop.arrivalDateTime);
                            return _buildStopRow(context, time, stopName,
                                isEndpoint: false, colorScheme: colorScheme, textTheme: textTheme);
                          }),
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

  Widget _buildTrainCar(Color color, bool isActive,
      {bool isFront = false, bool isBack = false}) {
    return Builder(builder: (context) {
      final bgColor = isActive ? color : Colors.grey.withValues(alpha: 0.35);
      final windowColor = isActive ? Colors.white.withValues(alpha: 0.9) : Theme.of(context).colorScheme.surface.withValues(alpha: 0.8);

      return Padding(
        padding: EdgeInsets.only(right: isFront ? 0 : 2.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 18,
              width: 32,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.horizontal(
                  left: isBack ? const Radius.circular(4) : const Radius.circular(2),
                  right: isFront ? const Radius.circular(10) : const Radius.circular(2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (!isFront) ...[
                    Container(
                      width: 8,
                      height: 6,
                      decoration: BoxDecoration(
                        color: windowColor,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 6,
                      decoration: BoxDecoration(
                        color: windowColor,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: 10,
                      height: 8,
                      margin: const EdgeInsets.only(left: 2),
                      decoration: BoxDecoration(
                        color: windowColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 8,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: windowColor,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(1.5),
                          right: Radius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: 22,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildWheel(isActive),
                  _buildWheel(isActive),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildWheel(bool isActive) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: isActive ? Colors.grey.shade700 : Colors.grey.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildStopRow(BuildContext context, String time, String name,
      {required bool isEndpoint,
      required ColorScheme colorScheme,
      required TextTheme textTheme}) {
    if (isEndpoint) {
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Text(
              time,
              style: textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 8),
      child: Row(
        children: [
          Text(
            time,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '• $name',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
