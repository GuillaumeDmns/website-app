import 'package:flutter/material.dart';

/// Parses a GTFS hex color (`FFCD00`, with or without `#`), or returns [fallback].
Color parseHexColor(String? hex, Color fallback) {
  final value = hex?.replaceFirst('#', '').trim();
  if (value == null || value.length != 6) {
    return fallback;
  }
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? fallback : Color(0xFF000000 | parsed);
}

/// [color] darker by [amount] (0 to 1) of its lightness
Color darken(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}
