import 'package:flutter/material.dart';

Color hexToColor(String? hexColor) {
  hexColor = (hexColor ?? '808080').replaceAll('#', '');
  if (hexColor.length == 6) {
    return Color(int.parse('FF$hexColor', radix: 16));
  }
  return Colors.grey;
}