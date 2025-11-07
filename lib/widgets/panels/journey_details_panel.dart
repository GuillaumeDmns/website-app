import 'package:flutter/material.dart';
import 'package:website_app/models/navitia/journey.dart';

import '../seaction_list_item.dart';

class JourneyDetailsPanel extends StatelessWidget {
  final ScrollController sc;
  final Journey journey;
  final VoidCallback onReturn;

  const JourneyDetailsPanel({
    super.key,
    required this.sc,
    required this.journey,
    required this.onReturn,
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
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onReturn,
              ),
              const Expanded(
                child: Text(
                  'Votre itinéraire',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        const Divider(),
        if (journey.sections == null || journey.sections!.isEmpty)
          const Center(child: Text("Aucun détail pour cet itinéraire."))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: journey.sections!.length,
            itemBuilder: (context, index) {
              final section = journey.sections![index];
              return SectionListItem(section: section);
            },
          ),
      ],
    );
  }
}
