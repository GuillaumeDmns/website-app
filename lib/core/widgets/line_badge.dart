import 'package:flutter/material.dart';

import '../api/models.dart';
import '../utils/colors.dart';

/// Line badge with the IDFM look: round metro, rounded RER/Transilien, framed tram, square bus.
class LineBadge extends StatelessWidget {
  const LineBadge(this.line, {super.key, this.size = 28});

  final LineSummary line;
  final double size;

  @override
  Widget build(BuildContext context) {
    final background = parseHexColor(line.color, Colors.grey.shade600);
    final foreground = parseHexColor(line.textColor, Colors.white);
    final name = line.name ?? '?';
    final textStyle = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: size * (name.length > 3 ? 0.36 : 0.5),
      height: 1,
      letterSpacing: -0.3,
    );

    return switch (line.mode) {
      TransportMode.metro => _box(
          width: size,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: Text(name, style: textStyle.copyWith(color: foreground)),
        ),
      TransportMode.rer || TransportMode.transilien || TransportMode.ter => _box(
          width: size,
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.25)),
          child: Text(name, style: textStyle.copyWith(color: foreground)),
        ),
      TransportMode.tram => _box(
          minWidth: size,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.symmetric(horizontal: BorderSide(color: background, width: size * 0.14)),
          ),
          child: Text(name, style: textStyle.copyWith(color: Colors.black)),
        ),
      TransportMode.bus || TransportMode.noctilien => _box(
          minWidth: size * 1.3,
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(3)),
          child: Text(name, style: textStyle.copyWith(color: foreground)),
        ),
    };
  }

  Widget _box({double? width, double? minWidth, required Decoration decoration, required Widget child}) {
    return Semantics(
      label: '${line.mode.label} ${line.name ?? ''}',
      excludeSemantics: true,
      // Sized to its content: an aligned Container would otherwise take all the width given by a Wrap
      child: IntrinsicWidth(
        child: Container(
          width: width,
          height: size,
          constraints: minWidth == null ? null : BoxConstraints(minWidth: minWidth),
          padding: width == null ? EdgeInsets.symmetric(horizontal: size * 0.15) : null,
          alignment: Alignment.center,
          decoration: decoration,
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        ),
      ),
    );
  }
}
