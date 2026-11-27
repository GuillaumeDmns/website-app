import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/widgets/ui.dart';
import '../../../l10n/l10n.dart';
import '../line_vehicles.dart';

/// Where the lane [lane] is drawn in the rail column: the trunk's, then each branch's a little to the right
double laneX(int lane) => 24 + lane * 20;

/// Width of the rail column for branches nested [depth] deep
double railWidth(int depth) => 48 + depth * 20;

/// The line's stroke in the stop list
const _strokeWidth = 6.0;

/// How a row of the stop list draws the line on its left: its own [lane] (its [top] and [bottom] halves, the stop
/// between them), the other lanes [passing] by from top to bottom, in a column [width] wide
class RailSpec {
  const RailSpec({
    required this.color,
    this.lane = 0,
    this.passing = const {},
    this.top = true,
    this.bottom = true,
    this.joinFrom = const {},
    this.width = 48,
  });

  final Color color;
  final int lane;
  final Set<int> passing;

  /// Lanes bending into this row's own lane at its stop: another way coming back (the loop closing)
  final Set<int> joinFrom;
  final bool top;
  final bool bottom;
  final double width;
}

/// A bend of the rail across a row, from lane [from] at its top to lane [to] at its bottom; [partial] keeps only the
/// half touching the parent's lane ([parentAtTop]), ended by a dot: a branch folded away. A [loop] leaves lane `from`
/// and comes back to it within the row, out to lane `to`: another way between two stops, folded.
typedef RailBend = ({int from, int to, bool partial, bool parentAtTop, bool loop});

class _RailPainter extends CustomPainter {
  const _RailPainter(this.rail, {this.bend});

  final RailSpec rail;
  final RailBend? bend;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = rail.color
      ..strokeWidth = _strokeWidth;
    for (final lane in rail.passing) {
      canvas.drawLine(Offset(laneX(lane), 0), Offset(laneX(lane), size.height), paint);
    }
    final stroke = Paint()
      ..color = rail.color
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke;
    final bend = this.bend;
    if (bend == null) {
      final x = laneX(rail.lane);
      if (rail.top) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height / 2), paint);
      }
      if (rail.bottom) {
        canvas.drawLine(Offset(x, size.height / 2), Offset(x, size.height), paint);
      }
      // A way coming back into this lane at its stop
      for (final lane in rail.joinFrom) {
        final from = laneX(lane);
        canvas.drawPath(
          Path()
            ..moveTo(from, 0)
            ..cubicTo(from, size.height * 0.3, x, size.height * 0.2, x, size.height / 2),
          stroke,
        );
      }
      return;
    }
    if (bend.loop) {
      // Out of the lane and back into it: a closed loop beside the lane passing straight
      final lane = laneX(bend.from);
      final out = laneX(bend.to);
      canvas.drawPath(
        Path()
          ..moveTo(lane, size.height * 0.1)
          ..cubicTo(lane, size.height * 0.35, out, size.height * 0.25, out, size.height * 0.5)
          ..cubicTo(out, size.height * 0.75, lane, size.height * 0.65, lane, size.height * 0.9),
        stroke,
      );
      return;
    }
    final start = Offset(laneX(bend.from), 0);
    final end = Offset(laneX(bend.to), size.height);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(start.dx, size.height * 0.55, end.dx, size.height * 0.45, end.dx, end.dy);
    if (!bend.partial) {
      canvas.drawPath(path, stroke);
      return;
    }
    final metric = path.computeMetrics().first;
    final cutAt = metric.length * 0.6;
    canvas.drawPath(
      bend.parentAtTop ? metric.extractPath(0, cutAt) : metric.extractPath(metric.length - cutAt, metric.length),
      stroke,
    );
    final cut = metric.getTangentForOffset(bend.parentAtTop ? cutAt : metric.length - cutAt)!.position;
    canvas.drawCircle(cut, _strokeWidth * 0.8, Paint()..color = rail.color);
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.rail.color != rail.color ||
      old.rail.lane != rail.lane ||
      old.rail.top != rail.top ||
      old.rail.bottom != rail.bottom ||
      old.rail.passing.length != rail.passing.length ||
      !old.rail.passing.containsAll(rail.passing) ||
      old.rail.joinFrom.length != rail.joinFrom.length ||
      !old.rail.joinFrom.containsAll(rail.joinFrom) ||
      old.bend != bend;
}

/// The rail column of a row: [rail] drawn, and [child] (a stop's dot, a vehicle) on its own lane
class _RailColumn extends StatelessWidget {
  const _RailColumn({required this.rail, this.child, this.bend});

  final RailSpec rail;
  final Widget? child;
  final RailBend? bend;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: rail.width,
        child: CustomPaint(
          painter: _RailPainter(rail, bend: bend),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (child case final child?)
                Positioned(
                  left: laneX(rail.lane) - 30,
                  width: 60,
                  top: 0,
                  bottom: 0,
                  child: Center(child: child),
                ),
            ],
          ),
        ),
      );
}

/// Stop of the line on its lane; the vehicles standing there are drawn over its dot by the stop list
/// ([LineVehicleMark])
class LineStopTile extends StatelessWidget {
  const LineStopTile({
    super.key,
    required this.stop,
    required this.rail,
    this.terminus = false,
    this.closed = false,
  });

  /// Its height before the text size: room for two vehicles back to back between two stops
  static const height = 52.0;

  /// The line doesn't stop there now (station closed, stop not served)
  final bool closed;

  final StopRef stop;
  final RailSpec rail;

  /// A terminus: a larger dot, its name bold
  final bool terminus;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(Routes.stop(stop.id)),
      child: SizedBox(
        // Taller with a larger text size
        height: MediaQuery.textScalerOf(context).scale(height),
        child: Row(
          children: [
            _RailColumn(
              rail: rail,
              child: Container(
                width: terminus ? 16 : 12,
                height: terminus ? 16 : 12,
                decoration: BoxDecoration(
                  color: context.colors.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: rail.color, width: 3),
                ),
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

/// A branch of the line off its parent (the trunk or another branch), folded on one row or heading its stops when
/// [expanded]: where it comes from ([merges]) or where it goes, how many stops and vehicles it has; a tap folds or
/// unfolds it. The rail bends from the parent's lane to the branch's, or back into it when it [merges].
class LineSpurTile extends StatelessWidget {
  const LineSpurTile({
    super.key,
    this.title,
    this.loop = false,
    required this.end,
    required this.merges,
    required this.stopCount,
    required this.vehicleCount,
    required this.mode,
    required this.expanded,
    required this.rail,
    required this.parentLane,
    required this.onToggle,
  });

  /// Its height before the text size
  static const height = 48.0;

  /// Its far end: where it comes from, or its terminus
  final StopRef end;

  /// Instead of where it comes from or goes: another way between two stops, the other direction's own stops
  final String? title;

  /// Another way between two stops of its parent: it comes back to it, folded as a closed loop
  final bool loop;
  final bool merges;
  final int stopCount;
  final int vehicleCount;
  final TransportMode mode;
  final bool expanded;

  /// Its own lane, and the lanes passing by (its parent's when it goes on past this row)
  final RailSpec rail;
  final int parentLane;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final height = MediaQuery.textScalerOf(context).scale(LineSpurTile.height);
    final vehicles = vehicleCount == 0 ? null : vehiclesCount(mode, vehicleCount);
    return InkWell(
      onTap: onToggle,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            _RailColumn(
              rail: rail,
              bend: loop && !expanded
                  ? (from: parentLane, to: rail.lane, partial: false, parentAtTop: true, loop: true)
                  : merges
                      ? (from: rail.lane, to: parentLane, partial: !expanded, parentAtTop: false, loop: false)
                      : (from: parentLane, to: rail.lane, partial: !expanded, parentAtTop: true, loop: false),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title ?? (merges ? l10n.lineBranchFrom(end.name) : l10n.lineBranchTo(end.name)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                [l10n.lineBranchStops(stopCount), ?vehicles].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          color: context.colors.muted,
                          semanticLabel: expanded ? l10n.lineBranchFold : l10n.lineBranchUnfold,
                        ),
                      ],
                    ),
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

/// `3 trains`, `2 bus`, `1 tram`
String vehiclesCount(TransportMode mode, int count) => switch (mode) {
      TransportMode.tram => currentL10n.liveTramsCount(count),
      TransportMode.bus || TransportMode.noctilien => currentL10n.liveBusesCount(count),
      _ => currentL10n.liveTrainsCount(count),
    };

/// Vehicles on the rail of the stop list, never on a row of their own: one capsule pointing the way they go (down
/// the list, up when [reverse]), with how many they are on it when several run between the same two stops the same
/// way. A white bar across it when they stand at a stop. A tap opens them ([onOpen]).
class LineVehicleMark extends StatelessWidget {
  const LineVehicleMark({
    super.key,
    required this.line,
    required this.vehicles,
    required this.reverse,
    required this.atStop,
    required this.label,
    required this.onOpen,
  });

  final LineSummary line;
  final List<Vehicle> vehicles;
  final bool reverse;
  final bool atStop;

  /// What a screen reader says of it
  final String label;
  final ValueChanged<List<Vehicle>> onOpen;

  /// Smaller than on the map: two fit back to back between two stops
  static const scale = 0.64;

  /// Its length along the rail, its white ring included
  static const length = 37 * scale;

  /// Its box, square
  static double get size => VehicleCapsule.boxSize(scale: scale);

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onOpen(vehicles),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Its square box drawn whole in a tap area as long as the capsule
                OverflowBox(
                  maxWidth: size,
                  maxHeight: size,
                  child: Transform.rotate(
                    angle: reverse ? 0 : math.pi,
                    child: VehicleCapsule(line: line, atStop: atStop, scale: scale),
                  ),
                ),
                if (vehicles.length > 1)
                  Align(
                    alignment: Alignment.center,
                    child: Transform.translate(offset: const Offset(16, 0), child: _CountBadge(vehicles.length)),
                  ),
              ],
            ),
          ),
        ),
      );
}

/// How many vehicles a mark stands for, small beside its capsule: dark ringed with white, as the capsule's edges
class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        height: 16,
        constraints: const BoxConstraints(minWidth: 16),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF101215),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Text(
          '$count',
          textScaler: TextScaler.noScaling,
          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600, height: 1),
        ),
      );
}
