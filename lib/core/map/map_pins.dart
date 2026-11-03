import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'map_overlay.dart';

/// A pin of an overlay: its widget, or a colored dot; a button named by its label when it can be tapped
class PinView extends StatelessWidget {
  const PinView({super.key, required this.pin, required this.outline});

  final MapPin pin;
  final Color outline;

  /// What [pin] looks like, alone: its child, else its colored dot ringed with [outline]
  static Widget marker(MapPin pin, Color outline) =>
      pin.child ??
      Container(
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

  /// The box [pin] is drawn in: its child's, else its dot with room around it to tap it
  static Size boxOf(MapPin pin) => pin.child != null ? pin.childSize : Size.square(pin.size + 16);

  @override
  Widget build(BuildContext context) {
    final marker = PinView.marker(pin, outline);
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

  /// Diameter of the soft halo around the dot
  static const halo = 22.0;

  @override
  Widget build(BuildContext context) {
    final heading = screenHeading;
    final rotation = heading == null ? null : heading * math.pi / 180;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (rotation != null) Transform.rotate(angle: rotation, child: const HeadingCone()),
        Container(
          width: halo,
          height: halo,
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

/// How sure the user's position is, like Google Maps: a soft blue disc of its fix's accuracy around the user dot (the
/// user is somewhere in it), [radius] logical pixels from the middle of its box; under the pins and the dot
class AccuracyCircle extends StatelessWidget {
  const AccuracyCircle({super.key, required this.radius});

  final double radius;

  static final fill = Colors.blue.withValues(alpha: 0.12);
  static final border = Colors.blue.withValues(alpha: 0.3);

  /// The radius (logical pixels) of the circle of [accuracy] meters around a position at [latitude] on a map at [zoom]
  /// whose world is [tileSize] × 2^zoom pixels wide (MapLibre's tiles are 512 px, flutter_map's 256); null when unknown
  /// or within the dot's halo, which says it already
  static double? radiusFor(double? accuracy, double latitude, double zoom, {required double tileSize}) {
    if (accuracy == null) {
      return null;
    }
    // Web Mercator: the equator's length over the world's width in pixels, shrunk by the latitude's cosine
    final metersPerPixel = 40075016.686 * math.cos(latitude * math.pi / 180) / (tileSize * math.pow(2, zoom));
    final radius = accuracy / metersPerPixel;
    return radius > UserDot.halo / 2 ? radius : null;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _AccuracyPainter(radius)));
}

/// [AccuracyCircle]'s disc and its thin edge, around the middle of the box (beyond it when larger)
class _AccuracyPainter extends CustomPainter {
  const _AccuracyPainter(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas
      ..drawCircle(center, radius, Paint()..color = AccuracyCircle.fill)
      ..drawCircle(
        center,
        radius,
        Paint()
          ..color = AccuracyCircle.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(_AccuracyPainter oldDelegate) => oldDelegate.radius != radius;
}

/// The soft cone of [UserDot] pointing up from the middle of its box, the way the user faces
class HeadingCone extends StatelessWidget {
  const HeadingCone({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(size: UserDot.size, painter: const _HeadingPainter());
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
