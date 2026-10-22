import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Row of the journey detail's timeline: time on the left, a vertical line (solid or dotted) with an optional stop dot, content
class TimelineRow extends StatelessWidget {
  const TimelineRow({super.key, 
    required this.color,
    required this.child,
    this.time,
    this.dot = false,
    this.stopDot = false,
    this.dotted = false,
    this.isLast = false,
  });

  final Color color;
  final Widget child;
  final String? time;
  final bool dot;

  /// A stop the vehicle passes: a small dot on the line, which goes on
  final bool stopDot;
  final bool dotted;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            // Room for "09:15" at the user's text size
            width: MediaQuery.textScalerOf(context).scale(44),
            child: time == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      time!,
                      style: theme.textTheme.titleSmall?.copyWith(fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
          ),
          SizedBox(
            width: 24,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (!(dot && isLast))
                  Positioned.fill(
                    top: dot ? 8 : 0,
                    child: Center(
                      child: dotted ? _DottedLine(color: color) : Container(width: 5, color: color),
                    ),
                  ),
                if (stopDot)
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
                  ),
                if (dot)
                  Container(
                    margin: const EdgeInsets.only(top: 1),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      // Where the journey ends: filled
                      color: isLast ? color : context.colors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(padding: const EdgeInsets.only(bottom: 4), child: child),
          ),
        ],
      ),
    );
  }
}

/// Vertical dotted line (walking); painted, since the timeline rows are sized with IntrinsicHeight
class _DottedLine extends StatelessWidget {
  const _DottedLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(4, double.infinity), painter: _DotsPainter(color));
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = 2.0; y < size.height; y += 8) {
      canvas.drawCircle(Offset(size.width / 2, y), 2, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => oldDelegate.color != color;
}
