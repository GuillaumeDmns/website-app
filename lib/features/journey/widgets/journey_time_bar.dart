import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/api/models.dart';
import '../../../core/utils/colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../l10n/l10n.dart';
import '../../bikes/bike_widgets.dart';
import '../../traffic/disruption_widgets.dart';
import '../../traffic/traffic_providers.dart';
import 'journey_map.dart';

/// The time span shared by the journey results, so that their bars compare at a glance: when each one leaves and
/// arrives, how long it waits and walks
@immutable
class TimeAxis {
  const TimeAxis({required this.start, required this.end, required this.ticks, this.now});

  /// Results from [departures] to [arrivals]; [now] marked when it falls in or just before them
  factory TimeAxis.of(List<JourneyOption> journeys, DateTime now) {
    var start = journeys.map((journey) => journey.departure).reduce((a, b) => a.isBefore(b) ? a : b);
    var end = journeys.map((journey) => journey.arrival).reduce((a, b) => a.isAfter(b) ? a : b);
    final showsNow = !now.isAfter(end) && start.difference(now) <= const Duration(minutes: 15);
    if (showsNow && now.isBefore(start)) {
      start = now;
    }
    // A little air at both ends, so that the first and last segments keep their round corners in view
    final span = end.difference(start);
    final pad = span * 0.03;
    start = start.subtract(pad);
    end = end.add(pad);
    // Round times, at most 5 of them
    final minutes = math.max(1, span.inMinutes);
    final step = const [5, 10, 15, 20, 30, 60, 120, 180].firstWhere((step) => minutes / step <= 4.5, orElse: () => 240);
    final local = start.toLocal();
    var tick = DateTime(local.year, local.month, local.day, local.hour).add(Duration(minutes: step * (local.minute ~/ step + 1)));
    final ticks = <DateTime>[];
    while (tick.isBefore(end)) {
      ticks.add(tick.toUtc());
      tick = tick.add(Duration(minutes: step));
    }
    return TimeAxis(start: start, end: end, ticks: ticks, now: showsNow ? now : null);
  }

  final DateTime start;
  final DateTime end;
  final List<DateTime> ticks;
  final DateTime? now;

  /// Where [time] falls, from 0 (start) to 1 (end)
  double fraction(DateTime time) {
    final span = end.difference(start).inSeconds;
    return span <= 0 ? 0 : (time.difference(start).inSeconds / span).clamp(0.0, 1.0);
  }
}

/// Over the results: the round times of the axis, and now in green
class TimeAxisHeader extends StatelessWidget {
  const TimeAxisHeader({super.key, required this.axis});

  final TimeAxis axis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.labelMedium?.copyWith(fontSize: 11);
    final height = MediaQuery.textScalerOf(context).scale(14) + 4;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final now = axis.now;
          final nowX = now == null ? null : axis.fraction(now) * width;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final tick in axis.ticks)
                // A time too close to now's label is left out
                if (nowX == null || (axis.fraction(tick) * width - nowX).abs() > 30)
                  _centered(axis.fraction(tick) * width, width, Text(formatClock(tick), style: style)),
              if (nowX != null)
                _centered(
                  nowX,
                  width,
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(5)),
                    child: Text(formatClock(now!),
                        style: theme.textTheme.labelMedium?.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onPrimary)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// [child] centered on [x], kept inside the width
  static Widget _centered(double x, double width, Widget child) => Positioned(
        left: x - 30,
        width: 60,
        top: 0,
        child: Align(
          alignment: Alignment(x < 30 ? -1 : (x > width - 30 ? 1 : 0), 0),
          child: child,
        ),
      );
}

/// A journey on the shared [TimeAxis]: its rides as blocks of their line's color with the line's name, walks as round
/// dots, waits as a thin line, the round times and now as faint marks behind. Disrupted lines get their dot.
class JourneyTimeBar extends ConsumerWidget {
  const JourneyTimeBar({super.key, required this.journey, required this.axis});

  final JourneyOption journey;
  final TimeAxis axis;

  static const height = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final severities = ref.watch(lineSeveritiesProvider);

    // The segments, with the waits between sections the plan leaves implicit
    final segments = <(_Kind, DateTime, DateTime, JourneySection?)>[];
    DateTime? previous;
    for (final section in journey.sections) {
      if (previous != null && section.departure.difference(previous).inSeconds >= 60) {
        segments.add((_Kind.wait, previous, section.departure, null));
      }
      final kind = switch (section.kind) {
        SectionKind.transit => _Kind.ride,
        SectionKind.wait => _Kind.wait,
        SectionKind.walk || SectionKind.transfer => _Kind.walk,
        SectionKind.bike => _Kind.bike,
        _ => _Kind.other,
      };
      if (section.arrival.isAfter(section.departure)) {
        segments.add((kind, section.departure, section.arrival, section));
      }
      previous = section.arrival;
    }

    return Semantics(
      label: '${formatClock(journey.departure)} → ${formatClock(journey.arrival)}',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            double x(DateTime time) => axis.fraction(time) * width;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BarPainter(
                      ticks: [for (final tick in axis.ticks) x(tick)],
                      now: axis.now == null ? null : x(axis.now!),
                      walks: [for (final (kind, from, to, _) in segments) if (kind == _Kind.walk) (x(from), x(to))],
                      waits: [for (final (kind, from, to, _) in segments) if (kind == _Kind.wait) (x(from), x(to))],
                      tickColor: theme.colorScheme.outline.withValues(alpha: 0.7),
                      nowColor: theme.colorScheme.primary.withValues(alpha: 0.6),
                      muted: colors.muted,
                    ),
                  ),
                ),
                for (final (kind, from, to, section) in segments)
                  if (kind == _Kind.ride || kind == _Kind.bike || kind == _Kind.other)
                    Positioned(
                      left: x(from) + 1,
                      width: math.max(2, x(to) - x(from) - 2),
                      top: 0,
                      height: height,
                      child: _Block(
                        section: section!,
                        kind: kind,
                        severity: switch (severities[section.line?.id]) {
                          DisruptionSeverity.info => null,
                          final severity => severity,
                        },
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _Kind { ride, walk, wait, bike, other }

/// A ride (its line's color and name), a bike ride or a car ride: a rounded block
class _Block extends StatelessWidget {
  const _Block({required this.section, required this.kind, this.severity});

  final JourneySection section;
  final _Kind kind;
  final DisruptionSeverity? severity;

  @override
  Widget build(BuildContext context) {
    final line = section.line;
    final bikeShare = section.from?.name.startsWith('Station Vélib') ?? false;
    final background = switch (kind) {
      _Kind.ride => parseHexColor(line?.color, Colors.grey.shade600),
      _Kind.bike => bikeShare ? velibColor : bikePathColor,
      _ => context.colors.muted,
    };
    final foreground = kind == _Kind.ride ? parseHexColor(line?.textColor, Colors.white) : Colors.white;
    final block = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        // The name only where it fits
        builder: (context, constraints) => constraints.maxWidth < 16
            ? const SizedBox.shrink()
            : kind == _Kind.ride
                ? Text(
                    line?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w600, height: 1, letterSpacing: -0.3),
                  )
                : Icon(kind == _Kind.bike ? Icons.pedal_bike : Icons.directions_car, size: 16, color: foreground),
      ),
    );
    return severity == null ? block : WithSeverity(severity: severity, dotSize: 10, child: SizedBox.expand(child: block));
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.ticks,
    required this.now,
    required this.walks,
    required this.waits,
    required this.tickColor,
    required this.nowColor,
    required this.muted,
  });

  final List<double> ticks;
  final double? now;
  final List<(double, double)> walks;
  final List<(double, double)> waits;
  final Color tickColor;
  final Color nowColor;
  final Color muted;

  /// Walking dots: their radius and the distance between their centers
  static const _dot = 1.6;
  static const _gap = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    final tick = Paint()
      ..color = tickColor
      ..strokeWidth = 1;
    for (final x in ticks) {
      canvas.drawLine(Offset(x, -4), Offset(x, size.height + 4), tick);
    }
    if (now case final x?) {
      canvas.drawLine(Offset(x, -6), Offset(x, size.height + 6), Paint()
        ..color = nowColor
        ..strokeWidth = 2);
    }
    // Waits: a faint thin line
    final wait = Paint()
      ..color = muted.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final (from, to) in waits) {
      if (to - from > 8) {
        canvas.drawLine(Offset(from + 4, middle), Offset(to - 4, middle), wait);
      }
    }
    // Walks: whole round dots only, evenly spaced and centered, never touching the blocks
    final dot = Paint()..color = muted;
    for (final (from, to) in walks) {
      final room = to - from - 8;
      if (room < 0) {
        continue;
      }
      final count = (room / _gap).floor() + 1;
      final start = from + 4 + (room - (count - 1) * _gap) / 2;
      for (var i = 0; i < count; i++) {
        canvas.drawCircle(Offset(start + i * _gap, middle), _dot, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter oldDelegate) => true;
}

/// Under the results: what the dots and the thin line mean
class TimeBarLegend extends StatelessWidget {
  const TimeBarLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 12);
    final muted = context.colors.muted;
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 18,
            height: 6,
            child: CustomPaint(painter: _BarPainter(ticks: const [], now: null, walks: const [(-4, 22)], waits: const [], tickColor: muted, nowColor: muted, muted: muted)),
          ),
          const SizedBox(width: 6),
          Text(context.l10n.timeAxisWalk, style: style),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 18, height: 2, decoration: BoxDecoration(color: muted.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(1))),
          const SizedBox(width: 6),
          Text(context.l10n.timeAxisWait, style: style),
        ]),
      ],
    );
  }
}
