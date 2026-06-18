import 'package:flutter/material.dart';
import 'package:website_app/models/navitia/journey.dart';
import 'package:website_app/models/navitia/section.dart';
import 'package:website_app/models/navitia/stop_area.dart';
import 'package:website_app/models/navitia/vehicle_journey.dart';
import 'package:website_app/utils/time_utils.dart';

import '../section_list_item.dart';

class JourneyDetailsPanel extends StatelessWidget {
  final ScrollController sc;
  final Journey journey;
  final VoidCallback onReturn;
  final Function(int) onSectionFocused;
  final List<StopArea> terminusList;
  final Function(int, VehicleJourney, Section) onSectionUpdate;

  const JourneyDetailsPanel({
    super.key,
    required this.sc,
    required this.journey,
    required this.onReturn,
    required this.onSectionFocused,
    required this.terminusList,
    required this.onSectionUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final arrivalTime = TimeUtils.formatTime(journey.arrivalDateTime);

    return Column(
      children: [
        // Handle bar
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: onReturn,
                tooltip: 'Retour',
              ),
              Expanded(
                child: Text(
                  'Votre itinéraire',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (arrivalTime != '--:--')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flag_rounded,
                          size: 14,
                          color: colorScheme.onPrimaryContainer),
                      const SizedBox(width: 4),
                      Text(
                        arrivalTime,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ),
        Divider(color: colorScheme.outlineVariant, height: 1),
        const SizedBox(height: 8),
        Expanded(
          child: (journey.sections == null || journey.sections!.isEmpty)
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.route_outlined,
                          size: 44,
                          color: colorScheme.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text(
                        'Aucun détail disponible',
                        style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: sc,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: journey.sections!.length,
                  itemBuilder: (context, index) {
                    return SectionListItem(
                      section: journey.sections![index],
                      terminusList: terminusList,
                      isLast: index == journey.sections!.length - 1,
                      onTap: () => onSectionFocused(index),
                      onUpdateRequested: (vj) =>
                          onSectionUpdate(index, vj, journey.sections![index]),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
