import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    // Section 8 - Haptic feedback for data updates (25-30ms, ~75dB)
    WidgetsBinding.instance.addPostFrameCallback((_) => HapticFeedback.mediumImpact());
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
            // Destination header (Sections 1-3)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Color(0x534A667E), // Header background (Section 2)
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.directions_rounded,
                      size: 24, // Increased to 24 for better visibility (Section 2)
                      color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.destination,
                      style: textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 16, // Accessibility minimum (Section 6)
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

class DepartureItem extends StatefulWidget {
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
  State<StatefulWidget> createState() => _DepartureItemState();
}

class _DepartureItemState extends State<DepartureItem> {
  String? isoTime;
  String? timeStr;
  String? relativeTimeStr;
  String? subtitle;
  
  @override
  void initState() {
    super.initState();
    _updateDepartureData();
  }
  
  @override
  void didUpdateWidget(covariant DepartureItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget != oldWidget || widget.departure != oldWidget.departure) {
      _updateDepartureData();
    }
  }

  void _updateDepartureData() {
    isoTime = widget.departure.expectedDepartureTime ?? widget.departure.expectedArrivalTime!;
    timeStr = TimeUtils.getTimeFromIso8601(isoTime);
    relativeTimeStr = TimeUtils.formatTimeRelativeToNow(isoTime);
    
    final note = widget.departure.journeyNote;
    final platform = widget.departure.arrivalPlatformName != null
        ? 'Quai ${widget.departure.arrivalPlatformName}'
        : null;
    subtitle = [note, platform].where((item) => item != null).join(' — ');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => HapticFeedback.lightImpact(), // Section 7 - Light impact on tap (6-12ms, ~90dB)
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), // Sections 1,3 - Enhanced padding
        decoration: BoxDecoration(
                color: Color(0x1533667E), // Departure row background (Section 4)
          borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: relativeTimeStr != null && _isStale(relativeTimeStr!) 
                  ? Colors.red.withValues(alpha: 0.3) 
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Time badge (Sections 2-5)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Color(0x664A667E), // Time badge background (Section 2)
                borderRadius: BorderRadius.circular(12),
              ),
                child: Text(
                  timeStr ?? '',
                style: textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13, // Section 6 - Accessibility minimum (10sp+)
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Destination name (Sections 4-5)
                  Text(
                    widget.departure.destinationName ?? '',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14, // Section 6 - Accessibility minimum
                    ),
                  ),
                  // Dynamic time-ago indicator (Sections 9-13)
                  if (relativeTimeStr != null && relativeTimeStr!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Text(
                          relativeTimeStr!,
                          style: textTheme.labelSmall?.copyWith(
                      color: _isStale(relativeTimeStr!)
                          ? Colors.orange.withValues(alpha: 0.9)
                          : (relativeTimeStr == "À quai" || 
                               relativeTimeStr == "À l'approche")
                              ? Colors.green.shade700
                              : colorScheme.onSecondaryContainer,
                            fontSize: 11, // Section 6 - Accessibility minimum
                          ),
                        ),
                        // Staleness warning (>30min) (Section 9)
                        if (relativeTimeStr != null && _isStale(relativeTimeStr!))
                          Positioned(
                            right: -4,
                            top: 2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.warning_rounded, size: 10, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                    ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 11, // Section 6 - Accessibility minimum
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Dynamic staleness detection (Section 9)
  bool _isStale(String relativeTime) {
    if (relativeTime == "À quai" || relativeTime == "À l'approche") return false;
    return relativeTime.contains("30") || 
           relativeTime.contains(":") && (int.tryParse(relativeTime.split(":")[1]) ?? 0) > 30;
  }
}
