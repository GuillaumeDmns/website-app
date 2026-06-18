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
  late final int _initialItemCount = widget.nextDepartures.length;

  void _handleRemovedItems({
    required List<CallUnit> oldItems,
    required List<CallUnit> newItems,
  }) {
    for (var i = 0; i < oldItems.length; i++) {
      final oldItem = oldItems[i];
      if (!newItems.any((newItem) => newItem.id == oldItem.id)) {
        _listKey.currentState?.removeItem(
          i,
          (context, animation) => SizeTransition(
            sizeFactor: animation,
            child: DepartureItem(
              widget: widget,
              departure: widget.nextDepartures[i],
              isLastItem: false,
            ),
          ),
        );
      }
    }
  }

  void _handleAddedItems({
    required List<CallUnit> oldItems,
    required List<CallUnit> newItems,
  }) {
    for (var i = 0; i < newItems.length; i++) {
      final newItem = newItems[i];
      if (!oldItems.any((oldItem) => newItem.id == oldItem.id)) {
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Destination header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              child: Row(
                children: [
                  Icon(Icons.directions_rounded,
                      size: 16,
                      color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.destination,
                      style: textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: AnimatedList(
                key: _listKey,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final timeStr = TimeUtils.getTimeFromIso8601(
        departure.expectedDepartureTime ?? departure.expectedArrivalTime!);

    final subtitle = [
      departure.journeyNote,
      departure.arrivalPlatformName != null
          ? 'Quai ${departure.arrivalPlatformName}'
          : null,
    ].where((item) => item != null).join(' — ');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Time badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  timeStr,
                  style: textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      departure.destinationName ?? '',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLastItem)
          Divider(height: 1, color: colorScheme.outlineVariant, indent: 16),
      ],
    );
  }
}
