import 'package:flutter/material.dart';

import '../models/navitia/journey.dart';
import '../models/navitia/section.dart';
import '../utils/style_utils.dart';

class JourneyCard extends StatelessWidget {
  final Journey journey;
  final Function(Journey) onJourneySelected;

  const JourneyCard(
      {super.key, required this.journey, required this.onJourneySelected});

  String _formatTime(String? dateTimeString) {
    if (dateTimeString == null || dateTimeString.length < 13) return '--:--';
    try {
      return '${dateTimeString.substring(9, 11)}:${dateTimeString.substring(11, 13)}';
    } catch (_) {
      return '--:--';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final totalDurationInMinutes = (journey.duration ?? 0) ~/ 60;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => onJourneySelected(journey),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, colorScheme, textTheme, totalDurationInMinutes),
              const SizedBox(height: 14),
              _buildJourneySections(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme,
      TextTheme textTheme, int duration) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              _formatTime(journey.departureDateTime),
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward_rounded,
                  size: 18, color: colorScheme.onSurface.withValues(alpha: 0.4)),
            ),
            Text(
              _formatTime(journey.arrivalDateTime),
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$duration min',
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildJourneySections() {
    if (journey.sections == null || journey.sections!.isEmpty) {
      return const SizedBox.shrink();
    }
    final sectionsToDisplay = journey.sections!
        .where((s) => !['crow_fly', 'waiting', 'transfer'].contains(s.type))
        .toList();

    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: sectionsToDisplay.length,
        itemBuilder: (context, index) =>
            _buildSectionItem(sectionsToDisplay[index]),
        separatorBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildSectionItem(Section section) {
    if (section.type == 'public_transport' && section.displayInformations != null) {
      final info = section.displayInformations!;
      return Row(
        children: [
          Icon(
            _getTransportIcon(info.physicalMode),
            color: StyleUtils.hexToColor(info.color),
            size: 20,
          ),
          if (info.code != null && info.code!.isNotEmpty) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: StyleUtils.hexToColor(info.color),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                info.code!,
                style: TextStyle(
                  color: StyleUtils.hexToColor(info.textColor),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      );
    } else if (section.mode == 'walking') {
      return const Icon(Icons.directions_walk_rounded,
          color: Colors.grey, size: 20);
    }
    return const SizedBox.shrink();
  }

  IconData _getTransportIcon(String? physicalMode) {
    switch (physicalMode?.toLowerCase()) {
      case 'métro':
        return Icons.subway_outlined;
      case 'bus':
        return Icons.directions_bus_outlined;
      case 'rer':
      case 'train transilien':
      case 'ter':
        return Icons.train_outlined;
      case 'tram':
        return Icons.tram_outlined;
      default:
        return Icons.place_outlined;
    }
  }
}
