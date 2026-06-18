import 'package:flutter/material.dart';
import 'package:website_app/models/navitia/journey.dart';
import 'package:website_app/models/navitia/journeys.dart';
import 'package:website_app/widgets/journey_card.dart';

class SearchPanel extends StatelessWidget {
  final ScrollController sc;
  final TextEditingController startController;
  final TextEditingController destinationController;
  final VoidCallback onStartTap;
  final VoidCallback onDestinationTap;
  final bool isLoading;
  final bool showRoutes;
  final JourneysResponse? journeysList;
  final ValueChanged<Journey> onJourneySelected;

  const SearchPanel({
    super.key,
    required this.sc,
    required this.startController,
    required this.destinationController,
    required this.onStartTap,
    required this.onDestinationTap,
    required this.isLoading,
    required this.showRoutes,
    this.journeysList,
    required this.onJourneySelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
        // Search section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Route dots column
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          width: 2,
                          color: colorScheme.outlineVariant,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        // Start field
                        GestureDetector(
                          onTap: onStartTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 11),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    startController.text.isNotEmpty
                                        ? startController.text
                                        : 'Point de départ',
                                    style: startController.text.isNotEmpty
                                        ? textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w500)
                                        : textTheme.bodyMedium?.copyWith(
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.45)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Destination field
                        GestureDetector(
                          onTap: onDestinationTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 11),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    destinationController.text.isNotEmpty
                                        ? destinationController.text
                                        : 'Destination',
                                    style: destinationController.text.isNotEmpty
                                        ? textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w500)
                                        : textTheme.bodyMedium?.copyWith(
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.45)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (showRoutes)
          Expanded(
            child: ListView(
              controller: sc,
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Itinéraires',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (journeysList != null &&
                    journeysList!.journeys != null &&
                    journeysList!.journeys!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: journeysList!.journeys!.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final journey = journeysList!.journeys![index];
                        return JourneyCard(
                          journey: journey,
                          onJourneySelected: onJourneySelected,
                        );
                      },
                    ),
                  )
                else
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Icon(Icons.route_outlined,
                              size: 44,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          Text(
                            "Aucun itinéraire trouvé.",
                            style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          )
        else
          Expanded(
            child: ListView(
              controller: sc,
            ),
          ),
      ],
    );
  }
}
