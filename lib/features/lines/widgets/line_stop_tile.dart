import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/widgets/ui.dart';
import '../../../l10n/l10n.dart';
import '../line_vehicles.dart';
import '../vehicle_sheet.dart';

/// Stop of the line drawn on a vertical line of the line's color
class LineStopTile extends StatelessWidget {
  const LineStopTile({
    super.key,
    required this.stop,
    required this.color,
    required this.isFirst,
    required this.isLast,
    required this.line,
    this.vehicles = const [],
    this.closed = false,
    required this.onFollow,
  });

  /// "Suivre" in a vehicle's sheet
  final ValueChanged<Vehicle> onFollow;

  static const _height = 44.0;

  /// The line doesn't stop there now (station closed, stop not served)
  final bool closed;

  final StopRef stop;
  final Color color;
  final bool isFirst;
  final bool isLast;
  final LineSummary line;

  /// Vehicles around this stop, offset in stops (-0.5: halfway from the previous one, 0: at the stop)
  final List<({double offset, Vehicle vehicle})> vehicles;

  @override
  Widget build(BuildContext context) {
    final terminus = isFirst || isLast;
    // Taller with a larger text size
    final height = MediaQuery.textScalerOf(context).scale(_height);

    return InkWell(
      onTap: () => context.push(Routes.stop(stop.id)),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Column(
                    children: [
                      Expanded(child: Container(width: 6, color: isFirst ? Colors.transparent : color)),
                      Expanded(child: Container(width: 6, color: isLast ? Colors.transparent : color)),
                    ],
                  ),
                  Container(
                    width: terminus ? 16 : 12,
                    height: terminus ? 16 : 12,
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 3),
                    ),
                  ),
                  for (final (:offset, :vehicle) in vehicles)
                    Positioned(
                      top: height / 2 + offset * height - 10,
                      left: 14,
                      child: GestureDetector(
                        onTap: () => showVehicleSheet(context, line: line, vehicle: vehicle, onFollow: () => onFollow(vehicle)),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: VehicleMarker(line: line, size: 20, punctuality: Punctuality.of(vehicle), stale: vehicle.stale),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                stop.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: terminus ? FontWeight.w600 : FontWeight.w400,
                  color: closed ? context.colors.muted : null,
                  decoration: closed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (closed) PillTag(icon: Icons.block, color: Theme.of(context).colorScheme.error, text: context.l10n.notServed),
          ],
        ),
      ),
    );
  }
}
