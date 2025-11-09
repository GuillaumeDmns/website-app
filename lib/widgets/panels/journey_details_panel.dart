import 'package:flutter/material.dart';
import 'package:website_app/models/navitia/journey.dart';

import '../section_list_item.dart';

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
    return Column(
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
                  'Your journey',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: (journey.sections == null || journey.sections!.isEmpty)
              ? const Center(child: Text("No detail for this journey"))
              : ListView.builder(
                  controller: sc,
                  padding: EdgeInsets.zero,
                  itemCount: journey.sections!.length,
                  itemBuilder: (context, index) {
                    return SectionListItem(
                      section: journey.sections![index],
                      isLast: index == journey.sections!.length - 1,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
