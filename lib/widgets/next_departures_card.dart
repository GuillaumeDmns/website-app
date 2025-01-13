import 'package:flutter/material.dart';

import '../models/call_unit.dart';
import '../utils/time_utils.dart';

class NextDepartureCard extends StatefulWidget {
  const NextDepartureCard({
    super.key,
    required this.destination,
    required this.nextDepartures,
  });

  final String destination;
  final List<CallUnit> nextDepartures;

  @override
  State<StatefulWidget> createState() => _NextDepartureCardState();
}

class _NextDepartureCardState extends State<NextDepartureCard> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late int _initialItemCount = widget.nextDepartures.length;

  _handleRemovedItems({
    required List<CallUnit> oldItems,
    required List<CallUnit> newItems,
  }) {
    for (var i = 0; i < oldItems.length; i++) {
      final oldItem = oldItems[i];

      if (!newItems.any((newItem) {
        final oldTime = DateTime.parse(
            oldItem.expectedDepartureTime ?? oldItem.expectedArrivalTime!);
        final newTime = DateTime.parse(
            newItem.expectedDepartureTime ?? newItem.expectedArrivalTime!);

        return oldTime.difference(newTime).inMinutes == 0;
      })) {
        _listKey.currentState?.removeItem(
          i,
          (context, animation) => SizeTransition(
            sizeFactor: animation,
            child: DepartureItem(
                widget: widget,
                departure: widget.nextDepartures[i],
                isLastItem: false),
          ),
        );
      }
    }
  }

  _handleAddedItems({
    required List<CallUnit> oldItems,
    required List<CallUnit> newItems,
  }) {
    for (var i = 0; i < newItems.length; i++) {
      final newItem = newItems[i];

      if (!oldItems.any((oldItem) {
        final oldTime = DateTime.parse(
            oldItem.expectedDepartureTime ?? oldItem.expectedArrivalTime!);
        final newTime = DateTime.parse(
            newItem.expectedDepartureTime ?? newItem.expectedArrivalTime!);

        return oldTime.difference(newTime).inMinutes == 0;
      })) {
        _listKey.currentState?.insertItem(i);
      }
    }
  }

  @override
  void didUpdateWidget(covariant NextDepartureCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _handleAddedItems(
        oldItems: oldWidget.nextDepartures, newItems: widget.nextDepartures);
    _handleRemovedItems(
        oldItems: oldWidget.nextDepartures, newItems: widget.nextDepartures);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.destination),
            const SizedBox(height: 8.0),
            AnimatedList(
              key: _listKey,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              initialItemCount: _initialItemCount,
              itemBuilder: (context, index, animation) => SizeTransition(
                sizeFactor: animation,
                child: DepartureItem(
                  widget: widget,
                  departure: widget.nextDepartures[index],
                  isLastItem: widget.nextDepartures[index] ==
                      widget.nextDepartures.lastWhere(
                          (d) => d.destinationName == widget.destination),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DepartureItem extends StatelessWidget {
  const DepartureItem({
    super.key,
    required this.widget,
    required this.departure,
    required this.isLastItem,
  });

  final CallUnit departure;
  final NextDepartureCard widget;
  final bool isLastItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: Text(
            TimeUtils.getTimeFromIso8601(departure.expectedDepartureTime ??
                departure.expectedArrivalTime!),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          title: Text(departure.destinationName ?? ''),
          subtitle: Text(
            departure.arrivalPlatformName != null
                ? "Platform ${departure.arrivalPlatformName}"
                : '',
          ),
        ),
        if (!isLastItem) const Divider(height: 0),
      ],
    );
  }
}
