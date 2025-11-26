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
    return ListView(
      controller: sc,
      padding: EdgeInsets.zero,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              TextFormField(
                controller: startController,
                readOnly: true,
                onTap: onStartTap,
                decoration: InputDecoration(
                  hintText: 'Start',
                  prefixIcon: Icon(Icons.trip_origin, color: Colors.grey[700]),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: destinationController,
                readOnly: true,
                onTap: onDestinationTap,
                decoration: InputDecoration(
                  hintText: 'Destination',
                  prefixIcon:
                      Icon(Icons.fmd_good_outlined, color: Colors.grey[700]),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showRoutes)
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (journeysList != null &&
              journeysList!.journeys != null &&
              journeysList!.journeys!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8.0),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: journeysList!.journeys!.length,
                itemBuilder: (context, index) {
                  final journey = journeysList!.journeys![index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10.0),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12.0),
                      child: JourneyCard(
                        journey: journey,
                        onJourneySelected: onJourneySelected,
                      ),
                    ),
                  );
                },
              ),
            )
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("Aucun itinéraire trouvé."),
              ),
            ),
      ],
    );
  }
}
