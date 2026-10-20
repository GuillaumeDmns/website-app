import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'map_overlay.dart';

/// A pin of an overlay: its widget, or a colored dot; a button named by its label when it can be tapped
class PinView extends StatelessWidget {
  const PinView({super.key, required this.pin, required this.outline});

  final MapPin pin;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: pin.size,
      height: pin.size,
      decoration: BoxDecoration(
        color: pin.color,
        shape: BoxShape.circle,
        border: Border.all(color: outline, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
      child: pin.icon == Icons.circle ? null : Icon(pin.icon, size: pin.size * 0.6, color: Colors.white),
    );

    final marker = pin.child ?? dot;
    final child = Center(child: pin.label == null ? marker : Tooltip(message: pin.label!, child: marker));
    if (pin.onTap == null) {
      return child;
    }
    // A button for screen readers, named by the label
    return Semantics(
      button: true,
      label: pin.label,
      excludeSemantics: pin.label != null,
      child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: pin.onTap, child: child)),
    );
  }
}

/// The user's position; with a [screenHeading] (degrees clockwise from the top of the screen), a cone in that
/// direction
class UserDot extends StatelessWidget {
  const UserDot({super.key, this.screenHeading});

  final double? screenHeading;

  /// Size of the box it is drawn in, the dot in its middle
  static const size = Size(72, 72);

  @override
  Widget build(BuildContext context) {
    final heading = screenHeading;
    final rotation = heading == null ? null : heading * math.pi / 180;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (rotation != null)
          Transform.rotate(angle: rotation, child: const CustomPaint(size: Size(72, 72), painter: _HeadingPainter())),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: _dot(),
        ),
      ],
    );
  }

  Widget _dot() {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
    );
  }
}

/// A soft cone pointing up, from the center of the box
class _HeadingPainter extends CustomPainter {
  const _HeadingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx - size.width * 0.3, size.height * 0.04)
      ..quadraticBezierTo(center.dx, -size.height * 0.06, center.dx + size.width * 0.3, size.height * 0.04)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.blue.withValues(alpha: 0.8), Colors.blue.withValues(alpha: 0.05)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, center.dy)),
    );
  }

  @override
  bool shouldRepaint(_HeadingPainter oldDelegate) => false;
}

/// "Recentrer", in the corner above the panel ([bottom] high): the map follows the user again after they moved it
class RecenterButton extends StatelessWidget {
  const RecenterButton({super.key, required this.bottom, required this.onPressed});

  final double bottom;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: EdgeInsets.only(right: 16, bottom: bottom + 16),
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: context.l10n.recenter,
            onPressed: onPressed,
            child: const Icon(Icons.navigation),
          ),
        ),
      );
}
