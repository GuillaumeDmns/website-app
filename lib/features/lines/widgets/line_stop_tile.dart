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

/// Size of a vehicle on the stop list, smaller than on the map
const _capsuleScale = 0.82;

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

/// Stop of the line on its lane; a vehicle standing there in place of its dot, with "à quai", its mission and its
/// destination on the right (design 2c)
class LineStopTile extends StatelessWidget {
  const LineStopTile({
    super.key,
    required this.stop,
    required this.rail,
    required this.line,
    this.terminus = false,
    this.vehicle,
    this.reverse = false,
    this.closed = false,
    required this.onOpen,
  });

  /// Opens a vehicle's sheet
  final ValueChanged<Vehicle> onOpen;

  static const _height = 44.0;

  /// The line doesn't stop there now (station closed, stop not served)
  final bool closed;

  final StopRef stop;
  final RailSpec rail;
  final LineSummary line;

  /// A terminus: a larger dot, its name bold
  final bool terminus;

  /// The vehicle standing at this stop
  final Vehicle? vehicle;

  /// It runs up the list (the other direction)
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final vehicle = this.vehicle;
    // Taller with a larger text size
    final height = MediaQuery.textScalerOf(context).scale(_height);

    return InkWell(
      onTap: () => context.push(Routes.stop(stop.id)),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(builder: (context, constraints) {
          final rowWidth = constraints.maxWidth;
          return Row(
            children: [
              _RailColumn(
                rail: rail,
                child: vehicle == null
                    ? Container(
                        width: terminus ? 16 : 12,
                        height: terminus ? 16 : 12,
                        decoration: BoxDecoration(
                          color: context.colors.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: rail.color, width: 3),
                        ),
                      )
                    : _ListCapsule(line: line, vehicle: vehicle, atStop: true, reverse: reverse, onOpen: onOpen),
              ),
              Expanded(
                child: Text(
                  stop.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: terminus || vehicle != null ? FontWeight.w600 : FontWeight.w400,
                    color: closed ? context.colors.muted : null,
                    decoration: closed ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (closed) PillTag(icon: Icons.block, color: Theme.of(context).colorScheme.error, text: context.l10n.notServed),
              // At most half of the row, against its end like the other rows' times: the stop's name keeps the rest
              if (vehicle != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: rowWidth / 2),
                  child: InkWell(
                    onTap: () => onOpen(vehicle),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _VehicleWhen(vehicle: vehicle, when: atStopLabel(line.mode)),
                          _VehicleDestination(vehicle: vehicle, compact: true),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

/// A vehicle running between two stops, on a row of its own between them (design 2c): its mission and destination,
/// when it gets to the next stop on the right
class LineVehicleTile extends StatelessWidget {
  const LineVehicleTile({
    super.key,
    required this.vehicle,
    required this.rail,
    required this.line,
    required this.now,
    this.reverse = false,
    required this.onOpen,
  });

  static const _height = 34.0;

  final Vehicle vehicle;
  final RailSpec rail;
  final LineSummary line;
  final DateTime now;

  /// It runs up the list (the other direction)
  final bool reverse;

  /// Opens its sheet
  final ValueChanged<Vehicle> onOpen;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.textScalerOf(context).scale(_height);
    return InkWell(
      onTap: () => onOpen(vehicle),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            _RailColumn(
              rail: rail,
              child: _ListCapsule(line: line, vehicle: vehicle, atStop: false, reverse: reverse, onOpen: onOpen),
            ),
            Expanded(child: _VehicleDestination(vehicle: vehicle)),
            const SizedBox(width: 8),
            _VehicleWhen(vehicle: vehicle, when: vehicleWhen(vehicle, now, line.mode, atStop: false)),
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

  static const _height = 48.0;

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
    final height = MediaQuery.textScalerOf(context).scale(_height);
    final vehicles = vehicleCount == 0
        ? null
        : switch (mode) {
            TransportMode.tram => l10n.liveTramsCount(vehicleCount),
            TransportMode.bus || TransportMode.noctilien => l10n.liveBusesCount(vehicleCount),
            _ => l10n.liveTrainsCount(vehicleCount),
          };
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

/// The vehicle on the line of the stop list, pointing down the list (the way it goes), up when [reverse]
class _ListCapsule extends StatelessWidget {
  const _ListCapsule({
    required this.line,
    required this.vehicle,
    required this.atStop,
    required this.reverse,
    required this.onOpen,
  });

  final LineSummary line;
  final Vehicle vehicle;
  final bool atStop;
  final bool reverse;
  final ValueChanged<Vehicle> onOpen;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => onOpen(vehicle),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Transform.rotate(
            angle: reverse ? 0 : math.pi,
            child: VehicleCapsule(line: line, atStop: atStop, scale: _capsuleScale),
          ),
        ),
      );
}

/// When a vehicle gets to its next stop (`1 min`, `à quai`), orange when it is late, with its delay
class _VehicleWhen extends StatelessWidget {
  const _VehicleWhen({required this.vehicle, required this.when});

  final Vehicle vehicle;
  final String when;

  @override
  Widget build(BuildContext context) {
    final delay = vehicleDelay(vehicle);
    return Text(
      delay == null ? when : '$when · $delay',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: delay == null ? context.colors.live : context.colors.delayed,
          ),
    );
  }
}

/// A vehicle's mission (a train's code) and destination, `ZEMA → Melun`
class _VehicleDestination extends StatelessWidget {
  const _VehicleDestination({required this.vehicle, this.compact = false});

  final Vehicle vehicle;

  /// Under "à quai": smaller, the mission in text
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destination = '→ ${vehicle.destination ?? '?'}';
    if (compact) {
      return Text(
        [?vehicle.name, destination].join(' '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted),
      );
    }
    return Row(
      children: [
        if (vehicle.name case final name?) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Text(
                name,
                style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            destination,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted),
          ),
        ),
      ],
    );
  }
}
